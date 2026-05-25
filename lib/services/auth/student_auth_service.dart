import 'package:shared_preferences/shared_preferences.dart';

/// Student Authentication Service
/// Manages student login state locally (no Firebase Auth)
class StudentAuthService {
  static const String _keyIsLoggedIn = 'student_is_logged_in';
  static const String _keyStudentId = 'student_id';
  static const String _keyStudentName = 'student_name';
  static const String _keyStudentAvatar = 'student_avatar';

  /// Save student login state
  static Future<void> saveStudentLogin({
    required String studentId,
    required String studentName,
    String? studentAvatar,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, true);
    await prefs.setString(_keyStudentId, studentId);
    await prefs.setString(_keyStudentName, studentName);
    if (studentAvatar != null) {
      await prefs.setString(_keyStudentAvatar, studentAvatar);
    }
  }

  /// Check if student is logged in
  static Future<bool> isStudentLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsLoggedIn) ?? false;
  }

  /// Get student data
  static Future<Map<String, String?>> getStudentData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'studentId': prefs.getString(_keyStudentId),
      'studentName': prefs.getString(_keyStudentName),
      'studentAvatar': prefs.getString(_keyStudentAvatar),
    };
  }

  /// Clear student login state (logout)
  static Future<void> clearStudentLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIsLoggedIn);
    await prefs.remove(_keyStudentId);
    await prefs.remove(_keyStudentName);
    await prefs.remove(_keyStudentAvatar);
  }
}
