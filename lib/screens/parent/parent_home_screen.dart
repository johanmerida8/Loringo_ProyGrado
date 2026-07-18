// lib/screens/parent/parent_home_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/notification_permission_card.dart';
import 'package:loringo_app/components/notifications_badge.dart';
import 'package:loringo_app/providers/notification_provider.dart';
import 'package:loringo_app/screens/parent/child_report_detail_screen.dart';
import 'package:loringo_app/screens/parent/parent_profile_screen.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// The "Home" tab content for the parent role.
///
/// Beyond the greeting + children preview, this now surfaces two things
/// parents actually want at a glance:
///  - an average-score progress ring across all children with reports
///  - a "recent activity" feed of the latest report per child, newest
///    first, so a parent immediately sees what happened lately instead
///    of having to dig into Reports to find out.
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

  /// Average quiz score across every child's most recent report. Null
  /// when nobody has a report yet, so the ring can show an empty state
  /// instead of a misleading 0%.
  double? get _averageScore {
    final scores = childReports.values
        .where((r) => r.isNotEmpty)
        .map((r) => (r.first['quizPercent'] as num?)?.toDouble() ?? 0)
        .toList();
    if (scores.isEmpty) return null;
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  @override
  Widget build(BuildContext context) {
    final activity = _recentActivity;
    final avgScore = _averageScore;

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

          // ── Summary row: children / in groups / average score ring ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _summaryCard(
                    icon: Icons.people_alt_rounded,
                    label: 'Children',
                    value: '${myChildren.length}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _summaryCard(
                    icon: Icons.groups_rounded,
                    label: 'In Groups',
                    value:
                        '${myChildren.where((c) => (c['groupId'] as String?)?.isNotEmpty == true).length}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _averageScoreCard(avgScore)),
              ],
            ),
          ),

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

  Widget _averageScoreCard(double? avgScore) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration:
          BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    value: avgScore == null ? 0 : (avgScore / 100).clamp(0, 1),
                    strokeWidth: 4,
                    backgroundColor: AppColors.primarySoft(0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      avgScore == null
                          ? Colors.grey.shade300
                          : avgScore >= 80
                              ? const Color(0xFF4CAF50)
                              : (avgScore >= 60
                                  ? const Color(0xFFFFC107)
                                  : const Color(0xFFFF7043)),
                    ),
                  ),
                ),
                Icon(Icons.emoji_events_rounded,
                    color: avgScore == null
                        ? Colors.grey.shade300
                        : AppColors.primary,
                    size: 18),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(avgScore == null ? '—' : '${avgScore.round()}%',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Text('Avg Score', style: TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildChildSummaryCard(Map<String, dynamic> child) {
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
                Text(
                  childName,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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

  Widget _summaryCard({required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration:
          BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
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