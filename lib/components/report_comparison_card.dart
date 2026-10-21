// lib/components/report_comparison_card.dart
//
// In-app equivalent of the "Progress Trend" block in unit_report_pdf.dart --
// same data (ReportComparison), same trend message, so the report preview
// screens and the exported PDF never show different numbers. It compares the
// average of each unit's activity scores.

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/report_comparison.dart';

class ReportComparisonCard extends StatelessWidget {
  final ReportComparison comparison;
  final String unitTitle;
  // This report's activities average.
  final int activitiesPercent;

  const ReportComparisonCard({
    super.key,
    required this.comparison,
    required this.unitTitle,
    required this.activitiesPercent,
  });

  @override
  Widget build(BuildContext context) {
    if (!comparison.hasData) return const SizedBox.shrink();

    final previousReport = comparison.previousReport!;
    final previousUnitTitle =
        (previousReport['unitTitle'] as String?) ?? 'common.previousUnit'.tr();
    final previousPercent =
        (previousReport['activitiesAvgScore'] as num?)?.toInt() ?? 0;
    final difference =
        comparison.trendDifference ?? (activitiesPercent - previousPercent);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'common.progressTrend'.tr(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            'common.trendActivities'.tr(),
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _scoreColumn(previousUnitTitle, previousPercent, Colors.grey[700]!),
              _scoreColumn(unitTitle, activitiesPercent, AppColors.primary),
              if (comparison.averagePreviousPercent != null)
                _scoreColumn(
                  'common.averagePreviousUnits'.tr(),
                  comparison.averagePreviousPercent!,
                  Colors.grey[700]!,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            reportTrendMessage(difference),
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreColumn(String label, int percent, Color valueColor) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
          ),
          const SizedBox(height: 2),
          Text(
            '$percent%',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: valueColor),
          ),
        ],
      ),
    );
  }
}
