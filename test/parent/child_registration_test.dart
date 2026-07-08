// test/parent/child_registration_test.dart
import 'package:flutter_test/flutter_test.dart';

class ChildRegistrationValidator {
  static const String _validChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  
  static String? validateChildName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return 'Please enter your child\'s name';
    }
    if (name.trim().length < 2) {
      return 'Name must be at least 2 characters';
    }
    return null;
  }

  static String generateAccessCode() {
    final random = DateTime.now().millisecondsSinceEpoch;
    final code = String.fromCharCodes(
      List.generate(6, (_) => _validChars.codeUnitAt(random % _validChars.length))
    );
    return code.toUpperCase();
  }

  static bool isValidAccessCode(String code) {
    if (code.length != 6) return false;
    final validPattern = RegExp(r'^[A-Z2-9]{6}$');
    return validPattern.hasMatch(code);
  }

  static String? validateAccessCode(String? code) {
    if (code == null || code.isEmpty) return 'Access code is required';
    if (code.length != 6) return 'Access code must be 6 characters';
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
      return 'Access code must contain only letters and numbers';
    }
    return null;
  }
}

void main() {
  group('Child Registration Logic - AAA Pattern', () {

    test('ARRANGE-ACT-ASSERT: Valid child name passes validation', () {
      // ARRANGE
      const String validName = 'Laura';

      // ACT
      final result = ChildRegistrationValidator.validateChildName(validName);

      // ASSERT
      expect(result, isNull);
    });

    test('ARRANGE-ACT-ASSERT: Empty child name is rejected', () {
      // ARRANGE
      const String emptyName = '';

      // ACT
      final result = ChildRegistrationValidator.validateChildName(emptyName);

      // ASSERT
      expect(result, 'Please enter your child\'s name');
    });

    test('ARRANGE-ACT-ASSERT: Name too short (less than 2 chars) is rejected', () {
      // ARRANGE
      const String shortName = 'A';

      // ACT
      final result = ChildRegistrationValidator.validateChildName(shortName);

      // ASSERT
      expect(result, 'Name must be at least 2 characters');
    });

    test('ARRANGE-ACT-ASSERT: Generated access code has 6 characters', () {
      // ARRANGE - No setup needed
      
      // ACT
      final code = ChildRegistrationValidator.generateAccessCode();

      // ASSERT
      expect(code.length, 6);
    });

    test('ARRANGE-ACT-ASSERT: Generated access code uses valid characters', () {
      // ARRANGE - No setup needed
      
      // ACT
      final code = ChildRegistrationValidator.generateAccessCode();

      // ASSERT
      expect(ChildRegistrationValidator.isValidAccessCode(code), true);
    });

    test('ARRANGE-ACT-ASSERT: Empty access code is rejected', () {
      // ARRANGE
      const String emptyCode = '';

      // ACT
      final result = ChildRegistrationValidator.validateAccessCode(emptyCode);

      // ASSERT
      expect(result, 'Access code is required');
    });

    test('ARRANGE-ACT-ASSERT: Access code with wrong length is rejected', () {
      // ARRANGE
      const String wrongLengthCode = 'ABC12';

      // ACT
      final result = ChildRegistrationValidator.validateAccessCode(wrongLengthCode);

      // ASSERT
      expect(result, 'Access code must be 6 characters');
    });

    test('ARRANGE-ACT-ASSERT: Valid access code passes validation', () {
      // ARRANGE
      const String validCode = 'ABC123';

      // ACT
      final result = ChildRegistrationValidator.validateAccessCode(validCode);

      // ASSERT
      expect(result, isNull);
    });
  });
}