import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';

class PasswordUtils {
  PasswordUtils._();

  // Compiled once to avoid recreating on every keystroke
  static final RegExp _hasUppercase = RegExp(r'[A-Z]');
  static final RegExp _hasLowercase = RegExp(r'[a-z]');
  static final RegExp _hasDigit = RegExp(r'[0-9]');
  static final RegExp _hasSpecial = RegExp(r'''[!@#$%^&*()_+\-=\[\]{};:"\\|,.<>\/?`~]''');

  // Core rules as individual booleans
  static bool _longEnough(String p) => p.length >= 8;
  static bool _hasUpper(String p) => _hasUppercase.hasMatch(p);
  static bool _hasLower(String p) => _hasLowercase.hasMatch(p);
  static bool _hasNum(String p) => _hasDigit.hasMatch(p);
  static bool _hasSpecialChar(String p) => _hasSpecial.hasMatch(p);

  /// Returns true only when ALL 5 rules pass
  static bool isPasswordValid(String password) {
    return _longEnough(password) &&
        _hasUpper(password) &&
        _hasLower(password) &&
        _hasNum(password) &&
        _hasSpecialChar(password);
  }

  /// 0–5 score (one point per rule satisfied)
  static int strengthScore(String password) {
    int score = 0;
    if (_longEnough(password)) score++;
    if (_hasUpper(password)) score++;
    if (_hasLower(password)) score++;
    if (_hasNum(password)) score++;
    if (_hasSpecialChar(password)) score++;
    return score;
  }

  /// Human-readable label matching the score
  static String getPasswordStrength(String password) {
    switch (strengthScore(password)) {
      case 0:
      case 1:
        return 'Very Weak';
      case 2:
        return 'Weak';
      case 3:
        return 'Fair';
      case 4:
        return 'Strong';
      case 5:
        return 'Very Strong';
      default:
        return 'Very Weak';
    }
  }

  /// Colour that corresponds to the strength level
  static Color getPasswordStrengthColor(String password) {
    switch (strengthScore(password)) {
      case 0:
      case 1:
        return AppColors.danger;
      case 2:
        return AppColors.warning;
      case 3:
        return const Color(0xFFE6C629);
      case 4:
        return AppColors.primaryLight;
      case 5:
        return AppColors.success;
      default:
        return AppColors.danger;
    }
  }

  /// Returns the list of rules that the password is still MISSING
  static List<String> getPasswordRequirements(String password) {
    final List<String> missing = [];
    if (!_longEnough(password)) missing.add('At least 8 characters');
    if (!_hasUpper(password)) missing.add('At least 1 uppercase letter (A-Z)');
    if (!_hasLower(password)) missing.add('At least 1 lowercase letter (a-z)');
    if (!_hasNum(password)) missing.add('At least 1 number (0-9)');
    if (!_hasSpecialChar(password)) {
      missing.add('At least 1 special character (!@#\$%^&*...)');
    }
    return missing;
  }
}