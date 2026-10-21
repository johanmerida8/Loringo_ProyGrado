// lib/utils/unit_report_pdf.dart
//
// Shared unit-report PDF builder, used by both the parent-facing
// ChildReportDetailScreen and the teacher-facing ReportPreviewScreen --
// previously each screen had its own near-identical copy of this exact
// PDF (same fields, same table layout, same trend logic), which meant any
// fix had to be applied twice. This is the single source of truth now.
//
// Mirrors exactly what the in-app report screens show (same comparison
// helper, same fields) -- the PDF is a printable copy of the same report,
// not a separate source of additional information.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:loringo_app/models/feedback_tag.dart';
import 'package:loringo_app/utils/report_comparison.dart';

/// Unicode fonts for the PDF. Without a theme the `pdf` package falls back
/// to its built-in Helvetica, which can't draw characters outside basic
/// Latin — "—", curly quotes or the emojis teachers often put in their
/// feedback (👏 💯) came out blank. Noto Sans covers the text (accents, ñ,
/// ¡¿, dashes) and Noto Color Emoji is the fallback for emojis. Fetched by
/// `printing`'s PdfGoogleFonts and cached in memory after the first export.
/// If they can't be loaded (e.g. offline) this returns null and the PDF is
/// built with the default fonts as before, so exporting never fails on it.
Future<pw.ThemeData?> _loadPdfTheme() async {
  try {
    final fonts = await Future.wait([
      PdfGoogleFonts.notoSansRegular(),
      PdfGoogleFonts.notoSansBold(),
      PdfGoogleFonts.notoSansItalic(),
      PdfGoogleFonts.notoSansBoldItalic(),
      PdfGoogleFonts.notoColorEmoji(),
    ]);
    return pw.ThemeData.withFont(
      base: fonts[0],
      bold: fonts[1],
      italic: fonts[2],
      boldItalic: fonts[3],
      fontFallback: [fonts[4]],
    );
  } catch (_) {
    return null;
  }
}

/// Loringo logo for the report header; null if the asset can't be read, in
/// which case the header is just the title, as before.
Future<pw.MemoryImage?> _loadLogo() async {
  try {
    final bytes = await rootBundle.load('assets/images/loro.png');
    return pw.MemoryImage(bytes.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

Future<void> exportUnitReportPdf({
  required String studentName,
  required Map<String, dynamic> report,
  List<Map<String, dynamic>> allReports = const [],
}) async {
  final pdf = pw.Document(theme: await _loadPdfTheme());
  final logo = await _loadLogo();
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

  final feedback = (report['feedback'] as String?) ?? '';
  // Teacher's one-tap rating, rendered as "⭐ Great Work!" — the emoji
  // fallback font set up above covers it.
  final feedbackTag = feedbackTagFor(report['feedbackTag'] as String?);
  final feedbackTagText = feedbackTag == null
      ? ''
      : '${feedbackTag['emoji']} ${feedbackTagLabel(feedbackTag['key'] as String)}';

  final generatedAt = report['generatedAt'] as Timestamp?;
  final dateStr = generatedAt != null
      ? '${generatedAt.toDate().day}/${generatedAt.toDate().month}/${generatedAt.toDate().year}'
      : 'N/A';

  final comparison = computeReportComparison(report, allReports);

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // The logo has a dark background, so it's framed as a
              // rounded app-icon tile rather than placed bare on white.
              if (logo != null) ...[
                pw.ClipRRect(
                  horizontalRadius: 8,
                  verticalRadius: 8,
                  child: pw.Image(logo, width: 40, height: 40),
                ),
                pw.SizedBox(width: 10),
              ],
              pw.Text('common.loringoUnitReport'.tr(),
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('${'common.student'.tr()}: $studentName',
                  style: const pw.TextStyle(fontSize: 10)),
              pw.Text('${'common.date'.tr()}: $dateStr',
                  style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
          pw.Text('${'common.unit'.tr()}: $unitTitle',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 16),
          pw.Text('common.activityDetails'.tr(),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['common.metric'.tr(), 'common.value'.tr()],
            data: [
              ['common.activitiesCompleted'.tr(), '$activitiesCompleted / $totalActivities'],
              ['common.completionRate'.tr(), '$activitiesPercent%'],
            ],
            cellAlignment: pw.Alignment.centerLeft,
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: pw.TextStyle(fontSize: 9),
            columnWidths: {0: const pw.FixedColumnWidth(80), 1: const pw.FlexColumnWidth()},
          ),
          pw.SizedBox(height: 12),
          pw.Text('common.lessonQuizzes'.tr(),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['common.metric'.tr(), 'common.value'.tr()],
            data: [
              ['common.completed'.tr(), '$completedLessonQuizzes / $totalLessonQuizzes'],
            ],
            cellAlignment: pw.Alignment.centerLeft,
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: pw.TextStyle(fontSize: 9),
            columnWidths: {0: const pw.FixedColumnWidth(80), 1: const pw.FlexColumnWidth()},
          ),
          pw.SizedBox(height: 12),
          pw.Text('common.quizDetails'.tr(),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['common.metric'.tr(), 'common.value'.tr()],
            data: [
              ['common.score'.tr(), '$quizPercent%'],
              ['common.correctAnswers'.tr(), '$quizCorrect / $quizTotal'],
            ],
            cellAlignment: pw.Alignment.centerLeft,
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: pw.TextStyle(fontSize: 9),
            columnWidths: {0: const pw.FixedColumnWidth(80), 1: const pw.FlexColumnWidth()},
          ),
          if (feedback.isNotEmpty || feedbackTagText.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('common.teacherFeedback'.tr(),
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            if (feedbackTagText.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Text(feedbackTagText,
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ],
            if (feedback.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Text(feedback,
                  style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic)),
            ],
          ],
          if (comparison.hasData) ...[
            pw.SizedBox(height: 12),
            pw.Text('common.progressTrend'.tr(),
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            _buildComparisonBlock(
              comparison,
              unitTitle,
              (report['activitiesAvgScore'] as num?)?.toInt() ?? 0,
            ),
          ],
          pw.SizedBox(height: 12),
          pw.Divider(thickness: 0.5),
          pw.Text('${'common.generatedBy'.tr()} ${DateTime.now().year}',
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
  ReportComparison comparison,
  String unitTitle,
  int activitiesAvgScore,
) {
  final previousReport = comparison.previousReport!;
  final previousUnitTitle = (previousReport['unitTitle'] as String?) ?? 'common.previousUnit'.tr();
  final previousPercent = (previousReport['activitiesAvgScore'] as num?)?.toInt() ?? 0;
  final difference = comparison.trendDifference ?? (activitiesAvgScore - previousPercent);

  return pw.Container(
    padding: const pw.EdgeInsets.all(6),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(children: [
      pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Text('common.trendActivities'.tr(),
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
        ),
      ),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          pw.Column(children: [
            pw.Text(previousUnitTitle, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
            pw.Text('$previousPercent%',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.Column(children: [
            pw.Text(unitTitle, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
            pw.Text('$activitiesAvgScore%',
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue)),
          ]),
          if (comparison.averagePreviousPercent != null)
            pw.Column(children: [
              pw.Text('common.averagePreviousUnits'.tr(),
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
              pw.Text('${comparison.averagePreviousPercent}%',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ]),
        ],
      ),
      pw.SizedBox(height: 4),
      pw.Text(reportTrendMessage(difference),
          style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
    ]),
  );
}
