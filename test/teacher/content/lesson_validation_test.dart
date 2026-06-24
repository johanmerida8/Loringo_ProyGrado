import 'package:flutter_test/flutter_test.dart';

/// ============================================
/// VALIDACIÓN DE LECCIONES (LESSONS)
/// Corresponde a: create_lesson_screen.dart
/// ============================================

class LessonValidator {
  /// Valida el título de la lección
  static String? validateTitle(String? title) {
    if (title == null || title.trim().isEmpty) return 'Title is required';
    if (title.trim().length < 3) return 'Title must be at least 3 characters';
    return null;
  }

  /// Valida el orden de la lección
  static String? validateOrder(String? order) {
    if (order == null || order.trim().isEmpty) return 'Order is required';
    final orderNum = int.tryParse(order.trim());
    if (orderNum == null) return 'Order must be a number';
    if (orderNum < 1) return 'Order must be at least 1';
    return null;
  }
}

void main() {
  group('Lesson Validation - AAA Pattern', () {

    test('ARRANGE-ACT-ASSERT: Teacher creates a valid lesson', () {
      // ARRANGE - Preparar datos válidos
      const String validTitle = 'Past Tense Basics';
      const String validOrder = '2';

      // ACT - Ejecutar validaciones
      final titleError = LessonValidator.validateTitle(validTitle);
      final orderError = LessonValidator.validateOrder(validOrder);

      // ASSERT - Verificar resultados
      expect(titleError, isNull);
      expect(orderError, isNull);
    });

    test('ARRANGE-ACT-ASSERT: Lesson title rejects empty value', () {
      // ARRANGE - Título vacío
      const String emptyTitle = '';

      // ACT
      final error = LessonValidator.validateTitle(emptyTitle);

      // ASSERT
      expect(error, 'Title is required');
    });

    test('ARRANGE-ACT-ASSERT: Lesson title rejects short value', () {
      // ARRANGE - Título muy corto (solo 2 caracteres)
      const String shortTitle = 'Ab';

      // ACT
      final error = LessonValidator.validateTitle(shortTitle);

      // ASSERT
      expect(error, 'Title must be at least 3 characters');
    });

    test('ARRANGE-ACT-ASSERT: Lesson order rejects empty value', () {
      // ARRANGE - Orden vacío
      const String emptyOrder = '';

      // ACT
      final error = LessonValidator.validateOrder(emptyOrder);

      // ASSERT
      expect(error, 'Order is required');
    });

    test('ARRANGE-ACT-ASSERT: Lesson order rejects non-numeric value', () {
      // ARRANGE - Orden no numérico
      const String nonNumericOrder = 'abc';

      // ACT
      final error = LessonValidator.validateOrder(nonNumericOrder);

      // ASSERT
      expect(error, 'Order must be a number');
    });

    test('ARRANGE-ACT-ASSERT: Lesson order rejects zero or negative', () {
      // ARRANGE - Orden cero y negativo
      const String zeroOrder = '0';
      const String negativeOrder = '-1';

      // ACT
      final zeroError = LessonValidator.validateOrder(zeroOrder);
      final negativeError = LessonValidator.validateOrder(negativeOrder);

      // ASSERT
      expect(zeroError, 'Order must be at least 1');
      expect(negativeError, 'Order must be at least 1');
    });

    test('ARRANGE-ACT-ASSERT: Lesson order accepts positive numbers', () {
      // ARRANGE - Órdenes válidos
      const String order1 = '1';
      const String order5 = '5';
      const String order10 = '10';

      // ACT
      final error1 = LessonValidator.validateOrder(order1);
      final error5 = LessonValidator.validateOrder(order5);
      final error10 = LessonValidator.validateOrder(order10);

      // ASSERT
      expect(error1, isNull);
      expect(error5, isNull);
      expect(error10, isNull);
    });
  });
}