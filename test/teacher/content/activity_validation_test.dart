// test/teacher/activity_validation_test.dart
import 'package:flutter_test/flutter_test.dart';

/// ============================================
/// VALIDACIÓN DE ACTIVIDADES
/// Corresponde a: create_activity_screen.dart
/// ============================================

class ActivityValidator {
  /// Valida el título
  static String? validateTitle(String? title) {
    if (title == null || title.trim().isEmpty) {
      return 'Activity title is required';
    }
    if (title.trim().length < 3) {
      return 'Title must be at least 3 characters';
    }
    return null;
  }

  /// Valida el orden
  static String? validateOrder(String? order) {
    if (order == null || order.trim().isEmpty) {
      return 'Order is required';
    }
    final orderNum = int.tryParse(order.trim());
    if (orderNum == null) {
      return 'Order must be a number';
    }
    if (orderNum < 1) {
      return 'Order must be at least 1';
    }
    return null;
  }

  /// Valida los puntos de experiencia (XP)
  static String? validateXP(String? xp) {
    if (xp == null || xp.trim().isEmpty) {
      return 'XP is required';
    }
    final xpNum = int.tryParse(xp.trim());
    if (xpNum == null) {
      return 'XP must be a number';
    }
    if (xpNum < 0 || xpNum > 50) {
      return 'XP must be between 0 and 50';
    }
    return null;
  }

  /// Determina la dificultad según XP
  static String getDifficultyFromXP(int xp) {
    if (xp <= 15) return 'easy';
    if (xp <= 30) return 'medium';
    return 'hard';
  }
}

void main() {
  group('Activity Validation - AAA Pattern', () {

    // PRUEBA 1: Creación de actividad válida
    test('ARRANGE-ACT-ASSERT: Teacher creates a valid activity', () {
      // ARRANGE
      const String validTitle = 'Listening Exercise';
      const String validOrder = '3';
      const String validXP = '25';

      // ACT
      final titleError = ActivityValidator.validateTitle(validTitle);
      final orderError = ActivityValidator.validateOrder(validOrder);
      final xpError = ActivityValidator.validateXP(validXP);
      final difficulty = ActivityValidator.getDifficultyFromXP(25);

      // ASSERT
      expect(titleError, isNull);
      expect(orderError, isNull);
      expect(xpError, isNull);
      expect(difficulty, 'medium');
    });

    // PRUEBA 2: Validación de título
    test('ARRANGE-ACT-ASSERT: Title rejects empty or short values', () {
      // ARRANGE
      const String emptyTitle = '';
      const String shortTitle = 'Ab';

      // ACT
      final emptyError = ActivityValidator.validateTitle(emptyTitle);
      final shortError = ActivityValidator.validateTitle(shortTitle);

      // ASSERT
      expect(emptyError, 'Activity title is required');
      expect(shortError, 'Title must be at least 3 characters');
    });

    // PRUEBA 3: Validación de orden
    test('ARRANGE-ACT-ASSERT: Order rejects invalid values', () {
      // ARRANGE
      const String emptyOrder = '';
      const String nonNumericOrder = 'abc';
      const String zeroOrder = '0';

      // ACT
      final emptyError = ActivityValidator.validateOrder(emptyOrder);
      final nonNumericError = ActivityValidator.validateOrder(nonNumericOrder);
      final zeroError = ActivityValidator.validateOrder(zeroOrder);

      // ASSERT
      expect(emptyError, 'Order is required');
      expect(nonNumericError, 'Order must be a number');
      expect(zeroError, 'Order must be at least 1');
    });

    // PRUEBA 4: Validación de XP
    test('ARRANGE-ACT-ASSERT: XP rejects invalid values', () {
      // ARRANGE
      const String emptyXP = '';
      const String nonNumericXP = 'abc';
      const String negativeXP = '-5';
      const String tooHighXP = '75';

      // ACT
      final emptyError = ActivityValidator.validateXP(emptyXP);
      final nonNumericError = ActivityValidator.validateXP(nonNumericXP);
      final negativeError = ActivityValidator.validateXP(negativeXP);
      final tooHighError = ActivityValidator.validateXP(tooHighXP);

      // ASSERT
      expect(emptyError, 'XP is required');
      expect(nonNumericError, 'XP must be a number');
      expect(negativeError, 'XP must be between 0 and 50');
      expect(tooHighError, 'XP must be between 0 and 50');
    });

    // PRUEBA 5: Mapeo de XP a dificultad
    test('ARRANGE-ACT-ASSERT: XP maps to correct difficulty', () {
      // ARRANGE & ACT
      final easy = ActivityValidator.getDifficultyFromXP(10);
      final medium = ActivityValidator.getDifficultyFromXP(25);
      final hard = ActivityValidator.getDifficultyFromXP(40);

      // ASSERT
      expect(easy, 'easy');
      expect(medium, 'medium');
      expect(hard, 'hard');
    });
  });
}