// teacher_task_editor_screen.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/create_task_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/hierarchy_list_cards.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/screens/teacher/widgets/task_generator_dialog.dart';
import 'package:loringo_app/screens/teacher/widgets/task_type_selector_screen.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

// Hard ceiling on how many tasks a single Activity may ever contain in
// total, across every batch (Generate or Add Task) plus any tasks added
// individually via Edit over time. This is a DIFFERENT limit from the
// per-batch cap inside TaskGeneratorDialog/TaskTypeSelectorScreen (also
// 15, coincidentally the same number) — that one bounds a single
// operation; this one bounds the activity's lifetime total. Kept here
// since this screen is the only place that knows both the running total
// (from the tasks stream) and is the sole entry point to both creation
// flows.
const int _maxTasksPerActivity = 15;

class TeacherTaskEditorScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final String activityTitle;
  final Color  groupColor;
  final List<String> ancestorTrail;

  const TeacherTaskEditorScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.activityId,
    required this.activityTitle,
    required this.groupColor,
    required this.ancestorTrail,
  });

  @override
  State<TeacherTaskEditorScreen> createState() =>
      _TeacherTaskEditorScreenState();
}

class _TeacherTaskEditorScreenState
    extends State<TeacherTaskEditorScreen> {
  final Database db = Database();

  // ─── Display title resolver ─────────────────────────────────────────────
  // 'title' is now a mandatory top-level field on every task, entered by
  // the teacher when creating/editing (see create_task_screen.dart) — it's
  // what actually identifies the task in this list, independent of
  // whatever content each task type happens to store (a sentence, a chat
  // opener, an image label, etc.).
  //
  // Legacy fallback: tasks created before 'title' existed won't have it.
  // For those, fall back to the old per-type guessing logic so they don't
  // suddenly all show blank — they'll get a real title once a teacher
  // opens and re-saves them (the dirty-check won't block this, since
  // adding a title is itself a change).
  String _displayTitle(Map<String, dynamic> data) {
    final title = data['title'] as String?;
    if (title != null && title.trim().isNotEmpty) return title;

    final type = data['type'] as String? ?? '';
    if (type == 'reading') {
      final inner = data['data'] as Map<String, dynamic>?;
      final innerTitle = inner?['title'] as String?;
      if (innerTitle != null && innerTitle.trim().isNotEmpty) return innerTitle;
    }
    final legacyQuestion = data['question'] as String?;
    if (legacyQuestion != null && legacyQuestion.trim().isNotEmpty) {
      return legacyQuestion;
    }
    return 'Untitled — open to add a title';
  }

  Future<void> _deleteTask(String taskId, String displayTitle) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md)),
            title: const Text('Delete Task'),
            content: const Text('Delete this task?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.sm)),
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;
    try {
      await db.deletePersonalizedTask(
        widget.groupId, widget.contentId, widget.unitId,
        widget.lessonId, widget.activityId, taskId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Task deleted'),
          backgroundColor: AppColors.primary,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.danger,
        ));
      }
    }
  }

  void _editTask(String taskId, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePersonalizedTaskScreen(
          groupId:    widget.groupId,
          contentId:  widget.contentId,
          unitId:     widget.unitId,
          lessonId:   widget.lessonId,
          activityId: widget.activityId,
          groupColor: widget.groupColor,
          taskId:     taskId,
          existingData: {
            'title':    data['title'],
            'question': data['question'],
            'order':    data['order'],
            'type':     data['type'],
            'data':     data['data'],
          },
        ),
      ),
    );
  }

  // ─── "Add Task" entry point ─────────────────────────────────────────────
  // Opens TaskTypeSelectorScreen: the teacher picks exact types with an
  // exact count each (e.g. +2 Image Select, +1 Arrange), then
  // reviews/defines each resulting slot via TaskBatchReviewScreen — the
  // same review flow "Generate" uses. [remaining] is how many more tasks
  // this activity can still hold before hitting _maxTasksPerActivity;
  // the selector screen uses it as its own selection ceiling so the
  // teacher can never queue up more than actually fits.
  void _openTaskTypeSelector(int remaining) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TaskTypeSelectorScreen(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: widget.activityId,
          groupColor: widget.groupColor,
          maxTasks: remaining,
        ),
      ),
    );
  }

  void _openGenerator(int remaining) {
    showDialog(
      context: context,
      builder: (_) => TaskGeneratorDialog(
        groupId: widget.groupId,
        contentId: widget.contentId,
        unitId: widget.unitId,
        lessonId: widget.lessonId,
        activityId: widget.activityId,
        groupColor: widget.groupColor,
        maxTasks: remaining,
      ),
    );
  }

  String _typeLabel(String type) {
    const map = {
      'image_select':         'Image Selection',
      'image_select_reverse': 'Image Select Reverse',
      'fill_blank':           'Fill the Blank',
      'arrange':              'Arrange Words',
      'complete_the_chat':    'Complete Chat',
      'word_match':           'Word Match',
      'match':                'Match',
      'reading':              'Reading',
      'sentence_builder':     'Sentence Builder',
      'repeat_after_me':      'Repeat After Me',
      'listen_and_speak':     'Listen & Speak',
      'sound_match':          'Sound Match',
      'odd_one_out':          'Odd One Out',
    };
    return map[type] ?? type;
  }

  IconData _typeIcon(String type) {
    const map = {
      'image_select':         Icons.image,
      'image_select_reverse': Icons.image_search,
      'fill_blank':           Icons.edit_note,
      'arrange':              Icons.sort,
      'complete_the_chat':    Icons.chat,
      'word_match':           Icons.shuffle,
      'match':                Icons.compare_arrows,
      'reading':              Icons.menu_book,
      'sentence_builder':     Icons.translate,
      'repeat_after_me':      Icons.record_voice_over,
      'listen_and_speak':     Icons.hearing,
      'sound_match':          Icons.volume_up,
      'odd_one_out':          Icons.category_outlined,
    };
    return map[type] ?? Icons.help_outline;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.groupColor;

    return Scaffold(
      // NOTE: no Scaffold.appBar — replaced with TeacherScreenHeader.
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: widget.activityTitle,
            subtitle: 'Tasks',
            color: c,
          ),
          Expanded(
            child: StreamBuilder(
              stream: db.getPersonalizedTasksStream(
                widget.groupId, widget.contentId, widget.unitId,
                widget.lessonId, widget.activityId,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: c));
                }
                final tasks = snapshot.data?.docs ?? [];

                if (tasks.isEmpty) {
                  return HierarchyEmptyState(
                    icon:        Icons.help_outline,
                    title:       'No Tasks Yet',
                    subtitle:    'Tap + to create your first task',
                    color:       c,
                    actionLabel: 'Create First Task',
                    onAction: () => _openTaskTypeSelector(_maxTasksPerActivity),
                  );
                }

                return ListView.builder(
                  // Bottom padding leaves room so the FAB(s) don't cover
                  // the last card in the list.
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.md, AppSpacing.md, 100),
                  itemCount: tasks.length,
                  itemBuilder: (context, i) {
                    final doc      = tasks[i];
                    final data     = doc.data() as Map<String, dynamic>;
                    final displayTitle = _displayTitle(data);
                    final type     = data['type']     ?? 'unknown';
                    final order    = data['order']    ?? 0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.md - 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 3))
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm - 2),
                        leading: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: c.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(AppRadii.md),
                          ),
                          child: Center(
                              child: Icon(_typeIcon(type), color: c, size: 22)),
                        ),
                        title: Text(
                          '$order. $displayTitle',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm, vertical: 2),
                              decoration: BoxDecoration(
                                color: c.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(AppRadii.sm),
                              ),
                              child: Text(_typeLabel(type),
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: c)),
                            ),
                          ),
                        ),
                        trailing: HierarchyPopupActions(
                          onEdit: () => _editTask(doc.id, {
                            'title':    data['title'],
                            'question': data['question'],
                            'order':    order,
                            'type':     type,
                            'data':     data['data'],
                          }),
                          onDelete: () => _deleteTask(doc.id, displayTitle),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),

      // ── FABs, gated by remaining capacity ─────────────────────────────
      // Reads the same tasks stream a second time (StreamBuilder is cheap
      // here — Firestore snapshot listeners are shared/cached per query)
      // purely to compute currentCount for the remaining-slots gate,
      // without restructuring the body's StreamBuilder above.
      floatingActionButton: StreamBuilder(
        stream: db.getPersonalizedTasksStream(
          widget.groupId, widget.contentId, widget.unitId,
          widget.lessonId, widget.activityId,
        ),
        builder: (context, snapshot) {
          final currentCount = snapshot.data?.docs.length ?? 0;
          final remaining = _maxTasksPerActivity - currentCount;
          final isFull = remaining <= 0;

          return Wrap(
            spacing: 12.0,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              if (isFull)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 3)),
                    ],
                  ),
                  child: Text(
                    'Limit reached: $_maxTasksPerActivity tasks max per activity',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700]),
                  ),
                ),

              // ── Auto-Generate Button ──────────────────────────────────
              FloatingActionButton.extended(
                heroTag: null, // Disable hero animation to avoid conflicts
                onPressed: isFull ? null : () => _openGenerator(remaining),
                backgroundColor:
                    isFull ? Colors.grey.shade300 : AppColors.warning,
                elevation: isFull ? 0 : 3,
                icon: Icon(Icons.auto_awesome,
                    color: isFull ? Colors.grey.shade500 : AppColors.onPrimary),
                label: Text('Generate',
                    style: TextStyle(
                        color: isFull ? Colors.grey.shade500 : AppColors.onPrimary,
                        fontWeight: FontWeight.bold)),
              ),

              // ── Add Task Button ───────────────────────────────────────
              FloatingActionButton.extended(
                heroTag: null, // Disable hero animation
                onPressed: isFull ? null : () => _openTaskTypeSelector(remaining),
                backgroundColor: isFull ? Colors.grey.shade300 : c,
                elevation: isFull ? 0 : 3,
                icon: Icon(Icons.add,
                    color: isFull ? Colors.grey.shade500 : AppColors.onPrimary),
                label: Text('Add Task',
                    style: TextStyle(
                        color: isFull ? Colors.grey.shade500 : AppColors.onPrimary,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }
}