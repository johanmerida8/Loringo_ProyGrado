// test/parent/group_joining_test.dart
import 'package:flutter_test/flutter_test.dart';

class GroupJoiningValidator {
  static String? validateGroupCode(String? code) {
    if (code == null || code.isEmpty) {
      return 'Please enter the group code';
    }
    if (code.length != 6) {
      return 'Group code must be 6 characters';
    }
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code.toUpperCase())) {
      return 'Invalid group code format';
    }
    return null;
  }

  static String formatGroupCode(String code) {
    return code.trim().toUpperCase();
  }

  static bool canJoinGroup(bool alreadyInGroup) {
    return !alreadyInGroup;
  }

  static String getSuccessMessage(String childName, String groupName) {
    return '$childName joined the group: $groupName';
  }
}

void main() {
  group('Group Joining Logic - AAA Pattern', () {

    test('ARRANGE-ACT-ASSERT: Valid group code passes validation', () {
      // ARRANGE
      const String validCode = 'ABC123';

      // ACT
      final result = GroupJoiningValidator.validateGroupCode(validCode);

      // ASSERT
      expect(result, isNull);
    });

    test('ARRANGE-ACT-ASSERT: Empty group code is rejected', () {
      // ARRANGE
      const String emptyCode = '';

      // ACT
      final result = GroupJoiningValidator.validateGroupCode(emptyCode);

      // ASSERT
      expect(result, 'Please enter the group code');
    });

    test('ARRANGE-ACT-ASSERT: Group code with wrong length is rejected', () {
      // ARRANGE
      const String wrongLength = 'ABC12';

      // ACT
      final result = GroupJoiningValidator.validateGroupCode(wrongLength);

      // ASSERT
      expect(result, 'Group code must be 6 characters');
    });

    test('ARRANGE-ACT-ASSERT: Group code formatting converts to uppercase', () {
      // ARRANGE
      const String lowerCode = 'abc123';

      // ACT
      final formatted = GroupJoiningValidator.formatGroupCode(lowerCode);

      // ASSERT
      expect(formatted, 'ABC123');
    });

    test('ARRANGE-ACT-ASSERT: Group code formatting removes whitespace', () {
      // ARRANGE
      const String codeWithSpaces = '  abc123  ';

      // ACT
      final formatted = GroupJoiningValidator.formatGroupCode(codeWithSpaces);

      // ASSERT
      expect(formatted, 'ABC123');
    });

    test('ARRANGE-ACT-ASSERT: Student can join group if not already in one', () {
      // ARRANGE
      const bool alreadyInGroup = false;

      // ACT
      final canJoin = GroupJoiningValidator.canJoinGroup(alreadyInGroup);

      // ASSERT
      expect(canJoin, true);
    });

    test('ARRANGE-ACT-ASSERT: Student cannot join group if already in one', () {
      // ARRANGE
      const bool alreadyInGroup = true;

      // ACT
      final canJoin = GroupJoiningValidator.canJoinGroup(alreadyInGroup);

      // ASSERT
      expect(canJoin, false);
    });

    test('ARRANGE-ACT-ASSERT: Success message includes child and group names', () {
      // ARRANGE
      const String childName = 'Laura';
      const String groupName = 'Grade 1';

      // ACT
      final message = GroupJoiningValidator.getSuccessMessage(childName, groupName);

      // ASSERT
      expect(message, 'Laura joined the group: Grade 1');
    });
  });
}