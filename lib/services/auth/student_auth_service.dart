import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudentAuthService {
  static const String _keyStudentId = 'student_id';
  static const String _keyStudentName = 'student_name';
  static const String _keyStudentAvatar = 'student_avatar';
  static const String _keyAccessCode = 'access_code';

  /// Save student login info
  static Future<void> saveStudentLogin({
    required String studentId,
    required String studentName,
    required String? studentAvatar,
    required String accessCode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStudentId, studentId);
    await prefs.setString(_keyStudentName, studentName);
    await prefs.setString(_keyStudentAvatar, studentAvatar ?? '');
    await prefs.setString(_keyAccessCode, accessCode);
  }

  /// Get stored student login info
  static Future<Map<String, String>?> getStoredStudentLogin() async {
    final prefs = await SharedPreferences.getInstance();
    
    final studentId = prefs.getString(_keyStudentId);
    if (studentId == null) return null;
    
    return {
      'studentId': studentId,
      'studentName': prefs.getString(_keyStudentName) ?? '',
      'studentAvatar': prefs.getString(_keyStudentAvatar) ?? '',
      'accessCode': prefs.getString(_keyAccessCode) ?? '',
    };
  }

  /// Clear student login
  static Future<void> clearStudentLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyStudentId);
    await prefs.remove(_keyStudentName);
    await prefs.remove(_keyStudentAvatar);
    await prefs.remove(_keyAccessCode);
  }

  /// Check if student is logged in
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_keyStudentId);
  }

  // ========== ADD THESE METHODS ==========

  /// Alias for isLoggedIn() - used by splash screen
  static Future<bool> isStudentLoggedIn() async {
    return isLoggedIn();
  }

  /// Get student data as a map with typed values
  static Future<Map<String, dynamic>> getStudentData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'studentId': prefs.getString(_keyStudentId) ?? '',
      'studentName': prefs.getString(_keyStudentName) ?? '',
      'studentAvatar': prefs.getString(_keyStudentAvatar) ?? '',
      'accessCode': prefs.getString(_keyAccessCode) ?? '',
    };
  }

  static Future<void> updateStudentAvatar({
    required String studentId,
    required String newAvatar,
  }) async {
    try {
      // 1. update avatar
      await FirebaseFirestore.instance
        .collection('students')
        .doc(studentId)
        .update({
          'avatar': newAvatar,
        });
      
      // 2. update shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyStudentAvatar, newAvatar);
    } catch (e) {
      print('Error updating avatar: $e');
      rethrow;
    }
  }

  static Future<String> getStoredAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyStudentAvatar) ?? 'assets/avatars/panda.png';
  }

  static Future<String?> getStudentId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyStudentAvatar);
  }
}