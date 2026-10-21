// lib/utils/report_comparison.dart
//
// Shared unit-report comparison logic, used by the PDF builder
// (unit_report_pdf.dart) and by the in-app report screens
// (report_preview_screen.dart, child_report_detail_screen.dart) so both
// surfaces show the same numbers instead of drifting apart.
//
// The Progress Trend compares the average of each unit's activity scores
// (`activitiesAvgScore`, saved by Database.saveReportOnly). Reports sent
// before that field existed don't carry it and are ignored here; the Unit
// Quiz result has its own section in the report and isn't part of the trend.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';

class ReportComparison {
  final Map<String, dynamic>? previousReport;
  final int? averagePreviousPercent;
  final int? trendDifference;

  const ReportComparison({
    this.previousReport,
    this.averagePreviousPercent,
    this.trendDifference,
  });

  bool get hasData => previousReport != null;
}

/// Compares [report]'s activities average against every other report in
/// [allReports] that was generated strictly before it and also carries one.
/// Returns an empty [ReportComparison] when [report] has no activities
/// average or there is nothing earlier to compare against (e.g. the
/// student's first completed unit).
ReportComparison computeReportComparison(
  Map<String, dynamic> report,
  List<Map<String, dynamic>> allReports,
) {
  final currentGeneratedAt = (report['generatedAt'] as Timestamp?)?.toDate();
  final current = (report['activitiesAvgScore'] as num?)?.toInt();
  if (currentGeneratedAt == null || current == null) {
    return const ReportComparison();
  }

  final priorReports = allReports.where((r) {
    if (identical(r, report)) return false;
    if ((r['activitiesAvgScore'] as num?) == null) return false;
    final t = (r['generatedAt'] as Timestamp?)?.toDate();
    return t != null && t.isBefore(currentGeneratedAt);
  }).toList()
    ..sort((a, b) => (b['generatedAt'] as Timestamp)
        .compareTo(a['generatedAt'] as Timestamp));

  if (priorReports.isEmpty) return const ReportComparison();

  final previousReport = priorReports.first;
  final previous = (previousReport['activitiesAvgScore'] as num).toInt();
  final scores = priorReports
      .map((r) => (r['activitiesAvgScore'] as num).toDouble())
      .toList();

  return ReportComparison(
    previousReport: previousReport,
    averagePreviousPercent:
        (scores.reduce((a, b) => a + b) / scores.length).round(),
    trendDifference: current - previous,
  );
}

/// Localized trend message for a score difference vs. the previous unit.
String reportTrendMessage(int difference) {
  if (difference >= 10) {
    return '${'common.progressDiff1'.tr()} +$difference% ${'common.progressDiff1Sub'.tr()}';
  }
  if (difference >= 5) {
    return '${'common.progressDiff2'.tr()} +$difference% ${'common.progressDiff2Sub'.tr()}';
  }
  if (difference > 0) {
    return '${'common.progressDiff3'.tr()} +$difference%. ${'common.progressDiff3Sub'.tr()}';
  }
  if (difference == 0) {
    return 'common.progressDiff4'.tr();
  }
  return '${'common.progressDiff5'.tr()} ${difference.abs()}%.';
}
