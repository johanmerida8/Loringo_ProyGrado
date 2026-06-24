// test/notification/notification_permission_test.dart
import 'package:flutter_test/flutter_test.dart';

class PermissionHelper {
  static String getPermissionMessage(bool isGranted) {
    return isGranted 
        ? 'Notifications enabled' 
        : 'You can enable notifications later in settings';
  }

  static String getNotificationIcon(String type) {
    switch (type) {
      case 'quiz_report':
        return '📝';
      case 'group_invitation':
        return '👥';
      default:
        return '🔔';
    }
  }

  static String getNotificationTitle(String type) {
    switch (type) {
      case 'quiz_report':
        return 'New Report Available';
      case 'group_invitation':
        return 'Group Invitation';
      default:
        return 'Notification';
    }
  }

  static String formatNotificationMessage(String studentName, String unitTitle) {
    return '$studentName completed "$unitTitle" - Tap to view details';
  }
}

void main() {
  group('Notification Permission Logic', () {
    
    test('Should return enabled message when permission is granted', () {
      // ARRANGE
      const isGranted = true;
      const expectedMessage = 'Notifications enabled';
      
      // ACT
      final result = PermissionHelper.getPermissionMessage(isGranted);
      
      // ASSERT
      expect(result, expectedMessage);
    });

    test('Should return disabled message when permission is denied', () {
      // ARRANGE
      const isGranted = false;
      const expectedMessage = 'You can enable notifications later in settings';
      
      // ACT
      final result = PermissionHelper.getPermissionMessage(isGranted);
      
      // ASSERT
      expect(result, expectedMessage);
    });

    test('Should return 📝 icon for quiz report type', () {
      // ARRANGE
      const type = 'quiz_report';
      const expectedIcon = '📝';
      
      // ACT
      final result = PermissionHelper.getNotificationIcon(type);
      
      // ASSERT
      expect(result, expectedIcon);
    });

    test('Should return 👥 icon for group invitation type', () {
      // ARRANGE
      const type = 'group_invitation';
      const expectedIcon = '👥';
      
      // ACT
      final result = PermissionHelper.getNotificationIcon(type);
      
      // ASSERT
      expect(result, expectedIcon);
    });

    test('Should return 🔔 icon for unknown type', () {
      // ARRANGE
      const type = 'unknown';
      const expectedIcon = '🔔';
      
      // ACT
      final result = PermissionHelper.getNotificationIcon(type);
      
      // ASSERT
      expect(result, expectedIcon);
    });

    test('Should return "New Report Available" title for quiz report', () {
      // ARRANGE
      const type = 'quiz_report';
      const expectedTitle = 'New Report Available';
      
      // ACT
      final result = PermissionHelper.getNotificationTitle(type);
      
      // ASSERT
      expect(result, expectedTitle);
    });

    test('Should return "Group Invitation" title for group invitation', () {
      // ARRANGE
      const type = 'group_invitation';
      const expectedTitle = 'Group Invitation';
      
      // ACT
      final result = PermissionHelper.getNotificationTitle(type);
      
      // ASSERT
      expect(result, expectedTitle);
    });
  });
}