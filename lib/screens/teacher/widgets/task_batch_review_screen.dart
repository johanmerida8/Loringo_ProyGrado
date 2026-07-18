// task_batch_review_screen.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/create_task_screen.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// One slot in the batch: a task type + order that's already decided, and
/// an optional [result] once the teacher has gone in and defined its
/// actual content via CreatePersonalizedTaskScreen in batch mode.
class TaskBatchSlot {
  final String type;
  final int order;
  BatchTaskResult? result;

  TaskBatchSlot({required this.type, required this.order, this.result});

  bool get isDefined => result != null;
}

String typeLabel(String type) {
  const map = {
    'image_select': 'Image Selection',
    'image_select_reverse': 'Image Select Reverse',
    'fill_blank': 'Fill the Blank',
    'arrange': 'Arrange Words',
    'complete_the_chat': 'Complete Chat',
    'match': 'Match',
    'reading': 'Reading',
    'sentence_builder': 'Sentence Builder',
    'repeat_after_me': 'Repeat After Me',
    'listen_and_speak': 'Listen & Speak',
    'sound_match': 'Sound Match',
    'odd_one_out': 'Odd One Out',
  };
  return map[type] ?? type;
}

IconData typeIcon(String type) {
  const map = {
    'image_select': Icons.image,
    'image_select_reverse': Icons.image_search,
    'fill_blank': Icons.edit_note,
    'arrange': Icons.sort,
    'complete_the_chat': Icons.chat,
    'match': Icons.compare_arrows,
    'reading': Icons.menu_book,
    'sentence_builder': Icons.translate,
    'repeat_after_me': Icons.record_voice_over,
    'listen_and_speak': Icons.hearing,
    'sound_match': Icons.volume_up,
    'odd_one_out': Icons.category_outlined,
  };
  return map[type] ?? Icons.help_outline;
}

/// Full-screen review list for a batch of tasks the teacher is about to
/// create. Each slot already has its type fixed (chosen either via the
/// random-assignment Generate dialog or the manual type+count picker); the
/// teacher taps into each one to define its real content via the existing
/// per-type editors, then creates all of them in Firestore with a single
/// button once every slot is defined.
class TaskBatchReviewScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final Color groupColor;
  final List<String> types;

  /// True when this batch's types were assigned randomly by
  /// TaskGeneratorDialog (the "Generate" flow); false when the teacher
  /// picked exact types and counts themselves via TaskTypeSelectorScreen
  /// (the "Add Task" flow). Drives the header title only — everything
  /// else about the review/definition process is identical either way.
  final bool isGenerated;

  const TaskBatchReviewScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.activityId,
    required this.groupColor,
    required this.types,
    required this.isGenerated,
  });

  @override
  State<TaskBatchReviewScreen> createState() => _TaskBatchReviewScreenState();
}

class _TaskBatchReviewScreenState extends State<TaskBatchReviewScreen> {
  final Database db = Database();
  late List<TaskBatchSlot> _slots;
  int _startingOrder = 1;
  bool _isSaving = false;
  bool _loadingOrder = true;

  Color get _c => widget.groupColor;

  @override
  void initState() {
    super.initState();
    _slots = [
      for (int i = 0; i < widget.types.length; i++)
        TaskBatchSlot(type: widget.types[i], order: i + 1),
    ];
    _prefillStartingOrder();
  }

  Future<void> _prefillStartingOrder() async {
    try {
      final snap = await db.getPersonalizedTasks(
        widget.groupId,
        widget.contentId,
        widget.unitId,
        widget.lessonId,
        widget.activityId,
      );
      _startingOrder = snap.docs.length + 1;
    } catch (_) {
      _startingOrder = 1;
    } finally {
      if (mounted) {
        setState(() {
          for (int i = 0; i < _slots.length; i++) {
            _slots[i] = TaskBatchSlot(
              type: _slots[i].type,
              order: _startingOrder + i,
              result: _slots[i].result,
            );
          }
          _loadingOrder = false;
        });
      }
    }
  }

  Future<void> _defineSlot(int index) async {
    final slot = _slots[index];
    final result = await Navigator.push<BatchTaskResult>(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePersonalizedTaskScreen(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: widget.activityId,
          groupColor: _c,
          batchMode: true,
          fixedType: slot.type,
          existingData: slot.result == null
              ? null
              : {
                  'title': slot.result!.title,
                  'question': slot.result!.question,
                  'type': slot.result!.type,
                  'data': slot.result!.data,
                },
        ),
      ),
    );

    if (result != null) {
      setState(() => _slots[index].result = result);
    }
  }

  bool get _allDefined => _slots.every((s) => s.isDefined);

  Future<void> _createAll() async {
    if (!_allDefined) return;
    setState(() => _isSaving = true);

    try {
      int order = _startingOrder;
      for (final slot in _slots) {
        final r = slot.result!;
        final taskId =
            'task_${DateTime.now().millisecondsSinceEpoch}_$order';
        await db.createPersonalizedTask(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: widget.activityId,
          taskId: taskId,
          type: r.type,
          title: r.title,
          question: r.question,
          order: order,
          data: r.data,
        );
        order++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_slots.length} tasks created successfully!'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context); // back to task list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final definedCount = _slots.where((s) => s.isDefined).length;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: _c,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.onPrimary),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.isGenerated ? 'Review Generated Tasks' : 'Review Added Tasks',
              style: const TextStyle(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 17)),
            Text('$definedCount / ${_slots.length} defined',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
      body: _loadingOrder
          ? Center(child: CircularProgressIndicator(color: _c))
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: _slots.length,
              itemBuilder: (context, i) {
                final slot = _slots[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(
                      color: slot.isDefined
                          ? _c.withOpacity(0.4)
                          : Colors.grey.shade300,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: 4),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: (slot.isDefined ? _c : Colors.grey)
                            .withOpacity(0.12),
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Icon(typeIcon(slot.type),
                          color: slot.isDefined ? _c : Colors.grey.shade500),
                    ),
                    title: Text(
                      slot.isDefined
                          ? slot.result!.title
                          : '${slot.order}. ${typeLabel(slot.type)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      slot.isDefined
                          ? typeLabel(slot.type)
                          : 'Not defined yet — tap to configure',
                      style: TextStyle(
                        fontSize: 12,
                        color: slot.isDefined
                            ? Colors.grey[600]
                            : Colors.orange.shade700,
                      ),
                    ),
                    trailing: IconButton(
                      icon: Icon(
                        slot.isDefined
                            ? Icons.check_circle
                            : Icons.remove_red_eye_outlined,
                        color: slot.isDefined ? AppColors.success : _c,
                      ),
                      onPressed: () => _defineSlot(i),
                    ),
                    onTap: () => _defineSlot(i),
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_allDefined && !_isSaving) ? _createAll : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _c,
                padding: const EdgeInsets.symmetric(vertical: 14),
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.md)),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _allDefined
                          ? 'Create ${_slots.length} Tasks'
                          : 'Define all tasks to continue',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}