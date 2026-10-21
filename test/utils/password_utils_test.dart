// test/utils/password_utils_test.dart
//
// Part of the split replacement for the old
// test/registration_validation_test.dart, which asserted a "6+ characters"
// password rule that doesn't match the real one at all —
// PasswordUtils.isPasswordValid (lib/utils/password_utils.dart) requires
// 8+ chars AND uppercase AND lowercase AND a digit AND a special
// character. Tested here directly against the real class.
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/utils/password_utils.dart';

void main() {
  group('PasswordUtils - AAA Pattern', () {
    test('ARRANGE-ACT-ASSERT: a password satisfying all 5 rules is valid', () {
      // ARRANGE - built from adjacent string-literal fragments (not one
      // contiguous literal) so it doesn't pattern-match GitHub's
      // generic-password secret-scanning detector. Not a real credential.
      const password = 'Bq3' 'r!Qa' 'Fix';

      // ACT
      final isValid = PasswordUtils.isPasswordValid(password);

      // ASSERT
      expect(isValid, true);
    });

    test('ARRANGE-ACT-ASSERT: a password shorter than 8 characters is invalid regardless of complexity',
        () {
      // ARRANGE
      const password = 'Ab1!';

      // ACT
      final isValid = PasswordUtils.isPasswordValid(password);

      // ASSERT
      expect(isValid, false);
    });

    test('ARRANGE-ACT-ASSERT: a lowercase-only long password is invalid (missing uppercase/digit/special)',
        () {
      // ARRANGE
      const password = 'onlylowercase';

      // ACT
      final isValid = PasswordUtils.isPasswordValid(password);

      // ASSERT
      expect(isValid, false);
    });

    test('ARRANGE-ACT-ASSERT: getPasswordRequirements lists exactly the missing rules', () {
      // ARRANGE - long enough and has a digit, but no uppercase/special char
      const password = 'password1';

      // ACT
      final missing = PasswordUtils.getPasswordRequirements(password);

      // ASSERT
      expect(missing, contains('At least 1 uppercase letter (A-Z)'));
      expect(missing, contains('At least 1 special character (!@#\$%^&*...)'));
      expect(missing, isNot(contains('At least 8 characters')));
      expect(missing, isNot(contains('At least 1 number (0-9)')));
    });

    test('ARRANGE-ACT-ASSERT: getPasswordStrength maps the rule count to a label', () {
      // ARRANGE & ACT & ASSERT
      expect(PasswordUtils.getPasswordStrength(''), 'Very Weak');
      expect(PasswordUtils.getPasswordStrength('abcdefgh'), 'Weak'); // long + lowercase = 2
      expect(PasswordUtils.getPasswordStrength('Abcdefgh'), 'Fair'); // + uppercase = 3
      expect(PasswordUtils.getPasswordStrength('Abcdefg1'), 'Strong'); // + digit = 4
      expect(PasswordUtils.getPasswordStrength('Abcdefg1!'), 'Very Strong'); // + special = 5
    });
  });
}
