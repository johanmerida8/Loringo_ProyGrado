// lib/services/otp_service.dart
// ignore_for_file: constant_identifier_names

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class OTPService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // Rate limiting configuration
  static const int RESEND_COOLDOWN_SECONDS = 30;
  static const int RESET_COOLDOWN_MINUTES = 15;
  static const int MAX_DAILY_RESETS = 3;

  /// Send OTP to user's email using the Firebase Cloud Function `sendOtpEmail`.
  Future<bool> sendOTPToEmail(String email) async {
    try {
      debugPrint('Sending OTP to: $email');

      final canSend = await canRequestOTP(email);
      if (!canSend['canSend']) {
        throw Exception(canSend['message']);
      }

      final emailExists = await _checkEmailInFirestore(email);
      if (!emailExists) {
        throw Exception('Email is not registered');
      }

      final callable = _functions.httpsCallable('sendOtpEmail');
      final result = await callable.call({'email': email});

      if (result.data['success'] == true) {
        await _logPasswordResetAttempt(email);
        debugPrint('OTP sent successfully to $email');
        return true;
      } else {
        throw Exception('Failed to send OTP');
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint('sendOtpEmail failed: ${e.code} - ${e.message}');
      throw Exception(_mapFunctionError(e));
    } catch (e) {
      debugPrint('Error sending OTP: $e');
      rethrow;
    }
  }

  /// Verify OTP via the Firebase Cloud Function `verifyOtp`.
  Future<bool> verifyOTP(String email, String otpCode) async {
    try {
      debugPrint('Verifying OTP for: $email');

      final callable = _functions.httpsCallable('verifyOtp');
      final result = await callable.call({
        'email': email.toLowerCase().trim(),
        'otp': otpCode,
      });

      final success = result.data['success'] == true;
      debugPrint(success ? 'OTP verified successfully' : 'OTP verification failed');
      return success;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('verifyOtp failed: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Error verifying OTP: $e');
      return false;
    }
  }

  /// Check if user can resend OTP (short cooldown for OTPScreen)
  Future<Map<String, dynamic>> canResendOTP(String email) async {
    try {
      final normalizedEmail = email.toLowerCase().trim();

      final lastAttemptQuery = await _firestore
          .collection('password_reset_logs')
          .where('email', isEqualTo: normalizedEmail)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (lastAttemptQuery.docs.isNotEmpty) {
        final lastAttempt = lastAttemptQuery.docs.first;
        final lastTime = (lastAttempt.data()['timestamp'] as Timestamp).toDate();
        final diffSeconds = DateTime.now().difference(lastTime).inSeconds;

        if (diffSeconds < RESEND_COOLDOWN_SECONDS) {
          final remaining = RESEND_COOLDOWN_SECONDS - diffSeconds;
          return {
            'canSend': false,
            'message': 'Please wait $remaining seconds before resending the code',
            'reason': 'resend_cooldown',
            'remainingSeconds': remaining,
          };
        }
      }

      return {'canSend': true, 'message': 'You can resend the code'};
    } catch (e) {
      debugPrint('Error checking resend cooldown: $e');
      return {'canSend': true, 'message': 'You can resend the code'};
    }
  }

  /// Check if user can request a new password reset (long cooldown)
  Future<Map<String, dynamic>> canRequestOTP(String email) async {
    return await _canRequestOTP(email);
  }

  /// Update password after OTP verification.
  ///
  /// IMPORTANT: this no longer uses FirebaseAuth.currentUser.updatePassword(),
  /// since the user is never signed in during the "forgot password" flow —
  /// there is no active session to update. Instead, this calls the
  /// `resetPassword` Cloud Function, which re-checks that the given OTP was
  /// actually verified (used == true in `otps`) and then uses the Admin SDK
  /// to set the new password server-side, without requiring a session.
  Future<void> updatePassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    try {
      debugPrint('Resetting password for: $email');

      final callable = _functions.httpsCallable('resetPassword');
      final result = await callable.call({
        'email': email.toLowerCase().trim(),
        'otp': otp,
        'newPassword': newPassword,
      });

      if (result.data['success'] != true) {
        throw Exception('Failed to reset password');
      }

      debugPrint('Password reset successfully for $email');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('resetPassword failed: ${e.code} - ${e.message}');
      throw Exception(_mapResetPasswordError(e));
    } catch (e) {
      debugPrint('Error resetting password: $e');
      throw Exception('Failed to reset password: $e');
    }
  }

  // ============================================================================
  // PRIVATE METHODS
  // ============================================================================

  String _mapFunctionError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'not-found':
        return 'No verification code was found for this email.';
      case 'deadline-exceeded':
        return 'This code has expired. Request a new one.';
      case 'resource-exhausted':
        return 'Too many attempts. Please request a new code.';
      case 'failed-precondition':
        return 'This code has already been used.';
      case 'invalid-argument':
        return 'Invalid or expired code.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  String _mapResetPasswordError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'failed-precondition':
        return 'Please verify your code again before resetting your password.';
      case 'not-found':
        return 'User not found. Please verify your email.';
      case 'invalid-argument':
        return e.message ?? 'Invalid request.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  Future<bool> _checkEmailInFirestore(String email) async {
    try {
      final userQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email.toLowerCase().trim())
          .limit(1)
          .get();

      return userQuery.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking email in Firestore: $e');
      return false;
    }
  }

  Future<void> _logPasswordResetAttempt(String email) async {
    try {
      await _firestore.collection('password_reset_logs').add({
        'email': email.toLowerCase().trim(),
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'password_reset',
        'status': 'sent',
      });

      await _cleanupOldLogs();
    } catch (e) {
      debugPrint('Error saving to password_reset_logs: $e');
    }
  }

  Future<void> _cleanupOldLogs() async {
    try {
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));

      final oldLogs = await _firestore
          .collection('password_reset_logs')
          .where('timestamp', isLessThan: Timestamp.fromDate(thirtyDaysAgo))
          .limit(100)
          .get();

      final batch = _firestore.batch();
      for (var doc in oldLogs.docs) {
        batch.delete(doc.reference);
      }

      if (oldLogs.docs.isNotEmpty) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Error cleaning up old logs: $e');
    }
  }

  Future<Map<String, dynamic>> _canRequestOTP(String email) async {
    try {
      final normalizedEmail = email.toLowerCase().trim();

      final lastAttemptQuery = await _firestore
          .collection('password_reset_logs')
          .where('email', isEqualTo: normalizedEmail)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (lastAttemptQuery.docs.isNotEmpty) {
        final lastAttempt = lastAttemptQuery.docs.first;
        final lastTime = (lastAttempt.data()['timestamp'] as Timestamp).toDate();
        final diffMinutes = DateTime.now().difference(lastTime).inMinutes;

        if (diffMinutes < RESET_COOLDOWN_MINUTES) {
          final remaining = RESET_COOLDOWN_MINUTES - diffMinutes;
          return {
            'canSend': false,
            'message': 'Please wait $remaining minutes before requesting another code',
            'reason': 'cooldown',
            'remainingMinutes': remaining,
            'attemptsToday': await _getTodayAttemptsCount(normalizedEmail),
            'maxDaily': MAX_DAILY_RESETS,
          };
        }
      }

      final todayAttempts = await _getTodayAttemptsCount(normalizedEmail);

      if (todayAttempts >= MAX_DAILY_RESETS) {
        return {
          'canSend': false,
          'message': 'You have reached the daily limit of $MAX_DAILY_RESETS attempts. Please try again tomorrow.',
          'reason': 'daily_limit',
          'attemptsToday': todayAttempts,
          'maxDaily': MAX_DAILY_RESETS,
        };
      }

      return {
        'canSend': true,
        'message': 'You can request a code',
        'attemptsToday': todayAttempts,
        'remainingAttempts': MAX_DAILY_RESETS - todayAttempts,
        'cooldownMinutes': RESET_COOLDOWN_MINUTES,
        'maxDaily': MAX_DAILY_RESETS,
      };
    } catch (e) {
      debugPrint('Error checking rate limiting: $e');
      return {
        'canSend': true,
        'message': 'You can request a code',
        'warning': 'Error checking limits: $e',
      };
    }
  }

  Future<int> _getTodayAttemptsCount(String email) async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59);

      final querySnapshot = await _firestore
          .collection('password_reset_logs')
          .where('email', isEqualTo: email)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .get();

      return querySnapshot.docs.length;
    } catch (e) {
      debugPrint('Error getting today\'s attempt count: $e');
      return 0;
    }
  }
}