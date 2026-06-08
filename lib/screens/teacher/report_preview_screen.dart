// screens/teacher/report_preview_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ReportPreviewScreen extends StatefulWidget {
  final String studentName;
  final Map<String, dynamic> studentData;
  final Map<String, dynamic> report;

  const ReportPreviewScreen({
    super.key,
    required this.studentName,
    required this.studentData,
    required this.report,
  });

  @override
  State<ReportPreviewScreen> createState() => _ReportPreviewScreenState();
}

class _ReportPreviewScreenState extends State<ReportPreviewScreen> {
  bool _isExporting = false;

  Future<void> _exportPdf() async {
    setState(() => _isExporting = true);
    
    try {
      await _generatePdf();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    } finally {
      setState(() => _isExporting = false);
    }
  }

  Future<void> _generatePdf() async {
    final pdf = pw.Document();
    final childName = widget.studentName;
    final unitTitle = (widget.report['unitTitle'] as String?) ?? 'Unit';
    
    // Extract data
    final quizPercent = (widget.report['quizPercent'] as num?)?.toInt() ?? 0;
    final quizCorrect = (widget.report['quizCorrect'] as num?)?.toInt() ?? 0;
    final quizTotal = (widget.report['quizTotalQuestions'] as num?)?.toInt() ?? 0;
    
    final activitiesCompleted = (widget.report['activitiesCompleted'] as num?)?.toInt() ?? 0;
    final totalActivities = (widget.report['totalActivities'] as num?)?.toInt() ?? 0;
    final activitiesPercent = totalActivities == 0 ? 0 : (activitiesCompleted / totalActivities * 100).round().clamp(0, 100);
    
    final previousScores = List<int>.from(((widget.report['previousUnitScores'] as List?) ?? []).map((e) => (e as num).toInt()));
    final feedback = (widget.report['feedback'] as String?) ?? '';
    final generatedAt = widget.report['generatedAt'] as Timestamp?;
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
            // Header
            pw.Text('Loringo Unit Report',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 6),
            
            // Student info
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Student: $childName', style: const pw.TextStyle(fontSize: 10)),
                pw.Text('Date: $dateStr', style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
            pw.Text('Unit: $unitTitle', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            
            pw.SizedBox(height: 16),
            
            // Activity Details Table
            pw.Text('Activity Details', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
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
            
            // Quiz Details Table
            pw.Text('Quiz Details', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
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
            
            // Progress Trend
            pw.SizedBox(height: 12),
            pw.Text('Progress Trend', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            if (previousScores.isNotEmpty) ...[
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                      children: [
                        ...previousScores.asMap().entries.map((entry) => pw.Column(
                          children: [
                            pw.Text('Unit ${entry.key + 1}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
                            pw.Text('${entry.value}%', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                          ],
                        )),
                        pw.Column(
                          children: [
                            pw.Text('Current', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
                            pw.Text('$quizPercent%', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue)),
                          ],
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(_getTrendMessage(previousScores, quizPercent), 
                        style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
                  ],
                ),
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
                    pw.Text('This is the first unit completed. Complete more units to see progress trends.', 
                        style: pw.TextStyle(fontSize: 9, color: PdfColors.grey, fontStyle: pw.FontStyle.italic)),
                  ],
                ),
              ),
            ],

            // Teacher Feedback
            pw.SizedBox(height: 12),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 6),
            pw.Text('Teacher Feedback', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: feedback.isNotEmpty
                  ? pw.Text(feedback, style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic, height: 1.4))
                  : pw.Text('No feedback provided yet.', 
                      style: pw.TextStyle(fontSize: 9, color: PdfColors.grey, fontStyle: pw.FontStyle.italic)),
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
    if (difference >= 10) return 'Excellent improvement! +$difference% compared to previous unit!';
    if (difference >= 5) return 'Good progress! +$difference% improvement. Keep it up!';
    if (difference > 0) return 'Slight improvement of +$difference%. Consistency is key!';
    if (difference == 0) return 'Maintained the same score. Try some extra practice!';
    return 'Score decreased by ${difference.abs()}%. Review the material again!';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('Report: ${widget.studentName}'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _isExporting
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_rounded),
            onPressed: _isExporting ? null : _exportPdf,
            tooltip: 'Export PDF',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Report Preview', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 24),
                _buildInfoRow('Student', widget.studentName),
                _buildInfoRow('Unit', widget.report['unitTitle'] ?? 'N/A'),
                _buildInfoRow('Score', '${widget.report['quizPercent'] ?? 0}%'),
                _buildInfoRow('Activities', '${widget.report['activitiesCompleted'] ?? 0}/${widget.report['totalActivities'] ?? 0}'),
                const Divider(),
                if (widget.report['feedback'] != null && widget.report['feedback'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Teacher Feedback', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(widget.report['feedback']),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _exportPdf,
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: const Text('Export as PDF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}