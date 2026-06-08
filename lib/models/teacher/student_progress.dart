import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';

// ============================================================================
// Unit Information Model
// ============================================================================
class UnitInfo {
  final String contentId;
  final String unitId;
  final String unitTitle;
  final List<String> activityIds;
  final List<String> lessonQuizIds;
  final String? unitQuizId;

  const UnitInfo({
    required this.contentId,
    required this.unitId,
    required this.unitTitle,
    required this.activityIds,
    required this.lessonQuizIds,
    required this.unitQuizId,
  });

  factory UnitInfo.fromFirestore({
    required String contentId,
    required String unitId,
    required String unitTitle,
    required List<String> activityIds,
    required List<String> lessonQuizIds,
    String? unitQuizId,
  }) {
    return UnitInfo(
      contentId: contentId,
      unitId: unitId,
      unitTitle: unitTitle,
      activityIds: activityIds,
      lessonQuizIds: lessonQuizIds,
      unitQuizId: unitQuizId,
    );
  }

  int get totalActivities => activityIds.length;
  int get totalLessonQuizzes => lessonQuizIds.length;
  bool get hasUnitQuiz => unitQuizId != null;
  int get totalQuizzes => totalLessonQuizzes + (hasUnitQuiz ? 1 : 0);
}

// ============================================================================
// Unit Raw Data (for progress calculation)
// ============================================================================
class UnitRawData {
  int completedActivities = 0;
  int totalActivities = 0;
  int activityScoreSum = 0;
  
  int completedLessonQuizzes = 0;
  int totalLessonQuizzes = 0;
  int lessonQuizScoreSum = 0;
  
  int? unitQuizScore;
  int? unitQuizTotal;

  UnitRawData();

  // Calculated properties
  int get avgActivityScore => completedActivities == 0 ? 0 : (activityScoreSum / completedActivities).round();
  
  int get avgLessonQuizScore => completedLessonQuizzes == 0 ? 0 : (lessonQuizScoreSum / completedLessonQuizzes).round();
  
  int get unitQuizPercent {
    if (unitQuizTotal == null || unitQuizTotal == 0 || unitQuizScore == null) return 0;
    return (unitQuizScore! / unitQuizTotal! * 100).round();
  }
  
  int get overallScore {
    return (
      (avgActivityScore * 0.4) +
      (avgLessonQuizScore * 0.3) +
      (unitQuizPercent * 0.3)
    ).round();
  }
  
  int get overallStars {
    if (overallScore >= 90) return 3;
    if (overallScore >= 70) return 2;
    return 1;
  }
  
  double get activityProgress => totalActivities == 0 ? 0 : completedActivities / totalActivities;
  double get lessonQuizProgress => totalLessonQuizzes == 0 ? 0 : completedLessonQuizzes / totalLessonQuizzes;
}

// ============================================================================
// Raw Progress (per student)
// ============================================================================
class RawProgress {
  final int xp;
  final Map<String, UnitRawData> byUnit;

  const RawProgress({
    required this.xp,
    required this.byUnit,
  });

  factory RawProgress.empty() {
    return const RawProgress(xp: 0, byUnit: {});
  }
}

// ============================================================================
// Student Statistics (display model)
// ============================================================================
class StudentStats {
  final String studentId;
  final String name;
  final String avatar;
  final int xp;
  
  // Activity stats
  final int completedActivities;
  final int totalActivities;
  final int avgActivityScore;
  
  // Quiz stats
  final int completedLessonQuizzes;
  final int totalLessonQuizzes;
  final int avgLessonQuizScore;
  final int? unitQuizScore;
  final int? unitQuizTotal;
  final int unitQuizPercent;
  
  // Overall
  final int overallScore;
  final int overallStars;

  const StudentStats({
    required this.studentId,
    required this.name,
    required this.avatar,
    required this.xp,
    required this.completedActivities,
    required this.totalActivities,
    required this.avgActivityScore,
    required this.completedLessonQuizzes,
    required this.totalLessonQuizzes,
    required this.avgLessonQuizScore,
    required this.unitQuizScore,
    required this.unitQuizTotal,
    required this.unitQuizPercent,
    required this.overallScore,
    required this.overallStars,
  });

  double get activityPercent => totalActivities == 0 ? 0 : completedActivities / totalActivities;
  double get lessonQuizPercent => totalLessonQuizzes == 0 ? 0 : completedLessonQuizzes / totalLessonQuizzes;
  
  String get activityProgressText => '$completedActivities/$totalActivities';
  String get lessonQuizProgressText => '$completedLessonQuizzes/$totalLessonQuizzes';
  String get avgActivityScoreText => '$avgActivityScore%';
  String get avgLessonQuizScoreText => '$avgLessonQuizScore%';
  String get overallScoreText => '$overallScore%';
  
  Color get overallScoreColor {
    if (overallScore >= 80) return const Color(0xFF4CAF50);
    if (overallScore >= 60) return const Color(0xFFFFC107);
    return const Color(0xFFFF7043);
  }
}

// ============================================================================
// Summary Statistics (for dashboard header)
// ============================================================================
class SummaryStats {
  final int studentCount;
  final int avgOverallScore;
  final int totalActivities;
  final int totalQuizzes;
  final int completedActivities;
  final int completedQuizzes;

  const SummaryStats({
    required this.studentCount,
    required this.avgOverallScore,
    required this.totalActivities,
    required this.totalQuizzes,
    required this.completedActivities,
    required this.completedQuizzes,
  });

  double get avgActivityProgress => totalActivities == 0 ? 0 : completedActivities / totalActivities;
  double get avgQuizProgress => totalQuizzes == 0 ? 0 : completedQuizzes / totalQuizzes;
  
  String get avgOverallScoreText => '$avgOverallScore%';
  String get avgActivityProgressText => '${(avgActivityProgress * 100).round()}%';
  String get avgQuizProgressText => '${(avgQuizProgress * 100).round()}%';
}

// ============================================================================
// Helper extension for converting Timestamp
// ============================================================================
extension TimestampExtension on Timestamp {
  DateTime toLocalDateTime() => toDate().toLocal();
}

// ============================================================================
// Helper function for stars display
// ============================================================================
String getStarDisplay(int stars) {
  switch (stars) {
    case 3: return '⭐⭐⭐';
    case 2: return '⭐⭐';
    case 1: return '⭐';
    default: return '☆';
  }
}