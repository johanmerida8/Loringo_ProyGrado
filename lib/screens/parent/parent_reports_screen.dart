// parent_reports_screen.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/parent/child_report_detail_screen.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// Reports tab — one summary card per child (same visual language as
/// ParentChildrenScreen) instead of dumping every report flat on one
/// page. Tapping a card opens ChildReportDetailScreen with that child's
/// full report history.
class ParentReportsScreen extends StatelessWidget {
  final List<Map<String, dynamic>> myChildren;
  final Map<String, List<Map<String, dynamic>>> childReports;
  final String Function(DateTime) formatDate;

  const ParentReportsScreen({
    super.key,
    required this.myChildren,
    required this.childReports,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Text(
              'Reports',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (myChildren.isEmpty)
            _emptyState(
              icon: Icons.description_rounded,
              message: 'No children registered yet',
              sub: 'Register a child first to see reports',
            )
          else
            ...myChildren.map((child) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: _buildChildReportCard(context, child),
                )),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildChildReportCard(
      BuildContext context, Map<String, dynamic> child) {
    final childId = child['id'] as String;
    final reports = childReports[childId] ?? [];
    final latest = reports.isNotEmpty ? reports.first : null;
    final latestPercent = latest != null
        ? (latest['quizPercent'] as num?)?.toInt() ?? 0
        : null;
    final scoreColor = latestPercent == null
        ? Colors.grey
        : latestPercent >= 80
            ? const Color(0xFF4CAF50)
            : (latestPercent >= 60
                ? const Color(0xFFFFC107)
                : const Color(0xFFFF7043));

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: reports.isEmpty
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChildReportDetailScreen(
                      child: child,
                      reports: reports,
                      formatDate: formatDate,
                    ),
                  ),
                ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _childAvatar(child, radius: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        child['names'] ?? 'Child',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        reports.isEmpty
                            ? 'No reports yet'
                            : '${reports.length} report${reports.length != 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (latestPercent != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: scoreColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '$latestPercent%',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: scoreColor,
                          ),
                        ),
                        Text(
                          'latest',
                          style: TextStyle(
                            fontSize: 10,
                            color: scoreColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Icon(Icons.chevron_right_rounded,
                    color: reports.isEmpty
                        ? Colors.grey[300]
                        : Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(
      {required IconData icon, required String message, required String sub}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
        child: Column(
          children: [
            Icon(icon, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(message, style: TextStyle(fontSize: 16, color: Colors.grey[500])),
            const SizedBox(height: 6),
            Text(sub,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[400])),
          ],
        ),
      ),
    );
  }

  Widget _childAvatar(Map<String, dynamic> child, {required double radius}) {
    final avatar = child['avatar'] as String?;
    if (avatar != null && avatar.isNotEmpty) {
      return CircleAvatar(radius: radius, backgroundImage: AssetImage(avatar));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primarySoft(0.15),
      child: Text(
        (child['names'] as String? ?? 'S')[0].toUpperCase(),
        style: TextStyle(
            fontSize: radius * 0.8,
            fontWeight: FontWeight.bold,
            color: AppColors.primary),
      ),
    );
  }
}