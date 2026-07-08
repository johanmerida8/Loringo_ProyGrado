// screens/teacher/student_reports_history_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/report_preview_screen.dart';
import 'package:loringo_app/theme/app_theme.dart';

// ── StudentReportsHistoryScreen ─────────────────────────────────────────────
//
// Muestra TODOS los reportes de un estudiante (uno por unidad, ya que
// students/{studentId}/reports/{unitId} usa unitId como ID fijo — un
// reporte por unidad, nunca duplicados). Se usa cuando el filtro del
// dashboard está en "All Units"; cada ítem abre el ReportPreviewScreen
// existente con ese reporte específico.

class StudentReportsHistoryScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('Reports: $studentName'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('students')
            .doc(studentId)
            .collection('reports')
            .orderBy('generatedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.picture_as_pdf_outlined,
                      size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text('No reports sent yet',
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
              final report = docs[index].data() as Map<String, dynamic>;
              final unitTitle = report['unitTitle'] as String? ?? 'Unit';
              final quizPercent = (report['quizPercent'] as num?)?.toInt() ?? 0;
              final generatedAt = report['generatedAt'] as Timestamp?;
              final dateStr = generatedAt != null
                  ? '${generatedAt.toDate().day}/${generatedAt.toDate().month}/${generatedAt.toDate().year}'
                  : 'N/A';

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
                  subtitle: Text('$quizPercent% · Sent $dateStr'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReportPreviewScreen(
                          studentName: studentName,
                          studentData: studentData,
                          report: report,
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