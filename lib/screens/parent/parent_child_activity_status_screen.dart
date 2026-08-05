// parent_child_activity_status_screen.dart
import 'package:flutter/material.dart';
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

  String get _childName => widget.child['names'] as String? ?? 'Student';

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
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  String _subtitleFor(Map<String, dynamic> item) {
    final status = item['status'] as String;
    switch (status) {
      case 'completed':
        final stars = item['stars'] as int? ?? 0;
        return stars > 0 ? 'Completed · $stars★' : 'Completed';
      case 'past_due':
        final due = item['dueDate'] as DateTime?;
        final closeDate = item['closeDate'] as DateTime?;
        if (closeDate != null && closeDate.isBefore(DateTime.now())) {
          return 'Window closed — can no longer be submitted';
        }
        return due == null ? 'Past due' : 'Was due ${_formatDate(due)} — overdue';
      case 'not_open_yet':
        if (item['notOpenReason'] == 'scheduled') {
          final scheduled = item['scheduledDate'] as DateTime?;
          return scheduled == null ? 'Not open yet' : 'Opens ${_formatDate(scheduled)}';
        }
        return 'Locked — complete earlier activities first';
      case 'due_today':
        return 'Due today';
      case 'due_tomorrow':
        return 'Due tomorrow';
      case 'later':
        final due = item['dueDate'] as DateTime?;
        return due == null ? 'No due date' : 'Due ${_formatDate(due)}';
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
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'past_due':
        return 'Past Due';
      case 'not_open_yet':
        return 'Not Open Yet';
      case 'due_today':
        return 'Due Today';
      case 'due_tomorrow':
        return 'Due Tomorrow';
      default:
        return 'Upcoming';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.onPrimary),
        title: Text(
          "$_childName's Activities",
          style: const TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
            child: Row(
              children: [
                Expanded(child: _filterChip('upcoming', 'Upcoming')),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _filterChip('past_due', 'Past Due')),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _filterChip('completed', 'Completed')),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.danger)),
                  );
                }

                final all = snapshot.data ?? [];
                final filtered = all.where((item) => _matchesFilter(item['status'] as String)).toList();

                if (filtered.isEmpty) {
                  return _emptyState();
                }

                // Group by unit, preserving traversal (pedagogical) order
                // from the source list — not re-sorted by due date at the
                // unit/lesson level, only within a lesson's own rows.
                final unitOrder = <String>[];
                final unitTitles = <String, String>{};
                final byUnit = <String, List<Map<String, dynamic>>>{};
                for (final item in all) {
                  final unitId = item['unitId'] as String;
                  if (!byUnit.containsKey(unitId)) {
                    unitOrder.add(unitId);
                    unitTitles[unitId] = item['unitTitle'] as String;
                    byUnit[unitId] = [];
                  }
                }
                for (final item in filtered) {
                  byUnit[item['unitId'] as String]!.add(item);
                }

                final visibleUnitIds =
                    unitOrder.where((id) => byUnit[id]!.isNotEmpty).toList();

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.lg),
                  itemCount: visibleUnitIds.length,
                  itemBuilder: (context, i) {
                    final unitId = visibleUnitIds[i];
                    final unitItems = byUnit[unitId]!;
                    if (_filter == 'upcoming') {
                      unitItems.sort((a, b) =>
                          _statusRank(a['status'] as String).compareTo(_statusRank(b['status'] as String)));
                    }
                    return _UnitSection(
                      title: unitTitles[unitId]!,
                      totalInUnit: all.where((it) => it['unitId'] == unitId).length,
                      shownCount: unitItems.length,
                      items: unitItems,
                      subtitleFor: _subtitleFor,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.divider),
    );
  }

  Widget _emptyState() {
    final message = switch (_filter) {
      'past_due' => 'Nothing past due — all caught up!',
      'completed' => 'No completed activities yet.',
      _ => 'Nothing upcoming right now.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.checklist_rounded, size: 64, color: Colors.grey[300]),
            const SizedBox(height: AppSpacing.md),
            Text(message, style: TextStyle(fontSize: 15, color: Colors.grey[500]), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _UnitSection extends StatelessWidget {
  final String title;
  final int totalInUnit;
  final int shownCount;
  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic>) subtitleFor;
  final ({IconData icon, Color color}) Function(String status) iconFor;
  final String Function(String status) pillLabel;

  const _UnitSection({
    required this.title,
    required this.totalInUnit,
    required this.shownCount,
    required this.items,
    required this.subtitleFor,
    required this.iconFor,
    required this.pillLabel,
  });

  @override
  Widget build(BuildContext context) {
    // Group this unit's (already-filtered) items by lesson, preserving
    // first-seen order — lessons render as non-collapsible sub-headers
    // rather than a nested ExpansionTile, since a two-level collapse has
    // no precedent elsewhere in this app and adds interaction cost for
    // little benefit at this depth.
    final lessonOrder = <String>[];
    final lessonTitles = <String, String>{};
    final byLesson = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final lessonId = item['lessonId'] as String;
      if (!byLesson.containsKey(lessonId)) {
        lessonOrder.add(lessonId);
        lessonTitles[lessonId] = item['lessonTitle'] as String;
        byLesson[lessonId] = [];
      }
      byLesson[lessonId]!.add(item);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          subtitle: Text('$shownCount / $totalInUnit activities',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
          children: [
            for (final lessonId in lessonOrder) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 4),
                child: Text(
                  lessonTitles[lessonId]!.toUpperCase(),
                  style: AppText.fieldLabel.copyWith(color: AppColors.textSecondary),
                ),
              ),
              for (final item in byLesson[lessonId]!) _ActivityRow(
                    item: item,
                    subtitle: subtitleFor(item),
                    iconFor: iconFor,
                    pillLabel: pillLabel,
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final String subtitle;
  final ({IconData icon, Color color}) Function(String status) iconFor;
  final String Function(String status) pillLabel;

  const _ActivityRow({
    required this.item,
    required this.subtitle,
    required this.iconFor,
    required this.pillLabel,
  });

  @override
  Widget build(BuildContext context) {
    final status = item['status'] as String;
    final visuals = iconFor(status);

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 0),
      leading: Icon(visuals.icon, color: visuals.color, size: 22),
      title: Text(
        item['title'] as String,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
        decoration: BoxDecoration(
          color: visuals.color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        child: Text(
          pillLabel(status),
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: visuals.color),
        ),
      ),
    );
  }
}
