// lib/services/auth/logout_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/services/auth/login_or_register.dart';
import 'package:loringo_app/services/auth/student_auth_service.dart';

class LogoutService {
  /// Logout for regular users (admin, teacher, parent)
  static Future<void> logoutUser(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginOrRegister()),
        (route) => false,
      );
    }
  }

  /// Logout for student users
  static Future<void> logoutStudent(BuildContext context) async {
    await StudentAuthService.clearStudentLogin();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginOrRegister()),
        (route) => false,
      );
    }
  }

  /// Show logout confirmation dialog
  static Future<bool> showLogoutConfirmation(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Log Out'),
          ),
        ],
      ),
    ).then((value) => value ?? false);
  }
}