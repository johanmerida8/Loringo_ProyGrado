// child_report_detail_screen.dart
// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/parent/widgets/parent_screen_header.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/unit_report_pdf.dart';

/// Full report history for a single child — reached by tapping a child's
/// card on ParentReportsScreen. Owns the same per-report card UI and PDF
/// export the old flat ParentReportsScreen used to render inline for
/// every child at once.
///
/// Split into a "Recent Report" (the latest one, expanded by default) and
/// "Previous Reports" (everything older, collapsed by default) so the
/// list reads as organized history rather than a flat dump. Each
/// collapsed row only shows the unit title, date, and an Export PDF
/// button — the score/activity/feedback breakdown only renders once a
/// card is expanded, keeping the collapsed list scannable while still
/// putting every detail one tap away (or straight into the PDF without
/// expanding at all).
class ChildReportDetailScreen extends StatefulWidget {
  final Map<String, dynamic> child;
  final List<Map<String, dynamic>> reports;
  final String Function(DateTime) formatDate;

  const ChildReportDetailScreen({
    super.key,
    required this.child,
    required this.reports,
    required this.formatDate,
  });

  @override
  State<ChildReportDetailScreen> createState() =>
      _ChildReportDetailScreenState();
}

class _ChildReportDetailScreenState extends State<ChildReportDetailScreen> {
  // Recent report (index 0) starts expanded since that's what a parent
  // opening this screen most likely wants to see right away; every
  // previous report starts collapsed.
  final Set<int> _expanded = {0};

  String get _childName =>
      widget.child['names'] as String? ?? 'parent.child_report_detail_screen.fallbackChild'.tr();

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final reports = widget.reports;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          ParentScreenHeader(
              title: 'parent.child_report_detail_screen.titleReports'
                  .tr(namedArgs: {'name': _childName})),
          Expanded(
            child: reports.isEmpty ? _emptyState() : _buildReportsList(reports),
          ),
        ],
      ),
    );
  }

  Widget _buildReportsList(List<Map<String, dynamic>> reports) {
    final recent = reports.first;
    final previous = reports.skip(1).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        _sectionLabel('parent.child_report_detail_screen.recentReport'.tr()),
        const SizedBox(height: 8),
        _buildReportCard(0, recent, reports),
        if (previous.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionLabel('parent.child_report_detail_screen.previousReports'.tr()),
          const SizedBox(height: 8),
          for (var i = 0; i < previous.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _buildReportCard(i + 1, previous[i], reports),
          ],
        ],
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.8,
        color: Colors.grey[500],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
        child: Column(
          children: [
            Icon(Icons.description_outlined, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'common.noReports'.tr(),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'common.noReportsSub'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard(
    int index,
    Map<String, dynamic> report,
    List<Map<String, dynamic>> allReports,
  ) {
    final unitTitle = report['unitTitle'] as String? ??
        'parent.child_report_detail_screen.unknownUnit'.tr();
    final quizPercent = (report['quizPercent'] as num?)?.toInt() ?? 0;
    final quizCorrect = (report['quizCorrect'] as num?)?.toInt() ?? 0;
    final quizTotal = (report['quizTotalQuestions'] as num?)?.toInt() ?? 0;
    final activitiesCompleted =
        (report['activitiesCompleted'] as num?)?.toInt() ?? 0;
    final totalActivities = (report['totalActivities'] as num?)?.toInt() ?? 0;
    final activitiesPercent =
        (report['activitiesPercent'] as num?)?.toInt() ?? 0;
    final previousScores = List<int>.from(
      ((report['previousUnitScores'] as List?) ?? []).map(
        (e) => (e as num).toInt(),
      ),
    );
    final generatedAt = report['generatedAt'] as Timestamp?;
    final dateStr = generatedAt != null
        ? widget.formatDate(generatedAt.toDate())
        : 'parent.child_report_detail_screen.recently'.tr();
    final feedback = (report['feedback'] as String?) ?? '';

    final scoreColor = quizPercent >= 80
        ? const Color(0xFF4CAF50)
        : (quizPercent >= 60
              ? const Color(0xFFFFC107)
              : const Color(0xFFFF7043));

    final isExpanded = _expanded.contains(index);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Always-visible row: unit title, date, Export PDF, expand
            // toggle. This is deliberately the ONLY thing shown while
            // collapsed — score/activities/feedback below only render
            // when expanded.
            InkWell(
              onTap: () => setState(() {
                if (isExpanded) {
                  _expanded.remove(index);
                } else {
                  _expanded.add(index);
                }
              }),
              borderRadius: BorderRadius.circular(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          unitTitle,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dateStr,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => exportUnitReportPdf(
                      studentName:
                          (widget.child['names'] as String?) ?? 'common.student'.tr(),
                      report: report,
                      allReports: allReports,
                    ),
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                    color: AppColors.primary,
                    tooltip: 'common.exportPdf'.tr(),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: Colors.grey[500],
                  ),
                ],
              ),
            ),
            if (isExpanded) ...[
              const SizedBox(height: 8),
              const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _statBlock(
                      label: 'parent.child_report_detail_screen.quizScore'.tr(),
                      value: '$quizPercent%',
                      sub: '$quizCorrect✓ / $quizTotal',
                      valueColor: scoreColor,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 50,
                    color: const Color(0xFFF0F0F0),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _statBlock(
                      label: 'common.activities'.tr(),
                      value: '$activitiesPercent%',
                      sub: 'parent.child_report_detail_screen.activitiesDone'
                          .tr(namedArgs: {
                        'completed': '$activitiesCompleted',
                        'total': '$totalActivities',
                      }),
                      valueColor: const Color(0xFF4CAF50),
                    ),
                  ),
                ],
              ),
              if (feedback.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primarySoft(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.comment_rounded,
                              size: 14,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'common.teacherFeedback'.tr(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          feedback,
                          style: const TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (previousScores.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFF0F0F0),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  children: [
                    ...previousScores.map(
                      (s) => Chip(
                        label: Text(
                          '$s%',
                          style: const TextStyle(fontSize: 12),
                        ),
                        backgroundColor: Colors.grey[100],
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    Chip(
                      label: Text(
                        '$quizPercent%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: scoreColor.withOpacity(0.18),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _statBlock({
    required String label,
    required String value,
    required String sub,
    required Color valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
        Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}
