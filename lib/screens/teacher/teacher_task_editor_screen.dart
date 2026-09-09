// teacher_task_editor_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/create_task_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/hierarchy_list_cards.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/screens/teacher/widgets/task_batch_review_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/task_generator_dialog.dart';
import 'package:loringo_app/screens/teacher/widgets/task_type_option.dart';
import 'package:loringo_app/screens/teacher/widgets/task_type_selector_screen.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

// Route name stamped on every MaterialPageRoute that pushes this screen
// (teacher_activity_editor_screen.dart, teacher_activity_screen.dart,
// create_activity_screen.dart's post-create "Continue" hop). Lets
// task_batch_review_screen.dart's Save button walk back here with
// Navigator.popUntil for the normal (activity-already-exists) case.
const String kTeacherTaskEditorRoute = 'teacherTaskEditor';

class TeacherTaskEditorScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final String activityTitle;
  final Color groupColor;
  final List<String> ancestorTrail;

  /// True only when this screen was reached straight from
  /// create_activity_screen.dart's "CONTINUE" button for a brand-new
  /// activity that hasn't been written to Firestore yet. In that state
  /// the task stream below is legitimately empty (nothing exists yet,
  /// not even the activity doc), and "Generate"/"Add Task" must bubble
  /// the eventually-defined batch of tasks all the way back up to
  /// create_activity_screen.dart (see _openTaskTypeSelector/_openGenerator)
  /// instead of writing anything themselves — that screen's "CREATE
  /// ACTIVITY" button is what actually creates the activity + tasks
  /// together. False for every other entry point (editing, or an
  /// activity's normal task list), where the activity already exists and
  /// this screen behaves exactly as it always has.
  final bool isPendingActivity;

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
    this.isPendingActivity = false,
  });

  @override
  State<TeacherTaskEditorScreen> createState() =>
      _TeacherTaskEditorScreenState();
}

class _TeacherTaskEditorScreenState extends State<TeacherTaskEditorScreen> {
  final Database db = Database();

  // Same optimistic-local-copy pattern as
  // teacher_activity_editor_screen.dart's _reorderingItems -- keeps the
  // dragged item's new position visible during the confirm dialog instead
  // of snapping back to the stream's still-unwritten order.
  List<QueryDocumentSnapshot>? _reorderingItems;

  Future<void> _handleReorder(
    List<QueryDocumentSnapshot> current,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final reordered = List<QueryDocumentSnapshot>.from(current);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    setState(() => _reorderingItems = reordered);

    final movedTitle = _displayTitle(moved.data() as Map<String, dynamic>);
    final confirm =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            title: Text('teacher.teacher_task_editor_screen.reorderTasks'.tr()),
            content: Text(
              'teacher.teacher_task_editor_screen.moveToPosition'.tr(
                namedArgs: {
                  'title': movedTitle,
                  'position': '${newIndex + 1}',
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('common.cancel'.tr()),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.groupColor,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                ),
                child: Text('common.confirm'.tr()),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) {
      if (mounted) setState(() => _reorderingItems = null);
      return;
    }

    try {
      await db.reorderPersonalizedTasks(
        contentId: widget.contentId,
        unitId: widget.unitId,
        lessonId: widget.lessonId,
        activityId: widget.activityId,
        orderedTaskIds: reordered.map((d) => d.id).toList(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('common.errorWithMessage'.tr(namedArgs: {'error': '$e'})),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _reorderingItems = null);
    }
  }

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
    return 'teacher.teacher_task_editor_screen.untitledOpenToAddTitle'.tr();
  }

  Future<void> _deleteTask(String taskId, String displayTitle) async {
    final confirm =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            title: Text('teacher.teacher_task_editor_screen.deleteTask'.tr()),
            content: Text(
              'teacher.teacher_task_editor_screen.deleteThisTask'.tr(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('common.cancel'.tr()),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                ),
                child: Text('common.delete'.tr()),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;
    try {
      await db.deletePersonalizedTask(
        widget.groupId,
        widget.contentId,
        widget.unitId,
        widget.lessonId,
        widget.activityId,
        taskId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('teacher.teacher_task_editor_screen.taskDeleted'.tr()),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('common.errorWithMessage'.tr(namedArgs: {'error': '$e'})),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  void _editTask(String taskId, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePersonalizedTaskScreen(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: widget.activityId,
          groupColor: widget.groupColor,
          taskId: taskId,
          existingData: {
            'title': data['title'],
            'question': data['question'],
            'order': data['order'],
            'type': data['type'],
            'data': data['data'],
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
  // this activity can still hold before hitting kMaxTasksPerActivity;
  // the selector screen uses it as its own selection ceiling so the
  // teacher can never queue up more than actually fits.
  Future<void> _openTaskTypeSelector(int remaining) async {
    final existingTaskCount = kMaxTasksPerActivity - remaining;
    // This screen's State outlives normal navigation (it's the same
    // pushed route throughout), so widget.isPendingActivity alone can't
    // tell us "still unsaved" once a task genuinely exists. Once a task
    // exists, the activity is guaranteed to exist too, so only treat this
    // as the still-pending flow when there's genuinely nothing there yet.
    final isPending = widget.isPendingActivity && existingTaskCount == 0;
    final result = await Navigator.push<List<BatchTaskResult>>(
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
          existingTaskCount: existingTaskCount,
          isPendingActivity: isPending,
        ),
      ),
    );
    // Bubble the defined batch up to whatever pushed this screen — for
    // the pending-activity flow, that's create_activity_screen.dart,
    // whose "CREATE ACTIVITY" button does the actual write.
    if (isPending && result != null && mounted) {
      Navigator.pop(context, result);
    }
  }

  Future<void> _openGenerator(int remaining) async {
    final existingTaskCount = kMaxTasksPerActivity - remaining;
    final isPending = widget.isPendingActivity && existingTaskCount == 0;

    // TaskGeneratorDialog only picks types now — it hands them back via
    // Navigator.pop(context, types) rather than pushing
    // TaskBatchReviewScreen itself. That push (and the await on ITS
    // result) has to happen here instead: a Dialog route's context isn't
    // safely reusable by the time a teacher finishes defining a whole
    // batch of tasks, which broke bubbling results for the
    // pending-activity flow when the dialog tried to do it directly.
    final types = await showDialog<List<String>>(
      context: context,
      builder: (_) => TaskGeneratorDialog(
        groupColor: widget.groupColor,
        maxTasks: remaining,
      ),
    );
    if (types == null || types.isEmpty || !mounted) return;

    final result = await Navigator.push<List<BatchTaskResult>>(
      context,
      MaterialPageRoute(
        builder: (_) => TaskBatchReviewScreen(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: widget.activityId,
          groupColor: widget.groupColor,
          types: types,
          // TaskGeneratorDialog assigns concrete types at random from
          // the selected pedagogical categories — the teacher never
          // picked exact types — so the review screen should say
          // "Generated".
          isGenerated: true,
          isPendingActivity: isPending,
        ),
      ),
    );
    if (isPending && result != null && mounted) {
      Navigator.pop(context, result);
    }
  }

  String _typeLabel(String type) {
    final map = {
      'image_select': 'teacher.teacher_task_editor_screen.typeImageSelect'.tr(),
      'image_select_reverse':
          'teacher.teacher_task_editor_screen.typeImageSelectReverse'.tr(),
      'fill_blank': 'teacher.teacher_task_editor_screen.typeFillBlank'.tr(),
      'arrange': 'teacher.teacher_task_editor_screen.typeArrange'.tr(),
      'complete_the_chat':
          'teacher.teacher_task_editor_screen.typeCompleteTheChat'.tr(),
      'word_match': 'teacher.teacher_task_editor_screen.typeWordMatch'.tr(),
      'match': 'teacher.teacher_task_editor_screen.typeMatch'.tr(),
      'reading': 'teacher.teacher_task_editor_screen.typeReading'.tr(),
      'sentence_builder':
          'teacher.teacher_task_editor_screen.typeSentenceBuilder'.tr(),
      'repeat_after_me':
          'teacher.teacher_task_editor_screen.typeRepeatAfterMe'.tr(),
      'listen_and_speak':
          'teacher.teacher_task_editor_screen.typeListenAndSpeak'.tr(),
      'sound_match': 'teacher.teacher_task_editor_screen.typeSoundMatch'.tr(),
      'odd_one_out': 'teacher.teacher_task_editor_screen.typeOddOneOut'.tr(),
    };
    return map[type] ?? type;
  }

  IconData _typeIcon(String type) {
    const map = {
      'image_select': Icons.image,
      'image_select_reverse': Icons.image_search,
      'fill_blank': Icons.edit_note,
      'arrange': Icons.sort,
      'complete_the_chat': Icons.chat,
      'word_match': Icons.shuffle,
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

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final c = widget.groupColor;

    return Scaffold(
      // NOTE: no Scaffold.appBar — replaced with TeacherScreenHeader.
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: widget.activityTitle,
            subtitle: 'teacher.teacher_task_editor_screen.tasks'.tr(),
            color: c,
          ),
          // Nothing has been saved to Firestore yet — see the field doc
          // on isPendingActivity. Makes the deferred-write state visible
          // instead of leaving the teacher to assume the activity already
          // exists just because they're looking at its task screen.
          //
          // Deliberately re-derived from the live tasks stream (docs
          // empty) rather than just checking widget.isPendingActivity:
          // this State object is never disposed across ordinary
          // navigation (it's the same pushed route throughout), so the
          // flag alone can't reflect "a task now exists" — reading the
          // stream instead makes the banner self-correct the moment one
          // shows up, no manual state to keep in sync.
          if (widget.isPendingActivity)
            StreamBuilder(
              stream: db.getPersonalizedTasksStream(
                widget.groupId,
                widget.contentId,
                widget.unitId,
                widget.lessonId,
                widget.activityId,
              ),
              builder: (context, snapshot) {
                final hasAnyTask = (snapshot.data?.docs ?? []).isNotEmpty;
                if (hasAnyTask) return const SizedBox.shrink();
                return Container(
                  width: double.infinity,
                  color: AppColors.warning.withOpacity(0.12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: AppColors.warning,
                        size: 16,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'teacher.teacher_task_editor_screen.notSavedYetBanner'
                              .tr(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          Expanded(
            child: StreamBuilder(
              stream: db.getPersonalizedTasksStream(
                widget.groupId,
                widget.contentId,
                widget.unitId,
                widget.lessonId,
                widget.activityId,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: c));
                }
                final streamTasks = snapshot.data?.docs ?? [];
                final tasks = _reorderingItems ?? streamTasks;

                if (tasks.isEmpty) {
                  return HierarchyEmptyState(
                    icon: Icons.help_outline,
                    title: 'teacher.teacher_task_editor_screen.noTasksYet'.tr(),
                    subtitle:
                        'teacher.teacher_task_editor_screen.tapPlusToCreateFirstTask'
                            .tr(),
                    color: c,
                    actionLabel:
                        'teacher.teacher_task_editor_screen.createFirstTask'
                            .tr(),
                    onAction: () => _openTaskTypeSelector(kMaxTasksPerActivity),
                  );
                }

                return ReorderableListView.builder(
                  // Bottom padding leaves room so the FAB(s) don't cover
                  // the last card in the list.
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    100,
                  ),
                  itemCount: tasks.length,
                  // Off: its automatic web/desktop handle appends at the
                  // TRAILING edge of every item, landing right on top of
                  // this tile's own "⋮" popup menu. We provide our own
                  // handle placement instead -- see below.
                  buildDefaultDragHandles: false,
                  onReorder: (oldIndex, newIndex) =>
                      _handleReorder(tasks, oldIndex, newIndex),
                  itemBuilder: (context, i) {
                    final doc = tasks[i];
                    final data = doc.data() as Map<String, dynamic>;
                    final displayTitle = _displayTitle(data);
                    final type = data['type'] ?? 'unknown';
                    final order = data['order'] ?? 0;

                    final card = Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.md - 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm - 2,
                        ),
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Web/mouse: no long-press gesture exists, so
                            // give it an explicit handle rendered as part
                            // of this tile itself. Mobile/touch: nothing
                            // here -- unchanged long-press-anywhere, via
                            // the delayed-drag listener wrapping the
                            // whole tile below.
                            if (kIsWeb) ...[
                              ReorderableDragStartListener(
                                index: i,
                                child: Icon(
                                  Icons.drag_indicator_rounded,
                                  color: Colors.grey[400],
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                            ],
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: c.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(
                                  AppRadii.md,
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  _typeIcon(type),
                                  color: c,
                                  size: 22,
                                ),
                              ),
                            ),
                          ],
                        ),
                        title: Text(
                          '$order. $displayTitle',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
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
                                horizontal: AppSpacing.sm,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: c.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(
                                  AppRadii.sm,
                                ),
                              ),
                              child: Text(
                                _typeLabel(type),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: c,
                                ),
                              ),
                            ),
                          ),
                        ),
                        trailing: HierarchyPopupActions(
                          onEdit: () => _editTask(doc.id, {
                            'title': data['title'],
                            'question': data['question'],
                            'order': order,
                            'type': type,
                            'data': data['data'],
                          }),
                          onDelete: () => _deleteTask(doc.id, displayTitle),
                        ),
                      ),
                    );

                    // Web: the tile's own drag handle (above, in
                    // `leading`) already registers the drag start, so
                    // just key it. Mobile: wrap the whole tile so
                    // long-press-anywhere works, same delayed-drag
                    // listener buildDefaultDragHandles uses internally
                    // for touch platforms.
                    if (kIsWeb) {
                      return KeyedSubtree(key: ValueKey(doc.id), child: card);
                    }
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(doc.id),
                      index: i,
                      child: card,
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
          widget.groupId,
          widget.contentId,
          widget.unitId,
          widget.lessonId,
          widget.activityId,
        ),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          final currentCount = docs.length;
          final remaining = kMaxTasksPerActivity - currentCount;
          final isFull = remaining <= 0;
          // NEW: whether the activity's existing tasks already include a
          // Reading Comprehension task -- if so, the activity is fully
          // closed (Reading is always solo), and "Add Task"/"Generate"
          // should reflect that instead of offering normal slots.
          final hasExistingReading = docs.any((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['type'] == 'reading';
          });

          return Wrap(
            spacing: 12.0,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              if (isFull)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    'teacher.teacher_task_editor_screen.limitReached'.tr(
                      namedArgs: {'max': '$kMaxTasksPerActivity'},
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                )
              // NEW: activity is closed by an existing Reading task -- show
              // a clear explanation instead of the normal FABs, since
              // neither Generate nor Add Task can offer anything here.
              else if (hasExistingReading)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25.0),
                    child: Text(
                      'teacher.teacher_task_editor_screen.readingBlocksOtherTasks'
                          .tr(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                )
              else ...[
                FloatingActionButton.extended(
                  heroTag: null,
                  onPressed: () => _openGenerator(remaining),
                  backgroundColor: AppColors.warning,
                  elevation: 3,
                  icon: const Icon(
                    Icons.auto_awesome,
                    color: AppColors.onPrimary,
                  ),
                  label: Text(
                    'teacher.teacher_task_editor_screen.generate'.tr(),
                    style: const TextStyle(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                FloatingActionButton.extended(
                  heroTag: null,
                  onPressed: () => _openTaskTypeSelector(remaining),
                  backgroundColor: c,
                  elevation: 3,
                  icon: const Icon(Icons.add, color: AppColors.onPrimary),
                  label: Text(
                    'teacher.teacher_task_editor_screen.addTask'.tr(),
                    style: const TextStyle(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
