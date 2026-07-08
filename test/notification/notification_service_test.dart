// test/notification/notification_service_test.dart
import 'package:flutter_test/flutter_test.dart';

class NotificationValidator {
  static String? validateParentId(String? parentId) {
    if (parentId == null || parentId.isEmpty) {
      return 'Parent ID not found';
    }
    return null;
  }

  static String? validateNotificationData({
    required String studentId,
    required String studentName,
    required String unitTitle,
  }) {
    if (studentId.isEmpty) return 'Student ID is required';
    if (studentName.isEmpty) return 'Student name is required';
    if (unitTitle.isEmpty) return 'Unit title is required';
    return null;
  }

  static Map<String, dynamic> buildNotificationData({
    required String parentId,
    required String studentId,
    required String studentName,
    required String unitTitle,
  }) {
    return {
      'userId': parentId,
      'type': 'quiz_report',
      'title': 'New Report Available',
      'message': '$studentName completed "$unitTitle" - Tap to view details',
      'isRead': false,
      'createdAt': DateTime.now().toIso8601String(),
      'data': {
        'studentId': studentId,
        'studentName': studentName,
        'unitTitle': unitTitle,
      },
    };
  }

  static String getNotificationBody(String studentName, String unitTitle) {
    return '$studentName completed "$unitTitle" - Tap to view details';
  }
}

void main() {
  group('Notification Service Logic', () {
    
    test('Should return error when parentId is null', () {
      // ARRANGE
      const String? parentId = null;
      const expectedError = 'Parent ID not found';
      
      // ACT
      final result = NotificationValidator.validateParentId(parentId);
      
      // ASSERT
      expect(result, expectedError);
    });

    test('Should return error when parentId is empty', () {
      // ARRANGE
      const parentId = '';
      const expectedError = 'Parent ID not found';
      
      // ACT
      final result = NotificationValidator.validateParentId(parentId);
      
      // ASSERT
      expect(result, expectedError);
    });

    test('Should return null when parentId is valid', () {
      // ARRANGE
      const parentId = 'parent123';
      
      // ACT
      final result = NotificationValidator.validateParentId(parentId);
      
      // ASSERT
      expect(result, isNull);
    });

    test('Should return error when studentId is empty', () {
      // ARRANGE
      const studentId = '';
      const studentName = 'Laura';
      const unitTitle = 'Animals';
      const expectedError = 'Student ID is required';
      
      // ACT
      final result = NotificationValidator.validateNotificationData(
        studentId: studentId,
        studentName: studentName,
        unitTitle: unitTitle,
      );
      
      // ASSERT
      expect(result, expectedError);
    });

    test('Should return error when studentName is empty', () {
      // ARRANGE
      const studentId = 's123';
      const studentName = '';
      const unitTitle = 'Animals';
      const expectedError = 'Student name is required';
      
      // ACT
      final result = NotificationValidator.validateNotificationData(
        studentId: studentId,
        studentName: studentName,
        unitTitle: unitTitle,
      );
      
      // ASSERT
      expect(result, expectedError);
    });

    test('Should return null when all notification data is valid', () {
      // ARRANGE
      const studentId = 's123';
      const studentName = 'Laura';
      const unitTitle = 'Animals';
      
      // ACT
      final result = NotificationValidator.validateNotificationData(
        studentId: studentId,
        studentName: studentName,
        unitTitle: unitTitle,
      );
      
      // ASSERT
      expect(result, isNull);
    });

    test('Should build correct notification data structure', () {
      // ARRANGE
      const parentId = 'p123';
      const studentId = 's123';
      const studentName = 'Laura';
      const unitTitle = 'Animals';
      
      // ACT
      final data = NotificationValidator.buildNotificationData(
        parentId: parentId,
        studentId: studentId,
        studentName: studentName,
        unitTitle: unitTitle,
      );
      
      // ASSERT
      expect(data['userId'], parentId);
      expect(data['type'], 'quiz_report');
      expect(data['title'], 'New Report Available');
      expect(data['isRead'], false);
      expect(data['data']['studentName'], studentName);
      expect(data['data']['unitTitle'], unitTitle);
    });
  });
}