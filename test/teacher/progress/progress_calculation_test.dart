// test/teacher/progress/progress_calculation_test.dart
import 'package:flutter_test/flutter_test.dart';

class ProgressCalculator {
  static int calculateActivityPercentage(int completed, int total) {
    if (total == 0) return 0;
    return (completed / total * 100).round();
  }

  static int calculateQuizPercentage(int score, int total) {
    if (total == 0) return 0;
    return (score / total * 100).round();
  }

  static int calculateStars(int percentage) {
    if (percentage >= 90) return 3;
    if (percentage >= 70) return 2;
    return 1;
  }

  static String getStarDisplay(int stars) {
    switch (stars) {
      case 3: return '⭐⭐⭐';
      case 2: return '⭐⭐';
      case 1: return '⭐';
      default: return '☆';
    }
  }

  static String getScoreColor(int percentage) {
    if (percentage >= 80) return 'green';
    if (percentage >= 60) return 'orange';
    return 'red';
  }
}

void main() {
  group('Progress Calculation Logic - AAA Pattern', () {

    test('ARRANGE-ACT-ASSERT: Activity percentage - all completed', () {
      // ARRANGE
      const int completed = 5;
      const int total = 5;

      // ACT
      final percentage = ProgressCalculator.calculateActivityPercentage(completed, total);

      // ASSERT
      expect(percentage, 100);
    });

    test('ARRANGE-ACT-ASSERT: Activity percentage - partial completion', () {
      // ARRANGE
      const int completed = 3;
      const int total = 5;

      // ACT
      final percentage = ProgressCalculator.calculateActivityPercentage(completed, total);

      // ASSERT
      expect(percentage, 60);
    });

    test('ARRANGE-ACT-ASSERT: Activity percentage - zero total returns 0', () {
      // ARRANGE
      const int completed = 0;
      const int total = 0;

      // ACT
      final percentage = ProgressCalculator.calculateActivityPercentage(completed, total);

      // ASSERT
      expect(percentage, 0);
    });

    test('ARRANGE-ACT-ASSERT: Quiz percentage calculation', () {
      // ARRANGE
      const int score = 6;
      const int total = 7;

      // ACT
      final percentage = ProgressCalculator.calculateQuizPercentage(score, total);

      // ASSERT
      expect(percentage, 86);
    });

    test('ARRANGE-ACT-ASSERT: Stars - 90%+ gives 3 stars', () {
      // ARRANGE
      const int percentage = 95;

      // ACT
      final stars = ProgressCalculator.calculateStars(percentage);

      // ASSERT
      expect(stars, 3);
    });

    test('ARRANGE-ACT-ASSERT: Stars - 70-89% gives 2 stars', () {
      // ARRANGE
      const int percentage = 85;

      // ACT
      final stars = ProgressCalculator.calculateStars(percentage);

      // ASSERT
      expect(stars, 2);
    });

    test('ARRANGE-ACT-ASSERT: Stars - below 70% gives 1 star', () {
      // ARRANGE
      const int percentage = 69;

      // ACT
      final stars = ProgressCalculator.calculateStars(percentage);

      // ASSERT
      expect(stars, 1);
    });

    test('ARRANGE-ACT-ASSERT: Star display - 3 stars', () {
      // ARRANGE
      const int stars = 3;

      // ACT
      final display = ProgressCalculator.getStarDisplay(stars);

      // ASSERT
      expect(display, '⭐⭐⭐');
    });

    test('ARRANGE-ACT-ASSERT: Star display - 2 stars', () {
      // ARRANGE
      const int stars = 2;

      // ACT
      final display = ProgressCalculator.getStarDisplay(stars);

      // ASSERT
      expect(display, '⭐⭐');
    });

    test('ARRANGE-ACT-ASSERT: Star display - 1 star', () {
      // ARRANGE
      const int stars = 1;

      // ACT
      final display = ProgressCalculator.getStarDisplay(stars);

      // ASSERT
      expect(display, '⭐');
    });

    test('ARRANGE-ACT-ASSERT: Score color - green for 80%+', () {
      // ARRANGE
      const int percentage = 90;

      // ACT
      final color = ProgressCalculator.getScoreColor(percentage);

      // ASSERT
      expect(color, 'green');
    });

    test('ARRANGE-ACT-ASSERT: Score color - orange for 60-79%', () {
      // ARRANGE
      const int percentage = 70;

      // ACT
      final color = ProgressCalculator.getScoreColor(percentage);

      // ASSERT
      expect(color, 'orange');
    });

    test('ARRANGE-ACT-ASSERT: Score color - red for below 60%', () {
      // ARRANGE
      const int percentage = 50;

      // ACT
      final color = ProgressCalculator.getScoreColor(percentage);

      // ASSERT
      expect(color, 'red');
    });
  });
}