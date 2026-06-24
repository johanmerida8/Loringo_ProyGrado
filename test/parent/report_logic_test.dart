// test/parent/report_logic_test.dart
import 'package:flutter_test/flutter_test.dart';

class ReportCalculator {
  static int calculateQuizPercent(int correct, int total) {
    if (total == 0) return 0;
    return (correct / total * 100).round();
  }

  static int calculateActivitiesPercent(int completed, int total) {
    if (total == 0) return 0;
    return (completed / total * 100).round();
  }

  static String getScoreColor(int percent) {
    if (percent >= 80) return 'green';
    if (percent >= 60) return 'yellow';
    return 'orange';
  }

  static int getStars(int percent) {
    if (percent >= 90) return 3;
    if (percent >= 70) return 2;
    return 1;
  }

  static String getScoreMessage(int percent) {
    if (percent >= 90) return 'Excellent! Outstanding performance!';
    if (percent >= 70) return 'Good job! Keep it up!';
    if (percent >= 50) return 'Good effort! Review and try again.';
    return 'Keep practicing! You\'ll get better.';
  }
}

void main() {
  group('Report Calculation Logic - AAA Pattern', () {

    test('ARRANGE-ACT-ASSERT: Quiz percentage calculation', () {
      // ARRANGE
      const int correct = 6;
      const int total = 7;

      // ACT
      final percent = ReportCalculator.calculateQuizPercent(correct, total);

      // ASSERT
      expect(percent, 86);
    });

    test('ARRANGE-ACT-ASSERT: Activities percentage calculation - all completed', () {
      // ARRANGE
      const int completed = 5;
      const int total = 5;

      // ACT
      final percent = ReportCalculator.calculateActivitiesPercent(completed, total);

      // ASSERT
      expect(percent, 100);
    });

    test('ARRANGE-ACT-ASSERT: Activities percentage calculation - partial', () {
      // ARRANGE
      const int completed = 3;
      const int total = 5;

      // ACT
      final percent = ReportCalculator.calculateActivitiesPercent(completed, total);

      // ASSERT
      expect(percent, 60);
    });

    test('ARRANGE-ACT-ASSERT: Zero total returns 0 percent', () {
      // ARRANGE
      const int completed = 0;
      const int total = 0;

      // ACT
      final percent = ReportCalculator.calculateActivitiesPercent(completed, total);

      // ASSERT
      expect(percent, 0);
    });

    test('ARRANGE-ACT-ASSERT: Score color - green for 80%+', () {
      // ARRANGE
      const int highPercent = 90;

      // ACT
      final color = ReportCalculator.getScoreColor(highPercent);

      // ASSERT
      expect(color, 'green');
    });

    test('ARRANGE-ACT-ASSERT: Score color - yellow for 60-79%', () {
      // ARRANGE
      const int mediumPercent = 75;

      // ACT
      final color = ReportCalculator.getScoreColor(mediumPercent);

      // ASSERT
      expect(color, 'yellow');
    });

    test('ARRANGE-ACT-ASSERT: Score color - orange for below 60%', () {
      // ARRANGE
      const int lowPercent = 50;

      // ACT
      final color = ReportCalculator.getScoreColor(lowPercent);

      // ASSERT
      expect(color, 'orange');
    });

    test('ARRANGE-ACT-ASSERT: Stars - 3 stars for 90%+', () {
      // ARRANGE
      const int highPercent = 95;

      // ACT
      final stars = ReportCalculator.getStars(highPercent);

      // ASSERT
      expect(stars, 3);
    });

    test('ARRANGE-ACT-ASSERT: Stars - 2 stars for 70-89%', () {
      // ARRANGE
      const int mediumPercent = 80;

      // ACT
      final stars = ReportCalculator.getStars(mediumPercent);

      // ASSERT
      expect(stars, 2);
    });

    test('ARRANGE-ACT-ASSERT: Stars - 1 star for below 70%', () {
      // ARRANGE
      const int lowPercent = 65;

      // ACT
      final stars = ReportCalculator.getStars(lowPercent);

      // ASSERT
      expect(stars, 1);
    });

    test('ARRANGE-ACT-ASSERT: Score message for excellent performance (90%+)', () {
      // ARRANGE
      const int excellentScore = 95;

      // ACT
      final message = ReportCalculator.getScoreMessage(excellentScore);

      // ASSERT
      expect(message, 'Excellent! Outstanding performance!');
    });

    test('ARRANGE-ACT-ASSERT: Score message for good performance (70-89%)', () {
      // ARRANGE
      const int goodScore = 75;

      // ACT
      final message = ReportCalculator.getScoreMessage(goodScore);

      // ASSERT
      expect(message, 'Good job! Keep it up!');
    });

    test('ARRANGE-ACT-ASSERT: Score message for fair performance (50-69%)', () {
      // ARRANGE
      const int fairScore = 55;

      // ACT
      final message = ReportCalculator.getScoreMessage(fairScore);

      // ASSERT
      expect(message, 'Good effort! Review and try again.');
    });

    test('ARRANGE-ACT-ASSERT: Score message for needs improvement (below 50%)', () {
      // ARRANGE
      const int lowScore = 40;

      // ACT
      final message = ReportCalculator.getScoreMessage(lowScore);

      // ASSERT
      expect(message, 'Keep practicing! You\'ll get better.');
    });
  });
}