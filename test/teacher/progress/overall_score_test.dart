// test/teacher/progress/overall_score_test.dart
import 'package:flutter_test/flutter_test.dart';

class OverallScoreCalculator {
  static const double ACTIVITY_WEIGHT = 0.4;
  static const double LESSON_QUIZ_WEIGHT = 0.3;
  static const double UNIT_QUIZ_WEIGHT = 0.3;

  static int calculateOverallScore({
    required int avgActivityScore,
    required int avgLessonQuizScore,
    required int unitQuizPercent,
  }) {
    final weightedScore = 
        (avgActivityScore * ACTIVITY_WEIGHT) +
        (avgLessonQuizScore * LESSON_QUIZ_WEIGHT) +
        (unitQuizPercent * UNIT_QUIZ_WEIGHT);
    return weightedScore.round();
  }

  static int calculateAverage(List<int> scores) {
    if (scores.isEmpty) return 0;
    return scores.reduce((a, b) => a + b) ~/ scores.length;
  }

  static int getRank(int score, List<int> allScores) {
    final sorted = List<int>.from(allScores)..sort((a, b) => b.compareTo(a));
    return sorted.indexOf(score) + 1;
  }
}

void main() {
  group('Overall Score Calculation - AAA Pattern', () {

    test('ARRANGE-ACT-ASSERT: Perfect score in all categories', () {
      // ARRANGE
      const int avgActivity = 100;
      const int avgLessonQuiz = 100;
      const int unitQuiz = 100;

      // ACT
      final score = OverallScoreCalculator.calculateOverallScore(
        avgActivityScore: avgActivity,
        avgLessonQuizScore: avgLessonQuiz,
        unitQuizPercent: unitQuiz,
      );

      // ASSERT
      expect(score, 100);
    });

    test('ARRANGE-ACT-ASSERT: Average performance (80% all categories)', () {
      // ARRANGE
      const int avgActivity = 80;
      const int avgLessonQuiz = 80;
      const int unitQuiz = 80;

      // ACT
      final score = OverallScoreCalculator.calculateOverallScore(
        avgActivityScore: avgActivity,
        avgLessonQuizScore: avgLessonQuiz,
        unitQuizPercent: unitQuiz,
      );

      // ASSERT
      expect(score, 80);
    });

    test('ARRANGE-ACT-ASSERT: Low activities, high quizzes', () {
      // ARRANGE
      const int avgActivity = 50;
      const int avgLessonQuiz = 100;
      const int unitQuiz = 100;

      // ACT
      final score = OverallScoreCalculator.calculateOverallScore(
        avgActivityScore: avgActivity,
        avgLessonQuizScore: avgLessonQuiz,
        unitQuizPercent: unitQuiz,
      );

      // ASSERT - 50*0.4 + 100*0.3 + 100*0.3 = 20+30+30 = 80
      expect(score, 80);
    });

    test('ARRANGE-ACT-ASSERT: Average calculation from list', () {
      // ARRANGE
      const List<int> scores = [80, 90, 100];

      // ACT
      final average = OverallScoreCalculator.calculateAverage(scores);

      // ASSERT
      expect(average, 90);
    });

    test('ARRANGE-ACT-ASSERT: Empty list returns 0', () {
      // ARRANGE
      const List<int> emptyList = [];

      // ACT
      final average = OverallScoreCalculator.calculateAverage(emptyList);

      // ASSERT
      expect(average, 0);
    });

    test('ARRANGE-ACT-ASSERT: Rank calculation - first place', () {
      // ARRANGE
      const int score = 95;
      const List<int> allScores = [95, 85, 75, 65, 55];

      // ACT
      final rank = OverallScoreCalculator.getRank(score, allScores);

      // ASSERT
      expect(rank, 1);
    });

    test('ARRANGE-ACT-ASSERT: Rank calculation - third place', () {
      // ARRANGE
      const int score = 75;
      const List<int> allScores = [95, 85, 75, 65, 55];

      // ACT
      final rank = OverallScoreCalculator.getRank(score, allScores);

      // ASSERT
      expect(rank, 3);
    });
  });
}