// task_batch_review_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/create_task_screen.dart';
import 'package:loringo_app/screens/teacher/teacher_task_editor_screen.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:provider/provider.dart';

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
  final map = {
    'image_select': 'teacher.task_batch_review_screen.typeImageSelect'.tr(),
    'image_select_reverse': 'teacher.task_batch_review_screen.typeImageSelectReverse'.tr(),
    'fill_blank': 'teacher.task_batch_review_screen.typeFillBlank'.tr(),
    'arrange': 'teacher.task_batch_review_screen.typeArrange'.tr(),
    'complete_the_chat': 'teacher.task_batch_review_screen.typeCompleteTheChat'.tr(),
    'match': 'teacher.task_batch_review_screen.typeMatch'.tr(),
    'reading': 'teacher.task_batch_review_screen.typeReading'.tr(),
    'sentence_builder': 'teacher.task_batch_review_screen.typeSentenceBuilder'.tr(),
    'repeat_after_me': 'teacher.task_batch_review_screen.typeRepeatAfterMe'.tr(),
    'listen_and_speak': 'teacher.task_batch_review_screen.typeListenAndSpeak'.tr(),
    'sound_match': 'teacher.task_batch_review_screen.typeSoundMatch'.tr(),
    'odd_one_out': 'teacher.task_batch_review_screen.typeOddOneOut'.tr(),
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

  /// True only when the activity itself hasn't been written to Firestore
  /// yet. When true, the bottom button doesn't write anything here at
  /// all — it hands the defined batch back via
  /// Navigator.pop(context, results) for create_activity_screen.dart's
  /// "CREATE ACTIVITY" button to write, together with the activity
  /// itself, in one place. When false (the activity already exists),
  /// this screen writes the batch directly, as it always has.
  final bool isPendingActivity;

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
    this.isPendingActivity = false,
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

  /// Writes every defined slot to Firestore. Only called when the
  /// activity already exists (widget.isPendingActivity is false) —
  /// otherwise _saveAndFinish() bubbles the batch back up instead of
  /// writing anything here. Returns whether it succeeded; on failure
  /// it's already shown the error snackbar, so callers just need to bail
  /// out.
  Future<bool> _persistSlots() async {
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
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('common.errorWithMessage'.tr(namedArgs: {'error': '$e'})),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  /// Bottom button. Two entirely different behaviors depending on
  /// widget.isPendingActivity:
  ///  - Activity already exists: writes this batch directly (as always),
  ///    then walks back to TeacherTaskEditorScreen (the task list).
  ///  - Activity is still pending: writes nothing — just hands the
  ///    defined batch back via Navigator.pop(context, results), for
  ///    create_activity_screen.dart's "CREATE ACTIVITY" button (reached
  ///    once TaskTypeSelectorScreen/TeacherTaskEditorScreen bubble this
  ///    same result further up) to write everything together.
  Future<void> _saveAndFinish() async {
    if (!_allDefined || _isSaving) return;

    if (widget.isPendingActivity) {
      Navigator.pop(context, _slots.map((s) => s.result!).toList());
      return;
    }

    setState(() => _isSaving = true);
    final ok = await _persistSlots();
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('teacher.task_batch_review_screen.tasksCreatedSuccessfully'.plural(_slots.length)),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context)
          .popUntil((route) => route.settings.name == kTeacherTaskEditorRoute);
      return;
    }
    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
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
              widget.isGenerated
                  ? 'teacher.task_batch_review_screen.reviewGeneratedTasks'.tr()
                  : 'teacher.task_batch_review_screen.reviewAddedTasks'.tr(),
              style: const TextStyle(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 17)),
            Text(
                'teacher.task_batch_review_screen.definedProgress'.tr(namedArgs: {
                  'count': '$definedCount',
                  'total': '${_slots.length}',
                }),
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
                  // ListTile paints its background/ink splashes on the
                  // nearest Material ancestor. The Container above used to
                  // carry the white fill itself, which sat between the
                  // ListTile and that ancestor and made both invisible
                  // ("ListTile background color or ink splashes may be
                  // invisible" framework warning). Moving the fill onto a
                  // Material that directly wraps the ListTile makes IT the
                  // nearest ancestor, so there's nothing in between.
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    clipBehavior: Clip.antiAlias,
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
                            : 'teacher.task_batch_review_screen.orderAndType'.tr(namedArgs: {
                                'order': '${slot.order}',
                                'type': typeLabel(slot.type),
                              }),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        slot.isDefined
                            ? typeLabel(slot.type)
                            : 'teacher.task_batch_review_screen.notDefinedYet'.tr(),
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
              onPressed: (_allDefined && !_isSaving) ? _saveAndFinish : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _c,
                foregroundColor: AppColors.onPrimary,
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
                      !_allDefined
                          ? 'teacher.task_batch_review_screen.defineAllTasksToContinue'.tr()
                          : (widget.isPendingActivity ? 'common.continue'.tr() : 'common.save'.tr()),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}