// test/teacher/unit_validation_test.dart
import 'package:flutter_test/flutter_test.dart';

/// ============================================
/// VALIDACIÓN DE UNIDADES (UNITS)
/// Corresponde a: create_unit_screen.dart
/// ============================================

class UnitValidator {
  /// Valida el título de la unidad
  static String? validateTitle(String? title) {
    if (title == null || title.trim().isEmpty) {
      return 'Title is required';
    }
    if (title.trim().length < 3) {
      return 'Title must be at least 3 characters';
    }
    return null;
  }

  /// Valida el orden de la unidad
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
}

void main() {
  group('Unit Validation - AAA Pattern', () {

    // PRUEBA 1: Creación de unidad válida
    test('ARRANGE-ACT-ASSERT: Teacher creates a valid unit', () {
      // ARRANGE
      const String validTitle = 'Introduction to Numbers';
      const String validOrder = '2';

      // ACT
      final titleError = UnitValidator.validateTitle(validTitle);
      final orderError = UnitValidator.validateOrder(validOrder);

      // ASSERT
      expect(titleError, isNull);
      expect(orderError, isNull);
    });

    // PRUEBA 2: Validación de título
    test('ARRANGE-ACT-ASSERT: Title rejects empty or short values', () {
      // ARRANGE
      const String emptyTitle = '';
      const String shortTitle = 'Ab';

      // ACT
      final emptyError = UnitValidator.validateTitle(emptyTitle);
      final shortError = UnitValidator.validateTitle(shortTitle);

      // ASSERT
      expect(emptyError, 'Title is required');
      expect(shortError, 'Title must be at least 3 characters');
    });

    // PRUEBA 3: Validación de orden
    test('ARRANGE-ACT-ASSERT: Order rejects invalid values', () {
      // ARRANGE
      const String emptyOrder = '';
      const String nonNumericOrder = 'abc';
      const String zeroOrder = '0';
      const String negativeOrder = '-1';

      // ACT
      final emptyError = UnitValidator.validateOrder(emptyOrder);
      final nonNumericError = UnitValidator.validateOrder(nonNumericOrder);
      final zeroError = UnitValidator.validateOrder(zeroOrder);
      final negativeError = UnitValidator.validateOrder(negativeOrder);

      // ASSERT
      expect(emptyError, 'Order is required');
      expect(nonNumericError, 'Order must be a number');
      expect(zeroError, 'Order must be at least 1');
      expect(negativeError, 'Order must be at least 1');
    });

    // PRUEBA 4: Orden válido acepta números positivos
    test('ARRANGE-ACT-ASSERT: Valid order accepts positive numbers', () {
      // ARRANGE
      const String order1 = '1';
      const String order5 = '5';
      const String order10 = '10';

      // ACT
      final error1 = UnitValidator.validateOrder(order1);
      final error5 = UnitValidator.validateOrder(order5);
      final error10 = UnitValidator.validateOrder(order10);

      // ASSERT
      expect(error1, isNull);
      expect(error5, isNull);
      expect(error10, isNull);
    });
  });
}