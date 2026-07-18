// task_generator_dialog.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/screens/teacher/widgets/task_batch_review_screen.dart';

enum ActivityTaskType {
  vocabulary,
  grammar,
  speakingListening,
  conversation,
}

/// The concrete task types each pedagogical category can produce. This
/// mirrors the taxonomy in kTaskTypeGroups (task_type_option.dart) exactly
/// — same five categories, no type appears in more than one category.
/// Keep both in sync if a task type ever moves category.
///
/// 'reading' is intentionally NOT included here. It's a full passage +
/// comprehension questions — a single, complex, hand-crafted task, not
/// something that belongs in a batch of quick-fire exercises. It stays
/// available only via the normal "Add Task" manual flow (and via
/// TaskTypeSelectorScreen, which does include it since that flow is
/// deliberate per-type selection, not random assignment).
const Map<ActivityTaskType, List<String>> _typesByCategory = {
  ActivityTaskType.vocabulary: [
    'image_select',
    'image_select_reverse',
    'match',
    'sound_match',
    'odd_one_out',
  ],
  ActivityTaskType.grammar: [
    'fill_blank',
    'arrange',
    'sentence_builder',
  ],
  ActivityTaskType.speakingListening: [
    'repeat_after_me',
    'listen_and_speak',
  ],
  ActivityTaskType.conversation: [
    'complete_the_chat',
  ],
};

/// Hard cap on how many tasks can be generated in a single batch,
/// independent of how many distinct types the selected categories offer.
/// Types are picked randomly and CAN repeat (e.g. 2x fill_blank), so the
/// limiting factor is no longer "unique types available" — it's just a
/// sane ceiling so a teacher doesn't accidentally queue up too many tasks
/// to define by hand in one sitting.
const int _maxTasksPerBatch = 15;

/// Dialog for choosing WHICH task types and HOW MANY the teacher wants to
/// create in this batch. It does not generate any task content itself —
/// it only decides the type of each slot. Confirming here pushes
/// TaskBatchReviewScreen, where the teacher opens each slot and fills it
/// in using the normal task editors (same ones used for a single manual
/// task), then creates all of them in Firestore at once.
class TaskGeneratorDialog extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final Color groupColor;

  /// Upper bound on how many tasks can be picked in THIS dialog — driven
  /// by TeacherTaskEditorScreen as (15 total per activity - tasks that
  /// already exist), not a fixed constant. This prevents a teacher with 9
  /// existing tasks from selecting 15 more here and ending up with 24;
  /// the picker itself can never offer more than the activity has room
  /// for. Must be >= 1 — the caller is responsible for not opening this
  /// dialog at all when the activity is already full.
  final int maxTasks;

  const TaskGeneratorDialog({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.activityId,
    required this.groupColor,
    required this.maxTasks,
  });

  @override
  State<TaskGeneratorDialog> createState() => _TaskGeneratorDialogState();
}

class _TaskGeneratorDialogState extends State<TaskGeneratorDialog> {
  Set<ActivityTaskType> _selectedCategories = {ActivityTaskType.vocabulary};
  late int _numberOfTasks;

  Color get _c => widget.groupColor;

  @override
  void initState() {
    super.initState();
    // Default to 3, but never more than what's actually available.
    _numberOfTasks = widget.maxTasks < 3 ? widget.maxTasks : 3;
  }

  /// The distinct concrete types available given the selected categories
  /// (deduplicated — a type appearing in two selected categories still
  /// only counts once as an available "flavor" to draw from).
  List<String> get _typePool {
    final pool = <String>{};
    for (final cat in _selectedCategories) {
      pool.addAll(_typesByCategory[cat]!);
    }
    return pool.toList();
  }

  /// Batch size is bounded by whichever is smaller: the caller-provided
  /// remaining-slots ceiling, or the hard per-batch sanity cap.
  int get _maxTasks =>
      widget.maxTasks < _maxTasksPerBatch ? widget.maxTasks : _maxTasksPerBatch;

  /// Builds the ordered list of concrete types for the batch: for each of
  /// the `_numberOfTasks` slots, picks a random type from the pool of the
  /// selected categories. Types can and will repeat — e.g. 5 Vocabulary
  /// tasks might come out as 2x fill_blank, 2x match, 1x arrange.
  List<String> _buildTypeSelection() {
    final pool = _typePool;
    final random = pool.toList()..shuffle();
    return List.generate(
      _numberOfTasks,
      (i) => random[i % random.length],
    )..shuffle();
  }

  void _proceedToReview() {
    final types = _buildTypeSelection();
    Navigator.pop(context); // close this dialog first
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TaskBatchReviewScreen(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: widget.activityId,
          groupColor: _c,
          types: types,
          // This dialog assigns concrete types at random from the
          // selected pedagogical categories — the teacher never picked
          // exact types, so the review screen should say "Generated".
          isGenerated: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ────────────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.auto_awesome, color: _c, size: 28),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text(
                    'Generate Tasks',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Description ──────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: _c.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: _c),
                          const SizedBox(width: AppSpacing.sm),
                          const Expanded(
                            child: Text(
                              'Pick the categories and how many tasks you want. '
                              'You\'ll define the content of each one next — '
                              'nothing is created yet.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    const Text('Activity Types',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: ActivityTaskType.values.map((type) {
                          return CheckboxListTile(
                            title: Text(_categoryLabel(type)),
                            subtitle: Text(
                              _categoryDescription(type),
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                            value: _selectedCategories.contains(type),
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _selectedCategories.add(type);
                                } else {
                                  _selectedCategories.remove(type);
                                  if (_selectedCategories.isEmpty) {
                                    _selectedCategories.add(ActivityTaskType.vocabulary);
                                  }
                                }
                                if (_numberOfTasks > _maxTasks) {
                                  _numberOfTasks = _maxTasks;
                                }
                              });
                            },
                            activeColor: _c,
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // ── Number of tasks ──────────────────────────────
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Number of Tasks (total)',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: _c.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove),
                                onPressed: _numberOfTasks > 1
                                    ? () => setState(() => _numberOfTasks--)
                                    : null,
                                color: _c,
                              ),
                              Container(
                                width: 32,
                                alignment: Alignment.center,
                                child: Text('$_numberOfTasks',
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: _c)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: _numberOfTasks < _maxTasks
                                    ? () => setState(() => _numberOfTasks++)
                                    : null,
                                color: _c,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      widget.maxTasks < _maxTasksPerBatch
                          ? 'Only $_maxTasks slot${_maxTasks == 1 ? '' : 's'} left in this activity (15 max) · types may repeat'
                          : 'Max per batch: $_maxTasks · types may repeat',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _selectedCategories.isEmpty ? null : _proceedToReview,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _c,
                          foregroundColor: AppColors.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.md)),
                        ),
                        child: Text(
                          'Continue with $_numberOfTasks Task${_numberOfTasks == 1 ? '' : 's'}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryLabel(ActivityTaskType type) {
    switch (type) {
      case ActivityTaskType.vocabulary:
        return 'Vocabulary';
      case ActivityTaskType.grammar:
        return 'Grammar';
      case ActivityTaskType.speakingListening:
        return 'Speaking and Listening';
      case ActivityTaskType.conversation:
        return 'Conversation';
    }
  }

  String _categoryDescription(ActivityTaskType type) {
    switch (type) {
      case ActivityTaskType.vocabulary:
        return 'Image select, image select reverse, match, sound match, odd one out';
      case ActivityTaskType.grammar:
        return 'Fill blank, arrange, sentence builder';
      case ActivityTaskType.speakingListening:
        return 'Repeat after me, listen and speak';
      case ActivityTaskType.conversation:
        return 'Complete the chat';
    }
  }
}