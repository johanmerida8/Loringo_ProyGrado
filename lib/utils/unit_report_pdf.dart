// lib/utils/unit_report_pdf.dart
//
// Shared unit-report PDF builder, used by both the parent-facing
// ChildReportDetailScreen and the teacher-facing ReportPreviewScreen --
// previously each screen had its own near-identical copy of this exact
// PDF (same fields, same table layout, same trend logic), which meant any
// fix had to be applied twice. This is the single source of truth now.
//
// No "Teacher Feedback" section -- deliberately removed from both original
// versions. The "Progress Trend" section from the old versions used
// report['previousUnitScores'], which was dead data (traced every read/
// write site in Database.saveReportOnly -- never once appended to, always
// empty). This version instead compares against the most recent OTHER
// report in [allReports] (the caller's full report history, if it has
// one), keyed by real generatedAt timestamps -- and shows nothing at all
// (no placeholder) when there isn't a previous unit to compare against.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

Future<void> exportUnitReportPdf({
  required String studentName,
  required Map<String, dynamic> report,
  List<Map<String, dynamic>> allReports = const [],
}) async {
  final pdf = pw.Document();
  final unitTitle = (report['unitTitle'] as String?) ?? 'Unit';

  final quizPercent = (report['quizPercent'] as num?)?.toInt() ?? 0;
  final quizCorrect = (report['quizCorrect'] as num?)?.toInt() ?? 0;
  final quizTotal = (report['quizTotalQuestions'] as num?)?.toInt() ?? 0;

  final activitiesCompleted = (report['activitiesCompleted'] as num?)?.toInt() ?? 0;
  final totalActivities = (report['totalActivities'] as num?)?.toInt() ?? 0;
  final activitiesPercent = totalActivities == 0
      ? 0
      : (activitiesCompleted / totalActivities * 100).round().clamp(0, 100);

  final completedLessonQuizzes = (report['completedLessonQuizzes'] as num?)?.toInt() ?? 0;
  final totalLessonQuizzes = (report['totalLessonQuizzes'] as num?)?.toInt() ?? 0;

  final generatedAt = report['generatedAt'] as Timestamp?;
  final dateStr = generatedAt != null
      ? '${generatedAt.toDate().day}/${generatedAt.toDate().month}/${generatedAt.toDate().year}'
      : 'N/A';

  // Previous-unit comparison: the most recent OTHER report strictly
  // earlier than this one's generatedAt, from the caller's own report
  // history. null when there's nothing to compare against (first unit, or
  // the caller didn't have a history to pass).
  Map<String, dynamic>? previousReport;
  final currentGeneratedAt = generatedAt?.toDate();
  if (currentGeneratedAt != null) {
    final priorReports = allReports.where((r) {
      if (identical(r, report)) return false;
      final t = (r['generatedAt'] as Timestamp?)?.toDate();
      return t != null && t.isBefore(currentGeneratedAt);
    }).toList()
      ..sort((a, b) =>
          (b['generatedAt'] as Timestamp).compareTo(a['generatedAt'] as Timestamp));
    previousReport = priorReports.isEmpty ? null : priorReports.first;
  }

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
              pw.Text('Student: $studentName', style: const pw.TextStyle(fontSize: 10)),
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
          pw.Text('Lesson Quizzes',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Table.fromTextArray(
            headers: ['Metric', 'Value'],
            data: [
              ['Completed', '$completedLessonQuizzes / $totalLessonQuizzes'],
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
          if (previousReport != null) ...[
            pw.SizedBox(height: 12),
            pw.Text('Compared to Previous Unit',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            _buildComparisonBlock(previousReport, unitTitle, quizPercent),
          ],
          pw.SizedBox(height: 12),
          pw.Divider(thickness: 0.5),
          pw.Text('Generated by Loringo ${DateTime.now().year}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey)),
        ],
      ),
    ),
  );

  await Printing.layoutPdf(
    onLayout: (format) async => pdf.save(),
    name: '${studentName.replaceAll(' ', '_')}_${unitTitle.replaceAll(' ', '_')}_report.pdf',
  );
}

pw.Widget _buildComparisonBlock(
  Map<String, dynamic> previousReport,
  String unitTitle,
  int quizPercent,
) {
  final previousUnitTitle = (previousReport['unitTitle'] as String?) ?? 'Previous unit';
  final previousQuizPercent = (previousReport['quizPercent'] as num?)?.toInt() ?? 0;
  final difference = quizPercent - previousQuizPercent;

  return pw.Container(
    padding: const pw.EdgeInsets.all(6),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          pw.Column(children: [
            pw.Text(previousUnitTitle, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
            pw.Text('$previousQuizPercent%',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.Column(children: [
            pw.Text(unitTitle, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
            pw.Text('$quizPercent%',
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue)),
          ]),
        ],
      ),
      pw.SizedBox(height: 4),
      pw.Text(_getTrendMessage(difference),
          style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
    ]),
  );
}

String _getTrendMessage(int difference) {
  if (difference >= 10) return 'Excellent improvement! +$difference% compared to previous unit.';
  if (difference >= 5) return 'Good progress! +$difference% improvement. Keep it up!';
  if (difference > 0) return 'Slight improvement of +$difference%. Consistency is key!';
  if (difference == 0) return 'Maintained the same score. Try some extra practice!';
  return 'Score decreased by ${difference.abs()}%. Review the material again!';
}
