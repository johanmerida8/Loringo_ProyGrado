// task_type_selector_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/create_task_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/task_batch_review_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/task_type_option.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:provider/provider.dart';

// ── TaskTypeSelectorScreen ──────────────────────────────────────────────────
// Replaces the old behavior of "Add Task" (which used to jump straight
// into CreatePersonalizedTaskScreen for a single, type-picked-via-dropdown
// task). Now "Add Task" opens this screen instead.
//
// Design decision — how this differs from "Generate":
// TaskGeneratorDialog lets the teacher pick pedagogical CATEGORIES
// (Vocabulary, Grammar, ...) and a total count; concrete types are then
// assigned randomly from whichever categories were checked. This screen
// is the deliberate opposite: the teacher picks EXACT types with an exact
// count each — e.g. "+2 Image Select, +3 Arrange, +1 Fill Blank" — no
// randomness at all. Both flows converge on the same TaskBatchReviewScreen
// afterward, since that screen only needs an ordered list of concrete
// type strings and doesn't care how they were chosen.
//
// 'reading' IS included here (unlike the Generate dialog, which
// deliberately excludes it as unsuitable for a random batch). Here the
// teacher is explicitly asking for N reading tasks, not getting one
// assigned at random, so there is no risk of an unwanted heavyweight task
// showing up in the batch.
//
// Uses TeacherScreenHeader (no Scaffold.appBar), consistent with the rest
// of the content-creation hierarchy.
class TaskTypeSelectorScreen extends StatefulWidget {
  final String groupId;
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final Color groupColor;
  final int maxTasks;
  final int existingTaskCount;

  /// True only when the activity itself hasn't been written to Firestore
  /// yet — forwarded straight through from TeacherTaskEditorScreen, and
  /// on to TaskBatchReviewScreen. When true, that screen doesn't write
  /// anything either: it hands the defined batch back via
  /// Navigator.pop(context, results), and this screen bubbles that same
  /// result one level further up (see _proceedToReview) so it eventually
  /// reaches create_activity_screen.dart, which does the actual create.
  final bool isPendingActivity;

  const TaskTypeSelectorScreen({
    super.key,
    required this.groupId,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.activityId,
    required this.groupColor,
    required this.maxTasks,
    required this.existingTaskCount,
    this.isPendingActivity = false,
  });

  @override
  State<TaskTypeSelectorScreen> createState() =>
      _TaskTypeSelectorScreenState();
}

class _TaskTypeSelectorScreenState extends State<TaskTypeSelectorScreen> {
  /// typeId -> count. Only types with count > 0 are included in the batch.
  final Map<String, int> _counts = {};

  // reading comprehension is a standalone
  static const String _readingType = 'reading';

  Color get _c => widget.groupColor;

  int get _total => _counts.values.fold(0, (a, b) => a + b);

  bool get _isReadingSelected => (_counts[_readingType] ?? 0) > 0;

  bool get _isOtherTypeSelected => 
      _counts.entries.any((e) => e.key != _readingType && e.value > 0);

  bool get _readingBlockedByExisitingTasks => widget.existingTaskCount > 0;

  bool get _canIncrement => _total < widget.maxTasks;

  void _increment(String typeId) {
    if (!_canIncrement) return;

    // reading comprehension is exclusive: picking it clears out any other selected type
    if (typeId == _readingType) {
      if (_readingBlockedByExisitingTasks) return;
      if (_isOtherTypeSelected) return;
      if ((_counts[_readingType] ?? 0) >= 1) return;
      setState(() => _counts[_readingType] = 1);
      return;
    }

    if (_isReadingSelected) return;

    setState(() => _counts[typeId] = (_counts[typeId] ?? 0) + 1);
  }

  void _decrement(String typeId) {
    final current = _counts[typeId] ?? 0;
    if (current <= 0) return;
    setState(() {
      if (current == 1) {
        _counts.remove(typeId);
      } else {
        _counts[typeId] = current - 1;
      }
    });
  }

  /// Expands the counts map into an ordered flat list of type strings,
  /// e.g. {image_select: 2, arrange: 1} -> [image_select, image_select,
  /// arrange]. This is exactly the shape TaskBatchReviewScreen already
  /// expects (it receives List<String> types from TaskGeneratorDialog
  /// today), so no change is needed on that screen.
  List<String> _buildTypeList() {
    final list = <String>[];
    _counts.forEach((type, count) {
      list.addAll(List.filled(count, type));
    });
    return list;
  }

  Future<void> _proceedToReview() async {
    if (_total == 0) return;
    final result = await Navigator.push<List<BatchTaskResult>>(
      context,
      MaterialPageRoute(
        builder: (_) => TaskBatchReviewScreen(
          groupId: widget.groupId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: widget.activityId,
          groupColor: _c,
          types: _buildTypeList(),
          // The teacher picked exact types and counts here — nothing was
          // assigned randomly — so the review screen should say "Added".
          isGenerated: false,
          isPendingActivity: widget.isPendingActivity,
        ),
      ),
    );
    // Bubble the defined batch one level further up — see the field doc
    // on isPendingActivity. When it's false, TaskBatchReviewScreen wrote
    // everything itself and popped via a named-route popUntil instead, so
    // this await resolves with null and there's nothing to forward.
    if (widget.isPendingActivity && result != null && mounted) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: 'teacher.task_type_selector_screen.addTasks'.tr(),
            subtitle: 'teacher.task_type_selector_screen.chooseTypesAndCount'.tr(),
            color: _c,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, 0, AppSpacing.md, 120),
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: _c.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Row(children: [
                    Icon(Icons.info_outline, color: _c),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'teacher.task_type_selector_screen.pickTypesBannerText'.tr(),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: AppSpacing.md),
                ...kTaskTypeGroups.entries.map(
                  (entry) => _TypeGroupSection(
                    groupName: entry.key,
                    options: entry.value,
                    counts: _counts,
                    color: _c,
                    canIncrement: _canIncrement,
                    isReadingSelected: _isReadingSelected,
                    isOtherTypeSelected: _isOtherTypeSelected,
                    readingBlockedByExistingTasks: _readingBlockedByExisitingTasks,
                    onIncrement: _increment,
                    onDecrement: _decrement,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'teacher.task_type_selector_screen.tasksSelectedProgress'.tr(namedArgs: {
                  'count': '$_total',
                  'max': '${_isReadingSelected ? 1 : widget.maxTasks}',
                }),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _total == 0 ? null : _proceedToReview,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _c,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.md)),
                  ),
                  child: Text(
                    _total == 0
                        ? 'teacher.task_type_selector_screen.selectAtLeastOneTask'.tr()
                        : 'teacher.task_type_selector_screen.continueWithTasks'.plural(_total),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Category section (mirrors the grouping used in the type picker) ────────

class _TypeGroupSection extends StatelessWidget {
  const _TypeGroupSection({
    required this.groupName,
    required this.options,
    required this.counts,
    required this.color,
    required this.canIncrement,
    required this.isReadingSelected,
    required this.isOtherTypeSelected,
    required this.readingBlockedByExistingTasks,
    required this.onIncrement,
    required this.onDecrement,
  });

  final String groupName;
  final List<TaskTypeOption> options;
  final Map<String, int> counts;
  final Color color;
  final bool canIncrement;
  final bool isReadingSelected;
  final bool isOtherTypeSelected;
  final bool readingBlockedByExistingTasks;
  final ValueChanged<String> onIncrement;
  final ValueChanged<String> onDecrement;

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
              top: AppSpacing.md, bottom: AppSpacing.xs),
          child: Text(taskGroupLabel(groupName).toUpperCase(),
              style: AppText.fieldLabel.copyWith(color: AppColors.textSecondary)),
        ),
        ...options.map((option) {
          final isReadingTile = option.id == 'reading';

          final tileCanIncrement = isReadingTile
              ? canIncrement &&
                  !readingBlockedByExistingTasks &&
                  !isOtherTypeSelected &&
                  (counts[option.id] ?? 0) < 1
              : canIncrement && !isReadingSelected;

          String? reason;
          if (isReadingTile && readingBlockedByExistingTasks) {
            reason = 'teacher.task_type_selector_screen.readingBlockedByExistingTasks'.tr();
          } else if (isReadingTile && isOtherTypeSelected) {
            reason = 'teacher.task_type_selector_screen.readingCantCombine'.tr();
          } else if (!isReadingTile && isReadingSelected) {
            reason = 'teacher.task_type_selector_screen.removeReadingToAddOthers'.tr();
          }

          return _TypeCounterTile(
            option: option,
            count: counts[option.id] ?? 0,
            color: color,
            canIncrement: tileCanIncrement,
            lockedReason: reason,
            onIncrement: () => onIncrement(option.id),
            onDecrement: () => onDecrement(option.id),
          );
        }),
      ],
    );
  }
}

// ── Single type row with a +/- counter ──────────────────────────────────────

class _TypeCounterTile extends StatelessWidget {
  const _TypeCounterTile({
    required this.option,
    required this.count,
    required this.color,
    required this.canIncrement,
    this.lockedReason, // NEW
    required this.onIncrement,
    required this.onDecrement,
  });

  final TaskTypeOption option;
  final int count;
  final Color color;
  final bool canIncrement;
  final String? lockedReason; // NEW
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  bool get _isSelected => count > 0;

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: _isSelected ? color.withOpacity(0.08) : AppColors.surface,
        borderRadius: AppRadii.mdAll,
        border: Border.all(
          color: _isSelected ? color : AppColors.divider,
          width: _isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (_isSelected ? color : AppColors.muted).withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: Icon(option.icon,
                  color: _isSelected ? color : AppColors.muted, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                taskTypeLabel(option),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _isSelected ? color : AppColors.textPrimary,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: const Icon(Icons.remove, size: 18),
                  onPressed: count > 0 ? onDecrement : null,
                  color: color,
                  splashRadius: 20,
                ),
                SizedBox(
                  width: 24,
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold, color: color),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: canIncrement ? onIncrement : null,
                  color: color,
                  splashRadius: 20,
                ),
              ]),
            ),
          ]),
          // NEW: inline explanation when this tile is locked by the
          // reading-exclusivity rule specifically (not just "batch full").
          if (lockedReason != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 52),
              child: Text(
                lockedReason!,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ),
          ],
        ],
      ),
    );
  }
}