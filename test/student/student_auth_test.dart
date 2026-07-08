// test/student/student_auth_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:loringo_app/services/auth/student_auth_service.dart';

void main() {
  group('Student Auth Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });
    
    test('Save and retrieve student login', () async {
      // ARRANGE
      const studentId = 'std_123';
      const studentName = 'John';
      const accessCode = 'CODE456';
      
      // ACT
      await StudentAuthService.saveStudentLogin(
        studentId: studentId,
        studentName: studentName,
        studentAvatar: null,
        accessCode: accessCode,
      );
      
      final result = await StudentAuthService.getStoredStudentLogin();
      
      // ASSERT
      expect(result?['studentId'], 'std_123');
      expect(result?['studentName'], 'John');
      expect(result?['accessCode'], 'CODE456');
    });
    
    test('Check if logged in returns true after save', () async {
      // ARRANGE
      await StudentAuthService.saveStudentLogin(
        studentId: 'std_123',
        studentName: 'John',
        studentAvatar: null,
        accessCode: 'CODE456',
      );
      
      // ACT
      final isLoggedIn = await StudentAuthService.isLoggedIn();
      
      // ASSERT
      expect(isLoggedIn, true);
    });
    
    test('Check if logged in returns false when no data', () async {
      // ACT
      final isLoggedIn = await StudentAuthService.isLoggedIn();
      
      // ASSERT
      expect(isLoggedIn, false);
    });
    
    test('Clear login removes all data', () async {
      // ARRANGE
      await StudentAuthService.saveStudentLogin(
        studentId: 'std_123',
        studentName: 'John',
        studentAvatar: null,
        accessCode: 'CODE456',
      );
      
      // ACT
      await StudentAuthService.clearStudentLogin();
      final result = await StudentAuthService.getStoredStudentLogin();
      
      // ASSERT
      expect(result, null);
    });
    
    test('Get student data returns empty strings when not logged in', () async {
      // ACT
      final data = await StudentAuthService.getStudentData();
      
      // ASSERT
      expect(data['studentId'], '');
      expect(data['studentName'], '');
      expect(data['studentAvatar'], '');
      expect(data['accessCode'], '');
    });
  });
}