// screens/teacher/progress/unit_report_loader_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/progress/report_preview_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';

// ── UnitReportLoaderScreen ──────────────────────────────────────────────────
//
// The "Report" button of the progress dashboard with a single unit selected.
// It opens right away (like "Reports" under All Units does) and loads the
// data here, behind the same clean header, then shows ReportPreviewScreen.
//
// Loads at once: this unit's report (reports/{unitId} uses the unitId as its
// fixed doc id, so it's a direct read) and every report the
// student has ever had (every group), which the Progress Trend compares
// against. This unit's copy is taken from that list because it also carries
// the activities average for reports sent before that field was stored.

class UnitReportLoaderScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String groupId;
  final String unitId;

  const UnitReportLoaderScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.groupId,
    required this.unitId,
  });

  @override
  State<UnitReportLoaderScreen> createState() => _UnitReportLoaderScreenState();
}

class _UnitReportLoaderScreenState extends State<UnitReportLoaderScreen> {
  late final Future<ReportPreviewScreen?> _future = _load();

  Future<ReportPreviewScreen?> _load() async {
    final results = await Future.wait<Object>([
      FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(widget.groupId)
          .collection('students')
          .doc(widget.studentId)
          .collection('reports')
          .doc(widget.unitId)
          .get(),
      Database().getAllReportsEver(widget.studentId),
    ]);
    final reportDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final allReports = results[1] as List<Map<String, dynamic>>;

    if (!reportDoc.exists) return null;

    final report = allReports.firstWhere(
      (r) => r['id'] == widget.unitId,
      orElse: () => reportDoc.data()!,
    );
    return ReportPreviewScreen(
      studentName: widget.studentName,
      report: report,
      allReports: allReports,
    );
  }

  Widget _message(String text) => Scaffold(
        backgroundColor: Colors.grey[50],
        body: Column(
          children: [
            TeacherScreenHeader(
              title: 'teacher.report_preview_screen.reportFor'
                  .tr(namedArgs: {'name': widget.studentName}),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(text, textAlign: TextAlign.center),
                ),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return FutureBuilder<ReportPreviewScreen?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: Colors.grey[50],
            body: Column(
              children: [
                TeacherScreenHeader(
                  title: 'teacher.report_preview_screen.reportFor'
                      .tr(namedArgs: {'name': widget.studentName}),
                ),
                const Expanded(
                    child: Center(child: CircularProgressIndicator())),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return _message('teacher.student_progress_dashboard.errorLoadingReport'
              .tr(namedArgs: {'error': '${snapshot.error}'}));
        }
        return snapshot.data ??
            _message(
                'teacher.student_progress_dashboard.noReportSentYet'.tr());
      },
    );
  }
}
