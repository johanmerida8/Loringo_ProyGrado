// screens/teacher/student_reports_history_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/report_preview_screen.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

// ── StudentReportsHistoryScreen ─────────────────────────────────────────────
//
// Muestra TODOS los reportes de un estudiante, de por vida — camina cada
// grupo al que el estudiante haya pertenecido (ver Database.getAllReportsEver),
// no solo los del grupo actual, ya que "All Units" implica historial
// completo sin importar si el estudiante cambió de grupo desde entonces.
// Un reporte por unidad (teacherGroups/{groupId}/students/{studentId}/reports/{unitId}
// usa unitId como ID fijo), nunca duplicados. Cada ítem abre el
// ReportPreviewScreen existente con ese reporte específico.

class StudentReportsHistoryScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final Map<String, dynamic> studentData;

  const StudentReportsHistoryScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.studentData,
  });

  @override
  State<StudentReportsHistoryScreen> createState() =>
      _StudentReportsHistoryScreenState();
}

class _StudentReportsHistoryScreenState
    extends State<StudentReportsHistoryScreen> {
  late final Future<List<Map<String, dynamic>>> _reportsFuture =
      Database().getAllReportsEver(widget.studentId).then((reports) {
    reports.sort((a, b) {
      final at = a['generatedAt'] as Timestamp?;
      final bt = b['generatedAt'] as Timestamp?;
      if (at == null || bt == null) return 0;
      return bt.compareTo(at);
    });
    return reports;
  });

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('teacher.student_report_history_screen.reportsFor'
            .tr(namedArgs: {'name': widget.studentName})),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _reportsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.picture_as_pdf_outlined,
                      size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text('teacher.student_report_history_screen.noReportsSentYet'.tr(),
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 15)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final report = docs[index];
              final unitTitle = report['unitTitle'] as String? ??
                  'teacher.student_report_history_screen.unit'.tr();
              final quizPercent = (report['quizPercent'] as num?)?.toInt() ?? 0;
              final generatedAt = report['generatedAt'] as Timestamp?;
              final dateStr = generatedAt != null
                  ? '${generatedAt.toDate().day}/${generatedAt.toDate().month}/${generatedAt.toDate().year}'
                  : 'teacher.student_report_history_screen.notAvailable'.tr();

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.picture_as_pdf_rounded,
                        color: AppColors.primary),
                  ),
                  title: Text(unitTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      'teacher.student_report_history_screen.percentSentDate'
                          .tr(namedArgs: {
                    'percent': '$quizPercent',
                    'date': dateStr,
                  })),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReportPreviewScreen(
                          studentName: widget.studentName,
                          studentData: widget.studentData,
                          report: report,
                          allReports: docs,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}