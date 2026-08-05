// lib/screens/parent/parent_home_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/notification_permission_card.dart';
import 'package:loringo_app/components/notifications_badge.dart';
import 'package:loringo_app/providers/notification_provider.dart';
import 'package:loringo_app/screens/parent/child_report_detail_screen.dart';
import 'package:loringo_app/screens/parent/parent_child_activity_status_screen.dart';
import 'package:loringo_app/screens/parent/parent_profile_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/task_type_option.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// The "Home" tab content for the parent role.
///
/// Deliberately scoped to the two things a parent actually opens this
/// screen to do: **follow up** on whether their kids are keeping up with
/// assigned work (Past Due / Due Today counts + a live list, sourced from
/// Database.getChildActivityStatusList — the same method backing each
/// child's dedicated Activities screen, so the numbers here always match
/// what a parent finds when they tap in), and **check performance**
/// (Skill Insights + Recent Activity, both report/score-driven). No
/// generic vanity counts (child count, group count, overall average
/// score) — if it doesn't help a parent decide whether to check in with
/// a kid, it doesn't belong on this screen.
class ParentHomeScreen extends StatelessWidget {
  final bool isWide;
  final String parentName;
  final String parentEmail;
  final String? parentUserId;
  final List<Map<String, dynamic>> myChildren;
  final Map<String, String> groupNames;
  final Map<String, List<Map<String, dynamic>>> childReports;
  final String Function(DateTime) formatDate;
  final VoidCallback onSeeAllChildren;
  final VoidCallback onNavigateToNotifications;
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  const ParentHomeScreen({
    super.key,
    required this.isWide,
    required this.parentName,
    required this.parentEmail,
    required this.parentUserId,
    required this.myChildren,
    required this.groupNames,
    required this.childReports,
    required this.formatDate,
    required this.onSeeAllChildren,
    required this.onNavigateToNotifications,
    required this.onLogout,
    required this.onDeleteAccount,
  });

  /// Latest report per child (by generatedAt), most recent first, capped
  /// to a handful for the feed.
  List<_ActivityEntry> get _recentActivity {
    final entries = <_ActivityEntry>[];
    for (final child in myChildren) {
      final childId = child['id'] as String?;
      if (childId == null) continue;
      final reports = childReports[childId];
      if (reports == null || reports.isEmpty) continue;
      entries.add(_ActivityEntry(child: child, report: reports.first));
    }
    entries.sort((a, b) {
      final aTs = a.report['generatedAt'] as Timestamp?;
      final bTs = b.report['generatedAt'] as Timestamp?;
      if (aTs == null || bTs == null) return 0;
      return bTs.compareTo(aTs);
    });
    return entries.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final activity = _recentActivity;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (!isWide)
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ParentProfileScreen(
                          parentName: parentName,
                          parentEmail: parentEmail,
                          parentId: parentUserId,
                          onLogout: onLogout,
                          onDeleteAccount: onDeleteAccount,
                        ),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.person_rounded,
                          color: AppColors.primary, size: 24),
                    ),
                  )
                else
                  const SizedBox.shrink(),
                NotificationBadge(
                  userId: parentUserId ?? '',
                  onTap: onNavigateToNotifications,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
              decoration: BoxDecoration(
                  color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
              child: Text('Hello, $parentName!',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),

          if (!kIsWeb)
            Consumer<NotificationProvider>(
              builder: (context, notificationProvider, child) {
                if (notificationProvider.isLoading) return const SizedBox.shrink();
                if (!notificationProvider.isEnabled &&
                    !notificationProvider.isPermanentlyDenied) {
                  return NotificationPermissionCard(
                    onRequestPermission: () async {
                      await notificationProvider.enableNotifications(context);
                    },
                  );
                }
                return const SizedBox.shrink();
              },
            ),

          // ── Follow-ups: Past Due / Due Today counts + the list ──
          // The first thing a parent sees below the greeting — this IS
          // the "should I check in with my kid" answer, sourced from the
          // same Database.getChildActivityStatusList() the per-child
          // Activities screen uses, so the numbers here never disagree
          // with what a parent finds after tapping in.
          _FollowUpsSection(myChildren: myChildren, formatDate: formatDate),

          // ── Task-type insights ──
          _TaskInsightsSection(myChildren: myChildren),

          // ── Recent activity feed ──
          if (activity.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('Recent Activity',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: isWide
                  ? GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 3.6,
                      children: activity
                          .map((e) => _activityTile(context, e))
                          .toList(),
                    )
                  : Column(
                      children: activity
                          .map((e) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _activityTile(context, e),
                              ))
                          .toList(),
                    ),
            ),
          ],

          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('My Children',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: onSeeAllChildren,
                  icon: const Icon(Icons.arrow_forward,
                      size: 16, color: AppColors.primary),
                  label: const Text('See all',
                      style: TextStyle(color: AppColors.primary)),
                ),
              ],
            ),
          ),
          if (myChildren.isEmpty)
            _emptyPlaceholder()
          else if (isWide)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 4,
                children: myChildren
                    .take(6)
                    .map((child) => _buildChildSummaryCard(child))
                    .toList(),
              ),
            )
          else
            ...myChildren.take(3).map((child) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: _buildChildSummaryCard(child),
                )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _activityTile(BuildContext context, _ActivityEntry entry) {
    final child = entry.child;
    final report = entry.report;
    final childName = child['names'] as String? ?? 'Student';
    final unitTitle = report['unitTitle'] as String? ?? 'Unit';
    final percent = (report['quizPercent'] as num?)?.toInt() ?? 0;
    final generatedAt = report['generatedAt'] as Timestamp?;
    final dateStr = generatedAt != null ? formatDate(generatedAt.toDate()) : '';
    final scoreColor = percent >= 80
        ? const Color(0xFF4CAF50)
        : (percent >= 60 ? const Color(0xFFFFC107) : const Color(0xFFFF7043));
    final childId = child['id'] as String?;
    final allReports = childId != null ? (childReports[childId] ?? []) : <Map<String, dynamic>>[];

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: allReports.isEmpty
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChildReportDetailScreen(
                      child: child,
                      reports: allReports,
                      formatDate: formatDate,
                    ),
                  ),
                ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 40,
                decoration: BoxDecoration(
                  color: scoreColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$childName completed $unitTitle',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(dateStr,
                        style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('$percent%',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: scoreColor)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChildSummaryCard(Map<String, dynamic> child) {
    final childId = child['id'] as String?;
    final groupId = child['groupId'] as String?;
    if (childId == null || groupId == null || groupId.isEmpty) {
      return _childSummaryCardInner(child, overdueCount: 0);
    }

    // Inactivity signal, per the agreed definition: not idle-timer
    // based, just "how many assigned activities are past due and still
    // incomplete" — same Database method the Follow-ups section and the
    // per-child Activities screen use, just reduced to a count here.
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Database().getChildActivityStatusList(groupId: groupId, studentId: childId),
      builder: (context, snapshot) {
        final overdueCount =
            (snapshot.data ?? const []).where((i) => i['status'] == 'past_due').length;
        return _childSummaryCardInner(child, overdueCount: overdueCount);
      },
    );
  }

  Widget _childSummaryCardInner(Map<String, dynamic> child, {required int overdueCount}) {
    final hasGroup = (child['groupId'] as String?)?.isNotEmpty == true;
    final avatarPath = child['avatar'] as String? ?? 'assets/avatars/panda.png';
    final childName = child['names'] as String? ?? 'Student';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primarySoft(0.15),
            child: ClipOval(
              child: Image.asset(
                avatarPath,
                fit: BoxFit.cover,
                width: 48,
                height: 48,
                errorBuilder: (context, error, stackTrace) {
                  return Text(
                    childName[0].toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      fontSize: 18,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        childName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (overdueCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$overdueCount overdue',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  hasGroup
                      ? groupNames[child['id']] ?? 'Unknown Group'
                      : 'No group assigned',
                  style: TextStyle(
                    fontSize: 12,
                    color: hasGroup ? AppColors.primary : Colors.orange,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyPlaceholder() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.child_care_rounded, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 10),
            Text('No children registered yet', style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}

class _ActivityEntry {
  final Map<String, dynamic> child;
  final Map<String, dynamic> report;
  const _ActivityEntry({required this.child, required this.report});
}

// ── Follow-ups section: Past Due / Due Today counts + the list ─────────
//
// Single shared data source for this screen's whole "should I check in
// with my kid" story: one Database.getChildActivityStatusList() call per
// child (Future.wait'd together), tagged with childId/childName, then
// both the two count cards and the list below read from the same
// fetched data — no separate ad hoc query duplicating this logic (that's
// what the old _UpcomingOverdueSection/fetchChildDueItems did, and it
// didn't agree with the per-child Activities screen on what "overdue"
// even meant, since it skipped closeDate/schedule/lock entirely).
class _FollowUpsSection extends StatefulWidget {
  final List<Map<String, dynamic>> myChildren;
  final String Function(DateTime) formatDate;

  const _FollowUpsSection({
    required this.myChildren,
    required this.formatDate,
  });

  @override
  State<_FollowUpsSection> createState() => _FollowUpsSectionState();
}

class _FollowUpsSectionState extends State<_FollowUpsSection> {
  final Database _db = Database();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _FollowUpsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.myChildren != widget.myChildren) {
      _future = _load();
    }
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final results = await Future.wait(widget.myChildren.map((child) async {
      final childId = child['id'] as String?;
      final groupId = child['groupId'] as String?;
      if (childId == null || groupId == null || groupId.isEmpty) {
        return <Map<String, dynamic>>[];
      }
      final items = await _db.getChildActivityStatusList(groupId: groupId, studentId: childId);
      final childName = child['names'] as String? ?? 'Student';
      // Tag each item with which child/card it belongs to — the
      // Database method itself doesn't know about parents/children,
      // only groupId/studentId, so this is where that context gets
      // attached for display and for the tap-through below.
      for (final item in items) {
        item['childId'] = childId;
        item['childName'] = childName;
      }
      return items;
    }));
    return results.expand((l) => l).toList();
  }

  static const _rank = {
    'past_due': 0,
    'due_today': 1,
    'due_tomorrow': 2,
    'later': 3,
    'not_open_yet': 4,
    'completed': 5,
  };

  String _subtitleFor(Map<String, dynamic> item) {
    final status = item['status'] as String;
    switch (status) {
      case 'past_due':
        final due = item['dueDate'] as DateTime?;
        return due == null ? 'Past due' : 'Overdue since ${widget.formatDate(due)}';
      case 'due_today':
        return 'Due today';
      case 'due_tomorrow':
        return 'Due tomorrow';
      case 'not_open_yet':
        if (item['notOpenReason'] == 'scheduled') {
          final scheduled = item['scheduledDate'] as DateTime?;
          return scheduled == null ? 'Not open yet' : 'Opens ${widget.formatDate(scheduled)}';
        }
        return 'Locked — complete earlier activities first';
      default:
        final due = item['dueDate'] as DateTime?;
        return due == null ? 'No due date' : 'Due ${widget.formatDate(due)}';
    }
  }

  void _openChildActivities(Map<String, dynamic> item) {
    final childId = item['childId'] as String;
    final child = widget.myChildren.firstWhere(
      (c) => c['id'] == childId,
      orElse: () => <String, dynamic>{},
    );
    if (child.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ParentChildActivityStatusScreen(child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <Map<String, dynamic>>[];
        final pastDueCount = all.where((i) => i['status'] == 'past_due').length;
        final dueTodayCount = all.where((i) => i['status'] == 'due_today').length;

        final actionable = all
            .where((i) => i['status'] == 'past_due' || i['status'] == 'due_today' || i['status'] == 'due_tomorrow')
            .toList()
          ..sort((a, b) => _rank[a['status']]!.compareTo(_rank[b['status']]!));
        final shown = actionable.take(6).toList();

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Follow-ups',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _countCard(
                      icon: Icons.warning_amber_rounded,
                      label: 'Past Due',
                      value: '$pastDueCount',
                      color: AppColors.danger,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _countCard(
                      icon: Icons.today_rounded,
                      label: 'Due Today',
                      value: '$dueTodayCount',
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (shown.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: AppColors.success, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          all.isEmpty
                              ? 'Nothing assigned yet.'
                              : 'All caught up — nothing past due or due today!',
                          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...shown.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _followUpTile(item),
                    )),
            ],
          ),
        );
      },
    );
  }

  Widget _countCard({required IconData icon, required String label, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _followUpTile(Map<String, dynamic> item) {
    final status = item['status'] as String;
    final isPastDue = status == 'past_due';
    final accent = isPastDue ? AppColors.danger : AppColors.warning;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openChildActivities(item),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 36,
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item['childName']} · ${item['title']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitleFor(item),
                      style: TextStyle(
                        fontSize: 11,
                        color: isPastDue ? AppColors.danger : Colors.grey[500],
                        fontWeight: isPastDue ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Task-type insights section ──────────────────────────────────────

class _TaskInsightsSection extends StatefulWidget {
  final List<Map<String, dynamic>> myChildren;

  const _TaskInsightsSection({required this.myChildren});

  @override
  State<_TaskInsightsSection> createState() => _TaskInsightsSectionState();
}

class _TaskInsightsSectionState extends State<_TaskInsightsSection> {
  late Future<Map<String, _TypeStat>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _TaskInsightsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.myChildren != widget.myChildren) {
      _future = _load();
    }
  }

  /// Aggregates every completed task's score, grouped by task type,
  /// across all children — reads progress.taskAnswers, the same map
  /// activity_play_screen.dart writes per task (each entry carries
  /// 'type' plus per-task fields). No new tracking needed: this is
  /// purely an aggregation over data already being written.
  Future<Map<String, _TypeStat>> _load() async {
    final byType = <String, _TypeStat>{};

    for (final child in widget.myChildren) {
      final childId = child['id'] as String?;
      if (childId == null) continue;

      final progressSnap = await FirebaseFirestore.instance
          .collection('students')
          .doc(childId)
          .collection('progress')
          .get();

      for (final doc in progressSnap.docs) {
        final taskAnswers = doc.data()['taskAnswers'] as Map<String, dynamic>?;
        if (taskAnswers == null) continue;

        for (final answer in taskAnswers.values) {
          if (answer is! Map) continue;
          final type = answer['type'] as String?;
          final accuracy = (answer['accuracy'] as num?)?.toDouble();
          if (type == null || accuracy == null) continue;

          final stat = byType.putIfAbsent(type, () => _TypeStat());
          stat.total += accuracy;
          stat.count += 1;
        }
      }
    }

    return byType;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, _TypeStat>>(
      future: _future,
      builder: (context, snapshot) {
        final byType = snapshot.data ?? const <String, _TypeStat>{};
        // Need a handful of distinct types with real attempts before a
        // "strongest/weakest" comparison means anything.
        if (byType.length < 2) return const SizedBox.shrink();

        final ranked = byType.entries.toList()
          ..sort((a, b) => b.value.average.compareTo(a.value.average));
        final strongest = ranked.take(2).toList();
        final weakest = ranked.reversed.take(2).toList();

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Skill Insights',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _typeStatColumn('Strongest', strongest, AppColors.success)),
                  const SizedBox(width: 12),
                  Expanded(child: _typeStatColumn('Needs Practice', weakest, AppColors.danger)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _typeStatColumn(String heading, List<MapEntry<String, _TypeStat>> entries, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 8),
          ...entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${taskTypeOptionFor(e.key).label} · ${e.value.average.round()}%',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )),
        ],
      ),
    );
  }
}

class _TypeStat {
  double total = 0;
  int count = 0;
  double get average => count == 0 ? 0 : total / count;
}