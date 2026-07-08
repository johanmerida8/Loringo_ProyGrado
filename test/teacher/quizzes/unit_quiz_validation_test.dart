// test/teacher/quizzes/unit_quiz_validation_test.dart
import 'package:flutter_test/flutter_test.dart';

/// ============================================
/// UNIT QUIZ - Examen Final de Unidad
/// - Preguntas nuevas de opción múltiple
/// - Es EVALUADO (graded)
/// - Se reporta a padres
/// - XP: 0-100 puntos (valoración más alta)
/// - Intentos limitados: 1-5 configurados por docente
/// - Puntaje mínimo configurable para aprobar
/// ============================================

class UnitQuizValidator {
  static String? validateTitle(String? title) {
    if (title == null || title.trim().isEmpty) return 'Title is required';
    if (title.trim().length < 3) return 'Title must be at least 3 characters';
    if (title.trim().length > 80) return 'Title must be 80 characters or fewer';
    return null;
  }

  static String? validatePassingScore(int passingScore, int totalQuestions) {
    if (passingScore < 1) return 'Passing score must be at least 1';
    if (passingScore > totalQuestions) return 'Passing score cannot exceed total questions';
    return null;
  }

  static String? validateMaxAttempts(int attempts) {
    if (attempts < 1 || attempts > 5) return 'Maximum attempts must be between 1 and 5';
    return null;
  }

  static String? validateXpReward(int xp) {
    if (xp < 0 || xp > 100) return 'XP Reward must be between 0 and 100';
    return null;
  }

  static int calculatePercentage(int correctCount, int totalQuestions) {
    if (totalQuestions == 0) return 0;
    return (correctCount / totalQuestions * 100).round();
  }

  static int calculateStars(int percentage) {
    if (percentage >= 90) return 3;
    if (percentage >= 70) return 2;
    if (percentage >= 50) return 1;
    return 0;
  }
}

void main() {
  group('Unit Quiz (Graded Exam) Validation - AAA Pattern', () {

    test('ARRANGE-ACT-ASSERT: Teacher creates a valid unit exam', () {
      // ARRANGE - Datos de prueba
      const String title = 'Unit 1 Final Exam';
      const int totalQuestions = 10;
      const int passingScore = 7;    // 70% para aprobar
      const int maxAttempts = 3;      // 3 intentos permitidos
      const int xpReward = 75;        // 75 XP (máximo 100)

      // ACT - Ejecutar validaciones
      final titleError = UnitQuizValidator.validateTitle(title);
      final passingError = UnitQuizValidator.validatePassingScore(passingScore, totalQuestions);
      final attemptsError = UnitQuizValidator.validateMaxAttempts(maxAttempts);
      final xpError = UnitQuizValidator.validateXpReward(xpReward);

      // ASSERT - Verificar que todo es válido
      expect(titleError, isNull);
      expect(passingError, isNull);
      expect(attemptsError, isNull);
      expect(xpError, isNull);
    });

    test('ARRANGE-ACT-ASSERT: Passing score cannot be 0', () {
      expect(UnitQuizValidator.validatePassingScore(0, 5), 'Passing score must be at least 1');
    });

    test('ARRANGE-ACT-ASSERT: Max attempts between 1 and 5', () {
      expect(UnitQuizValidator.validateMaxAttempts(0), 'Maximum attempts must be between 1 and 5');
    });

    test('ARRANGE-ACT-ASSERT: XP reward between 0 and 100', () {
      expect(UnitQuizValidator.validateXpReward(150), 'XP Reward must be between 0 and 100');
    });

    test('ARRANGE-ACT-ASSERT: Calculate percentage correctly', () {
      expect(UnitQuizValidator.calculatePercentage(7, 10), 70);
    });

    test('ARRANGE-ACT-ASSERT: Calculate stars based on percentage', () {
      expect(UnitQuizValidator.calculateStars(95), 3);
      expect(UnitQuizValidator.calculateStars(80), 2);
      expect(UnitQuizValidator.calculateStars(60), 1);
      expect(UnitQuizValidator.calculateStars(40), 0);
    });
  });
}