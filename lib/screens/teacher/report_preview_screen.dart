// screens/teacher/report_preview_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/unit_report_pdf.dart';

class ReportPreviewScreen extends StatefulWidget {
  final String studentName;
  final Map<String, dynamic> studentData;
  final Map<String, dynamic> report;
  final List<Map<String, dynamic>> allReports;

  const ReportPreviewScreen({
    super.key,
    required this.studentName,
    required this.studentData,
    required this.report,
    this.allReports = const [],
  });

  @override
  State<ReportPreviewScreen> createState() => _ReportPreviewScreenState();
}

class _ReportPreviewScreenState extends State<ReportPreviewScreen> {
  bool _isExporting = false;

  Future<void> _exportPdf() async {
    setState(() => _isExporting = true);

    try {
      await exportUnitReportPdf(
        studentName: widget.studentName,
        report: widget.report,
        allReports: widget.allReports,
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(
          'teacher.report_preview_screen.errorGeneratingPdf'
              .tr(namedArgs: {'error': '$e'}))));
    } finally {
      setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          TeacherScreenHeader(
            title: 'teacher.report_preview_screen.reportFor'
                .tr(namedArgs: {'name': widget.studentName}),
            trailing: IconButton(
              icon: _isExporting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf_rounded),
              color: AppColors.primary,
              onPressed: _isExporting ? null : _exportPdf,
              tooltip: 'teacher.report_preview_screen.exportPdf'.tr(),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'teacher.report_preview_screen.reportPreview'.tr(),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 24),
                      _buildInfoRow(
                          'teacher.report_preview_screen.student'.tr(),
                          widget.studentName),
                      _buildInfoRow(
                        'teacher.report_preview_screen.unit'.tr(),
                        widget.report['unitTitle'] ??
                            'teacher.report_preview_screen.notAvailable'.tr(),
                      ),
                      _buildInfoRow(
                        'teacher.report_preview_screen.score'.tr(),
                        '${widget.report['quizPercent'] ?? 0}%',
                      ),
                      _buildInfoRow(
                        'teacher.report_preview_screen.activities'.tr(),
                        '${widget.report['activitiesCompleted'] ?? 0}/${widget.report['totalActivities'] ?? 0}',
                      ),
                      const Divider(),
                      if (widget.report['feedback'] != null &&
                          widget.report['feedback'].toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'teacher.report_preview_screen.teacherFeedback'.tr(),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
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
                          label: Text('teacher.report_preview_screen.exportAsPdf'.tr()),
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
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
