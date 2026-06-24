// test/teacher/progress/feedback_test.dart
import 'package:flutter_test/flutter_test.dart';

class FeedbackValidator {
  static String? validateFeedback(String? feedback) {
    if (feedback == null || feedback.trim().isEmpty) {
      return 'Please add feedback before sending report';
    }
    if (feedback.trim().length < 3) {
      return 'Feedback must be at least 3 characters';
    }
    if (feedback.trim().length > 500) {
      return 'Feedback must be 500 characters or less';
    }
    return null;
  }

  static String getDefaultFeedback(int score, int total) {
    final percentage = (score / total * 100).round();
    if (percentage >= 90) return 'Excellent work! Keep up the great effort!';
    if (percentage >= 70) return 'Good job! Review the mistakes and keep practicing.';
    if (percentage >= 50) return 'Good effort! Let\'s review the material together.';
    return 'Keep practicing! You\'ll get better with more practice.';
  }

  static String formatScoreMessage(int score, int total) {
    final percentage = (score / total * 100).round();
    return 'Score: $score/$total ($percentage%)';
  }
}

void main() {
  group('Teacher Feedback Logic - AAA Pattern', () {

    test('ARRANGE-ACT-ASSERT: Valid feedback passes validation', () {
      // ARRANGE
      const String validFeedback = 'Great job!';

      // ACT
      final result = FeedbackValidator.validateFeedback(validFeedback);

      // ASSERT
      expect(result, isNull);
    });

    test('ARRANGE-ACT-ASSERT: Empty feedback is rejected', () {
      // ARRANGE
      const String emptyFeedback = '';

      // ACT
      final result = FeedbackValidator.validateFeedback(emptyFeedback);

      // ASSERT
      expect(result, 'Please add feedback before sending report');
    });

    test('ARRANGE-ACT-ASSERT: Feedback shorter than 3 chars is rejected', () {
      // ARRANGE
      const String shortFeedback = 'Ok';

      // ACT
      final result = FeedbackValidator.validateFeedback(shortFeedback);

      // ASSERT
      expect(result, 'Feedback must be at least 3 characters');
    });

    test('ARRANGE-ACT-ASSERT: Feedback longer than 500 chars is rejected', () {
      // ARRANGE
      final String longFeedback = 'a' * 501;

      // ACT
      final result = FeedbackValidator.validateFeedback(longFeedback);

      // ASSERT
      expect(result, 'Feedback must be 500 characters or less');
    });

    test('ARRANGE-ACT-ASSERT: Default feedback for 90%+ score', () {
      // ARRANGE
      const int score = 9;
      const int total = 10;

      // ACT
      final feedback = FeedbackValidator.getDefaultFeedback(score, total);

      // ASSERT
      expect(feedback, 'Excellent work! Keep up the great effort!');
    });

    test('ARRANGE-ACT-ASSERT: Default feedback for 70-89% score', () {
      // ARRANGE
      const int score = 8;
      const int total = 10;

      // ACT
      final feedback = FeedbackValidator.getDefaultFeedback(score, total);

      // ASSERT
      expect(feedback, 'Good job! Review the mistakes and keep practicing.');
    });

    test('ARRANGE-ACT-ASSERT: Score message format', () {
      // ARRANGE
      const int score = 8;
      const int total = 10;

      // ACT
      final message = FeedbackValidator.formatScoreMessage(score, total);

      // ASSERT
      expect(message, 'Score: 8/10 (80%)');
    });
  });
}