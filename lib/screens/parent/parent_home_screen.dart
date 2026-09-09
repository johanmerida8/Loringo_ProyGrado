// lib/screens/parent/parent_home_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/avatar_image.dart';
import 'package:loringo_app/components/notification_permission_card.dart';
import 'package:loringo_app/components/notifications_badge.dart';
import 'package:loringo_app/providers/locale_provider.dart';
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
  // Re-runs ParentNavigationScreen._loadData(), which refetches myChildren
  // with a fresh List instance. _FollowUpsSection's didUpdateWidget already
  // reloads its own (separately-fetched) overdue/due-today data whenever
  // that reference changes -- this callback is what actually triggers it,
  // since without a way to re-run _loadData, Follow-ups only ever fetched
  // once per app session and never noticed a teacher editing an activity's
  // due date afterwards.
  final Future<void> Function() onRefresh;

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
    required this.onRefresh,
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
    context.watch<LocaleProvider>();
    final activity = _recentActivity;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
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
              child: Text(
                  'parent.parent_home_screen.helloName'
                      .tr(namedArgs: {'name': parentName}),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('parent.parent_home_screen.recentActivity'.tr(),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                Text('common.myChildren'.tr(),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: onSeeAllChildren,
                  icon: const Icon(Icons.arrow_forward,
                      size: 16, color: AppColors.primary),
                  label: Text('parent.parent_home_screen.seeAll'.tr(),
                      style: const TextStyle(color: AppColors.primary)),
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
      ),
    );
  }

  Widget _activityTile(BuildContext context, _ActivityEntry entry) {
    final child = entry.child;
    final report = entry.report;
    final childName = child['names'] as String? ??
        'parent.parent_home_screen.studentFallback'.tr();
    final unitTitle = report['unitTitle'] as String? ??
        'parent.parent_home_screen.unitFallback'.tr();
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
                      'parent.parent_home_screen.childCompletedActivity'
                          .tr(namedArgs: {'child': childName, 'unit': unitTitle}),
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
    final avatarPath = child['avatar'] as String? ?? kAvatarFallbackAsset;
    final childName = child['names'] as String? ??
        'parent.parent_home_screen.studentFallback'.tr();

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
              child: AvatarImage(
                avatar: avatarPath,
                fit: BoxFit.cover,
                size: 48,
                fallbackBuilder: (context) => Text(
                  childName[0].toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                    fontSize: 18,
                  ),
                ),
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
                          'parent.parent_home_screen.overdueCount'
                              .plural(overdueCount),
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
                      ? groupNames[child['id']] ?? 'common.unknownGroup'.tr()
                      : 'common.noGroupAssigned'.tr(),
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
            Text('common.noChildRegistered'.tr(), style: TextStyle(color: Colors.grey[500])),
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
      final childName = child['names'] as String? ??
          'parent.parent_home_screen.studentFallback'.tr();
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
        return due == null
            ? 'parent.parent_home_screen.pastDue'.tr()
            : 'parent.parent_home_screen.overdueSince'
                .tr(namedArgs: {'date': widget.formatDate(due)});
      case 'due_today':
        return 'parent.parent_home_screen.dueToday'.tr();
      case 'due_tomorrow':
        return 'parent.parent_home_screen.dueTomorrow'.tr();
      case 'not_open_yet':
        if (item['notOpenReason'] == 'scheduled') {
          final scheduled = item['scheduledDate'] as DateTime?;
          return scheduled == null
              ? 'parent.parent_home_screen.notOpenYet'.tr()
              : 'parent.parent_home_screen.opensOn'
                  .tr(namedArgs: {'date': widget.formatDate(scheduled)});
        }
        return 'parent.parent_home_screen.lockedEarlierActivities'.tr();
      default:
        final due = item['dueDate'] as DateTime?;
        return due == null
            ? 'parent.parent_home_screen.noDueDate'.tr()
            : 'parent.parent_home_screen.dueOn'
                .tr(namedArgs: {'date': widget.formatDate(due)});
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
    context.watch<LocaleProvider>();
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
              Text('parent.parent_home_screen.followUps'.tr(),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _countCard(
                      icon: Icons.warning_amber_rounded,
                      label: 'parent.parent_home_screen.pastDue'.tr(),
                      value: '$pastDueCount',
                      color: AppColors.danger,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _countCard(
                      icon: Icons.today_rounded,
                      label: 'parent.parent_home_screen.dueToday'.tr(),
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
                              ? 'parent.parent_home_screen.nothingAssignedYet'.tr()
                              : 'parent.parent_home_screen.allCaughtUp'.tr(),
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

// ── Skill insights section ──────────────────────────────────────────
//
// Per child (not merged across siblings — a parent with several kids
// needs to know THIS one's strongest/weakest skill, not a blended
// average that belongs to nobody), aggregated at the CATEGORY level
// (Vocabulary/Grammar/Reading/Speaking & Listening/Conversation, via
// taskCategoryFor -- kTaskTypeGroups) rather than by individual task
// type: a parent never sees "Image Select" or "Fill in the Blank"
// themselves (they don't do the activities), but "Vocabulary" and
// "Grammar" mean something to them. A category only counts as "needs
// practice" below _kNeedsPracticeThreshold -- otherwise a child with no
// real weak spot gets a reassuring "no practice needed" line instead of
// an arbitrary second-best category being flagged as if it were a
// problem.

/// Average accuracy below which a category is flagged as needing
/// practice -- matches the 2-star cutoff used elsewhere for
/// activity/quiz scoring (Database.saveActivityCompletion), so "needs
/// practice" lines up with the same bar the rest of the app already
/// uses for "doing fine" vs. "could improve".
const double _kNeedsPracticeThreshold = 70;

class _ChildSkillInsight {
  final Map<String, dynamic> child;
  final MapEntry<String, _TypeStat> strongest;
  final MapEntry<String, _TypeStat>? needsPractice;
  const _ChildSkillInsight({required this.child, required this.strongest, this.needsPractice});
}

class _TaskInsightsSection extends StatefulWidget {
  final List<Map<String, dynamic>> myChildren;

  const _TaskInsightsSection({required this.myChildren});

  @override
  State<_TaskInsightsSection> createState() => _TaskInsightsSectionState();
}

class _TaskInsightsSectionState extends State<_TaskInsightsSection> {
  late Future<List<_ChildSkillInsight>> _future;

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

  /// Aggregates every completed task's score, grouped by skill category,
  /// one child at a time — reads progress.taskAnswers, the same map
  /// activity_play_screen.dart writes per task (each entry carries
  /// 'type' plus per-task fields). No new tracking needed: this is
  /// purely an aggregation over data already being written.
  Future<List<_ChildSkillInsight>> _load() async {
    final insights = <_ChildSkillInsight>[];

    for (final child in widget.myChildren) {
      final childId = child['id'] as String?;
      if (childId == null) continue;

      final byCategory = <String, _TypeStat>{};

      // Full lifetime history, not just the current group's — walks every
      // group this child has ever been in (see
      // Database.getAllProgressEver), so a child's skill insights don't
      // reset to nothing just because they switched groups.
      final allProgress = await Database().getAllProgressEver(childId);

      for (final data in allProgress) {
        final taskAnswers = data['taskAnswers'] as Map<String, dynamic>?;
        if (taskAnswers == null) continue;

        for (final answer in taskAnswers.values) {
          if (answer is! Map) continue;
          final type = answer['type'] as String?;
          final accuracy = (answer['accuracy'] as num?)?.toDouble();
          if (type == null || accuracy == null) continue;

          final stat = byCategory.putIfAbsent(taskCategoryFor(type), () => _TypeStat());
          stat.total += accuracy;
          stat.count += 1;
        }
      }

      // Need at least 2 distinct categories with real attempts before a
      // "strongest/needs practice" comparison means anything for this
      // child — otherwise skip them rather than show a misleading
      // single-datapoint insight.
      if (byCategory.length < 2) continue;

      final ranked = byCategory.entries.toList()
        ..sort((a, b) => b.value.average.compareTo(a.value.average));
      final weakest = ranked.last;

      insights.add(_ChildSkillInsight(
        child: child,
        strongest: ranked.first,
        needsPractice: weakest.value.average < _kNeedsPracticeThreshold ? weakest : null,
      ));
    }

    return insights;
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return FutureBuilder<List<_ChildSkillInsight>>(
      future: _future,
      builder: (context, snapshot) {
        final insights = snapshot.data ?? const <_ChildSkillInsight>[];
        if (insights.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('parent.parent_home_screen.skillInsights'.tr(),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
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
                  children: [
                    for (int i = 0; i < insights.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: Colors.grey.shade100),
                      _childInsightRow(insights[i]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _childInsightRow(_ChildSkillInsight insight) {
    final childName = insight.child['names'] as String? ??
        'parent.parent_home_screen.studentFallback'.tr();
    final avatarPath = insight.child['avatar'] as String? ?? kAvatarFallbackAsset;
    final needsPractice = insight.needsPractice;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primarySoft(0.15),
            child: ClipOval(
              child: AvatarImage(
                avatar: avatarPath,
                fit: BoxFit.cover,
                size: 32,
                fallbackBuilder: (context) => Text(
                  childName[0].toUpperCase(),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(childName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: 'parent.parent_home_screen.strongestPrefix'.tr(),
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    TextSpan(
                      text: '${taskGroupLabel(insight.strongest.key)} (${insight.strongest.value.average.round()}%)',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success),
                    ),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                needsPractice == null
                    ? Text('parent.parent_home_screen.noPracticeNeeded'.tr(),
                        style: const TextStyle(fontSize: 12, color: AppColors.success))
                    : Text.rich(
                        TextSpan(children: [
                          TextSpan(
                              text: 'parent.parent_home_screen.needsPracticePrefix'.tr(),
                              style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          TextSpan(
                            text: '${taskGroupLabel(needsPractice.key)} (${needsPractice.value.average.round()}%)',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.danger),
                          ),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ],
            ),
          ),
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