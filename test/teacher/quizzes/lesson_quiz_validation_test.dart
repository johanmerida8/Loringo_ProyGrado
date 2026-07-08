// test/teacher/quizzes/lesson_quiz_validation_test.dart
import 'package:flutter_test/flutter_test.dart';

/// ============================================
/// LESSON QUIZ - Práctica de Refuerzo
/// - Reutiliza tareas de actividades existentes
/// - NO es evaluado (solo práctica)
/// - XP: 0-10 puntos (bonificación pequeña)
/// - Muestra aciertos/desaciertos al estudiante
/// ============================================

class LessonQuizValidator {
  static String? validateTitle(String? title) {
    if (title == null || title.trim().isEmpty) {
      return 'Please enter a quiz title';
    }
    if (title.trim().length < 3) {
      return 'Title must be at least 3 characters';
    }
    return null;
  }

  /// XP limitado a 10 porque es solo práctica de refuerzo
  static String? validateXpReward(int xp) {
    if (xp < 0 || xp > 10) {
      return 'XP Reward must be between 0 and 10';
    }
    return null;
  }

  static String? validateSelectedTasks(int selectedCount) {
    if (selectedCount == 0) {
      return 'Please select at least one task';
    }
    return null;
  }
}

void main() {
  group('Lesson Quiz (Practice) Validation - AAA Pattern', () {

    test('ARRANGE-ACT-ASSERT: Teacher creates a valid practice quiz', () {
      // ARRANGE - Datos de prueba
      const String title = 'Lesson 1 Practice';
      const int xp = 5;        // Entre 0-10 XP
      const int selectedTasks = 3;

      // ACT - Ejecutar validaciones
      final titleError = LessonQuizValidator.validateTitle(title);
      final xpError = LessonQuizValidator.validateXpReward(xp);
      final taskError = LessonQuizValidator.validateSelectedTasks(selectedTasks);

      // ASSERT - Verificar que todo es válido
      expect(titleError, isNull);
      expect(xpError, isNull);
      expect(taskError, isNull);
    });

    test('ARRANGE-ACT-ASSERT: Lesson quiz XP cannot exceed 10', () {
      expect(LessonQuizValidator.validateXpReward(15), 'XP Reward must be between 0 and 10');
    });

    test('ARRANGE-ACT-ASSERT: Lesson quiz needs at least one task', () {
      expect(LessonQuizValidator.validateSelectedTasks(0), 'Please select at least one task');
    });
  });
}