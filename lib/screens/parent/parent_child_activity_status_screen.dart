// parent_child_activity_status_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/app_loading_indicator.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/parent/widgets/parent_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// Parent-facing turn-in tracker for one child: every assigned Activity,
/// grouped by Unit -> Lesson, filtered into three simple buckets —
/// Upcoming, Past Due, Completed — sourced from
/// Database.getChildActivityStatusList(), which mirrors
/// student_activities_screen.dart's exact schedule/due/close logic.
///
/// "Upcoming" is deliberately the only bucket for everything that isn't
/// done and isn't overdue: due today, due tomorrow, due later, and not
/// yet open (scheduled for the future, or locked behind an earlier
/// activity/lesson/unit). The filter chips stay simple on purpose — the
/// finer-grained timing (today/tomorrow/later/why-it's-locked) still
/// shows up as each row's subtitle, just not as extra top-level chips.
class ParentChildActivityStatusScreen extends StatefulWidget {
  final Map<String, dynamic> child;

  const ParentChildActivityStatusScreen({super.key, required this.child});

  @override
  State<ParentChildActivityStatusScreen> createState() =>
      _ParentChildActivityStatusScreenState();
}

class _ParentChildActivityStatusScreenState
    extends State<ParentChildActivityStatusScreen> {
  final Database _db = Database();
  late Future<List<Map<String, dynamic>>> _future;

  // 'upcoming' | 'past_due' | 'completed' — no "All" option, kept simple
  // on request. Defaults to Upcoming since that's what a parent checking
  // in on their child most likely wants to see first.
  String _filter = 'upcoming';

  String get _childName =>
      widget.child['names'] as String? ?? 'common.student'.tr();

  @override
  void initState() {
    super.initState();
    _future = _db.getChildActivityStatusList(
      groupId: widget.child['groupId'] as String,
      studentId: widget.child['id'] as String,
    );
  }

  /// Maps the richer per-activity `status` onto one of the three top-level
  /// filter buckets. 'not_open_yet' items count as Upcoming — they're not
  /// done and not overdue, just not reachable yet.
  bool _matchesFilter(String status) {
    switch (_filter) {
      case 'past_due':
        return status == 'past_due';
      case 'completed':
        return status == 'completed';
      case 'upcoming':
      default:
        return status == 'due_today' ||
            status == 'due_tomorrow' ||
            status == 'later' ||
            status == 'not_open_yet';
    }
  }

  /// Sort rank within the Upcoming bucket so due-today surfaces above
  /// due-tomorrow, above later, above not-yet-open — without reordering
  /// away from the unit/lesson hierarchy those rows are grouped under.
  int _statusRank(String status) {
    switch (status) {
      case 'due_today':
        return 0;
      case 'due_tomorrow':
        return 1;
      case 'later':
        return 2;
      case 'not_open_yet':
        return 3;
      default:
        return 4;
    }
  }

  String _formatDate(DateTime d) {
    final months = [
      'common.monthJan'.tr(),
      'common.monthFeb'.tr(),
      'common.monthMar'.tr(),
      'common.monthApr'.tr(),
      'common.monthMay'.tr(),
      'common.monthJun'.tr(),
      'common.monthJul'.tr(),
      'common.monthAug'.tr(),
      'common.monthSep'.tr(),
      'common.monthOct'.tr(),
      'common.monthNov'.tr(),
      'common.monthDec'.tr(),
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  // Whichever date is actually shown on a card: closeDate when the
  // teacher set one, dueDate otherwise. Never both -- closeDate is the
  // harder, more relevant cutoff (turn_in_widget.dart), so showing the
  // due date alongside it would be redundant/confusing.
  DateTime? _relevantDate(Map<String, dynamic> item) =>
      (item['closeDate'] as DateTime?) ?? (item['dueDate'] as DateTime?);
  String _dateLabel(Map<String, dynamic> item) => item['closeDate'] != null
      ? 'parent.parent_child_activity_status_screen.closes'.tr()
      : 'parent.parent_child_activity_status_screen.due'.tr();

  String _subtitleFor(Map<String, dynamic> item) {
    final status = item['status'] as String;
    final due = item['dueDate'] as DateTime?;
    final close = item['closeDate'] as DateTime?;
    const ns = 'parent.parent_child_activity_status_screen';

    switch (status) {
      case 'completed':
        final stars = item['stars'] as int? ?? 0;
        return stars > 0
            ? '$ns.completedWithStars'.tr(namedArgs: {'stars': '$stars'})
            : '$ns.pillCompleted'.tr();
      case 'past_due':
        if (close != null && close.isBefore(DateTime.now())) {
          return '$ns.windowClosed'.tr();
        }
        if (close != null) {
          // Still overdue on its original due date, but a later close
          // date means there's still a grace window to submit in.
          return '$ns.overdueCloses'.tr(namedArgs: {'date': _formatDate(close)});
        }
        return due == null
            ? '$ns.pastDue'.tr()
            : '$ns.wasDueOverdue'.tr(namedArgs: {'date': _formatDate(due)});
      case 'not_open_yet':
        if (item['notOpenReason'] == 'scheduled') {
          final scheduled = item['scheduledDate'] as DateTime?;
          return scheduled == null
              ? '$ns.notOpenYet'.tr()
              : '$ns.opens'.tr(namedArgs: {'date': _formatDate(scheduled)});
        }
        return '$ns.lockedCompleteEarlier'.tr();
      case 'due_today':
      case 'due_tomorrow':
        final relevant = _relevantDate(item);
        if (relevant == null) {
          return status == 'due_today'
              ? '$ns.dueTodayLower'.tr()
              : '$ns.dueTomorrowLower'.tr();
        }
        return '${_dateLabel(item)} ${_formatDate(relevant)}';
      case 'later':
        final relevant = _relevantDate(item);
        return relevant == null
            ? '$ns.noDueDate'.tr()
            : '${_dateLabel(item)} ${_formatDate(relevant)}';
      default:
        return '';
    }
  }

  ({IconData icon, Color color}) _iconFor(String status) {
    switch (status) {
      case 'completed':
        return (icon: Icons.check_circle, color: AppColors.success);
      case 'past_due':
        return (icon: Icons.warning_amber_rounded, color: AppColors.danger);
      case 'not_open_yet':
        return (icon: Icons.lock_outline, color: Colors.grey);
      case 'due_today':
        return (icon: Icons.today_rounded, color: AppColors.danger);
      case 'due_tomorrow':
        return (icon: Icons.schedule, color: AppColors.warning);
      default:
        return (icon: Icons.event_note_outlined, color: AppColors.info);
    }
  }

  String _pillLabel(String status) {
    const ns = 'parent.parent_child_activity_status_screen';
    switch (status) {
      case 'completed':
        return '$ns.pillCompleted'.tr();
      case 'past_due':
        return '$ns.filterPastDue'.tr();
      case 'not_open_yet':
        return '$ns.pillNotOpenYet'.tr();
      case 'due_today':
        return '$ns.pillDueToday'.tr();
      case 'due_tomorrow':
        return '$ns.pillDueTomorrow'.tr();
      default:
        return '$ns.filterUpcoming'.tr();
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    const ns = 'parent.parent_child_activity_status_screen';
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          ParentScreenHeader(
              title: '$ns.titleActivities'.tr(namedArgs: {'name': _childName})),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              0,
            ),
            child: Row(
              children: [
                Expanded(child: _filterChip(
                    'upcoming', '$ns.filterUpcoming'.tr())),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _filterChip(
                    'past_due', '$ns.filterPastDue'.tr())),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _filterChip(
                    'completed', '$ns.filterCompleted'.tr())),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const AppLoadingIndicator();
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'common.errorWithMessage'
                          .tr(namedArgs: {'error': '${snapshot.error}'}),
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  );
                }

                final all = snapshot.data ?? [];
                // Flat list, one card per activity — no unit/lesson
                // grouping. Preserves the source list's traversal
                // (pedagogical) order by default; the Upcoming tab
                // additionally sorts by due-status rank (due today above
                // due tomorrow above later above not-yet-open) so the
                // most time-sensitive activity surfaces first regardless
                // of which unit/lesson it belongs to.
                final filtered = all
                    .where((item) => _matchesFilter(item['status'] as String))
                    .toList();
                if (_filter == 'upcoming') {
                  filtered.sort(
                    (a, b) => _statusRank(
                      a['status'] as String,
                    ).compareTo(_statusRank(b['status'] as String)),
                  );
                }

                if (filtered.isEmpty) {
                  return _emptyState();
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.lg,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final item = filtered[i];
                    return _ActivityCard(
                      item: item,
                      subtitle: _subtitleFor(item),
                      iconFor: _iconFor,
                      pillLabel: _pillLabel,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label, textAlign: TextAlign.center),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: AppColors.primary,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: selected ? AppColors.onPrimary : AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.divider),
    );
  }

  Widget _emptyState() {
    const ns = 'parent.parent_child_activity_status_screen';
    final message = switch (_filter) {
      'past_due' => '$ns.emptyPastDue'.tr(),
      'completed' => '$ns.emptyCompleted'.tr(),
      _ => '$ns.emptyUpcoming'.tr(),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.checklist_rounded, size: 64, color: Colors.grey[300]),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              style: TextStyle(fontSize: 15, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// One activity, one card — no unit/lesson grouping. The unit name is
// still shown (per request), just as a small label on the card itself
// instead of as a collapsible group header.
class _ActivityCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String subtitle;
  final ({IconData icon, Color color}) Function(String status) iconFor;
  final String Function(String status) pillLabel;

  const _ActivityCard({
    required this.item,
    required this.subtitle,
    required this.iconFor,
    required this.pillLabel,
  });

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final status = item['status'] as String;
    final visuals = iconFor(status);
    final unitTitle = item['unitTitle'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(visuals.icon, color: visuals.color, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (unitTitle.isNotEmpty)
                  Text(
                    unitTitle.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.fieldLabel.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  item['title'] as String,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: visuals.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Text(
              pillLabel(status),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: visuals.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
