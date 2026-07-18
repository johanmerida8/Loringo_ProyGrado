// child_report_detail_screen.dart
// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Full report history for a single child — reached by tapping a child's
/// card on ParentReportsScreen. Owns the same per-report card UI and PDF
/// export the old flat ParentReportsScreen used to render inline for
/// every child at once.
class ChildReportDetailScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final childName = child['names'] as String? ?? 'Child';

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            _childAvatar(child, radius: 16),
            const SizedBox(width: 10),
            Text('$childName\'s Reports'),
          ],
        ),
      ),
      body: reports.isEmpty
          ? _emptyState()
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: reports.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, i) =>
                  _buildReportCard(context, child, reports[i]),
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
            const Text('No reports yet',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 6),
            Text(
              'Reports appear here once your child\ncompletes a unit quiz',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard(
      BuildContext context, Map<String, dynamic> child, Map<String, dynamic> report) {
    final unitTitle = report['unitTitle'] as String? ?? 'Unknown Unit';
    final quizPercent = (report['quizPercent'] as num?)?.toInt() ?? 0;
    final quizCorrect = (report['quizCorrect'] as num?)?.toInt() ?? 0;
    final quizTotal = (report['quizTotalQuestions'] as num?)?.toInt() ?? 0;
    final activitiesCompleted = (report['activitiesCompleted'] as num?)?.toInt() ?? 0;
    final totalActivities = (report['totalActivities'] as num?)?.toInt() ?? 0;
    final activitiesPercent = (report['activitiesPercent'] as num?)?.toInt() ?? 0;
    final previousScores = List<int>.from(
        ((report['previousUnitScores'] as List?) ?? []).map((e) => (e as num).toInt()));
    final generatedAt = report['generatedAt'] as Timestamp?;
    final dateStr = generatedAt != null ? formatDate(generatedAt.toDate()) : 'Recently';
    final feedback = (report['feedback'] as String?) ?? '';

    final scoreColor = quizPercent >= 80
        ? const Color(0xFF4CAF50)
        : (quizPercent >= 60 ? const Color(0xFFFFC107) : const Color(0xFFFF7043));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: Text(unitTitle,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
                Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _statBlock(
                    label: 'Quiz Score',
                    value: '$quizPercent%',
                    sub: '$quizCorrect✓ / $quizTotal',
                    valueColor: scoreColor,
                  ),
                ),
                Container(width: 1, height: 50, color: const Color(0xFFF0F0F0)),
                const SizedBox(width: 16),
                Expanded(
                  child: _statBlock(
                    label: 'Activities',
                    value: '$activitiesPercent%',
                    sub: '$activitiesCompleted / $totalActivities done',
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
                      Row(children: [
                        Icon(Icons.comment_rounded, size: 14, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text('Teacher Feedback',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                      ]),
                      const SizedBox(height: 6),
                      Text(feedback,
                          style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              ),
            if (previousScores.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                children: [
                  ...previousScores.map((s) => Chip(
                      label: Text('$s%', style: const TextStyle(fontSize: 12)),
                      backgroundColor: Colors.grey[100],
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)),
                  Chip(
                      label: Text('$quizPercent%',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      backgroundColor: scoreColor.withOpacity(0.18),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                ],
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _exportReportPdf(context, child, report),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary.withOpacity(0.4), width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                label: const Text('Export PDF', style: TextStyle(fontSize: 13)),
              ),
            ),
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
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        Text(value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: valueColor)),
        Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _childAvatar(Map<String, dynamic> child, {required double radius}) {
    final avatar = child['avatar'] as String?;
    if (avatar != null && avatar.isNotEmpty) {
      return CircleAvatar(radius: radius, backgroundImage: AssetImage(avatar));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.white.withOpacity(0.25),
      child: Text(
        (child['names'] as String? ?? 'S')[0].toUpperCase(),
        style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }

  Future<void> _exportReportPdf(
      BuildContext context, Map<String, dynamic> child, Map<String, dynamic> report) async {
    final pdf = pw.Document();
    final childName = (child['names'] as String?) ?? 'Student';
    final unitTitle = (report['unitTitle'] as String?) ?? 'Unit';

    final quizPercent = (report['quizPercent'] as num?)?.toInt() ?? 0;
    final quizCorrect = (report['quizCorrect'] as num?)?.toInt() ?? 0;
    final quizTotal = (report['quizTotalQuestions'] as num?)?.toInt() ?? 0;
    final activitiesCompleted = (report['activitiesCompleted'] as num?)?.toInt() ?? 0;
    final totalActivities = (report['totalActivities'] as num?)?.toInt() ?? 0;
    final activitiesPercent = totalActivities == 0
        ? 0
        : (activitiesCompleted / totalActivities * 100).round().clamp(0, 100);
    final previousScores = List<int>.from(
        ((report['previousUnitScores'] as List?) ?? []).map((e) => (e as num).toInt()));
    final feedback = (report['feedback'] as String?) ?? '';
    final generatedAt = report['generatedAt'] as Timestamp?;
    final dateStr = generatedAt != null
        ? '${generatedAt.toDate().day}/${generatedAt.toDate().month}/${generatedAt.toDate().year}'
        : 'N/A';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Loringo Unit Report',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Student: $childName', style: const pw.TextStyle(fontSize: 10)),
                pw.Text('Date: $dateStr', style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
            pw.Text('Unit: $unitTitle',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 16),
            pw.Text('Activity Details',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Table.fromTextArray(
              headers: ['Metric', 'Value'],
              data: [
                ['Activities completed', '$activitiesCompleted / $totalActivities'],
                ['Completion rate', '$activitiesPercent%'],
              ],
              cellAlignment: pw.Alignment.centerLeft,
              headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              cellStyle: pw.TextStyle(fontSize: 9),
              columnWidths: {0: const pw.FixedColumnWidth(80), 1: const pw.FlexColumnWidth()},
            ),
            pw.SizedBox(height: 12),
            pw.Text('Quiz Details',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Table.fromTextArray(
              headers: ['Metric', 'Value'],
              data: [
                ['Score', '$quizPercent%'],
                ['Correct answers', '$quizCorrect / $quizTotal'],
              ],
              cellAlignment: pw.Alignment.centerLeft,
              headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              cellStyle: pw.TextStyle(fontSize: 9),
              columnWidths: {0: const pw.FixedColumnWidth(80), 1: const pw.FlexColumnWidth()},
            ),
            pw.SizedBox(height: 12),
            pw.Text('Progress Trend',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            if (previousScores.isNotEmpty) ...[
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                    children: [
                      ...previousScores.asMap().entries.map((entry) => pw.Column(children: [
                            pw.Text('Unit ${entry.key + 1}',
                                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
                            pw.Text('${entry.value}%',
                                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                          ])),
                      pw.Column(children: [
                        pw.Text('Current', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
                        pw.Text('$quizPercent%',
                            style: pw.TextStyle(
                                fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue)),
                      ]),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(_getTrendMessage(previousScores, quizPercent),
                      style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
                ]),
              ),
            ] else ...[
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                        'First unit completed. Complete more units to see progress trends.',
                        style: pw.TextStyle(
                            fontSize: 9, color: PdfColors.grey, fontStyle: pw.FontStyle.italic)),
                  ],
                ),
              ),
            ],
            pw.SizedBox(height: 12),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 6),
            pw.Text('Teacher Feedback',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: feedback.isNotEmpty
                  ? pw.Text(feedback,
                      style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic, height: 1.4))
                  : pw.Text('No feedback provided yet.',
                      style: pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey, fontStyle: pw.FontStyle.italic)),
            ),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 0.5),
            pw.Text('Generated by Loringo ${DateTime.now().year}',
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey)),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: '${childName.replaceAll(' ', '_')}_${unitTitle.replaceAll(' ', '_')}_report.pdf',
    );
  }

  String _getTrendMessage(List<int> previousScores, int currentScore) {
    if (previousScores.isEmpty) {
      return 'First unit completed! Complete more units to see your progress trend.';
    }
    final lastScore = previousScores.last;
    final difference = currentScore - lastScore;
    if (difference >= 10) return 'Excellent improvement! +$difference% compared to previous unit.';
    if (difference >= 5) return 'Good progress! +$difference% improvement. Keep it up!';
    if (difference > 0) return 'Slight improvement of +$difference%. Consistency is key!';
    if (difference == 0) return 'Maintained the same score. Try some extra practice!';
    return 'Score decreased by ${difference.abs()}%. Review the material again!';
  }
}