// lib/services/otp_service.dart
// ignore_for_file: constant_identifier_names

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:loringo_app/services/firebase_refs.dart';

class OTPService {
  final FirebaseFirestore _firestore = firestoreInstance;
  // Lazy (not a field initializer) so constructing OTPService in a test
  // that only exercises the Firestore-backed rate-limit methods
  // (canResendOTP/canRequestOTP) never touches FirebaseFunctions.instance
  // at all — Cloud Functions have no swappable indirection (out of scope
  // for this suite) and would otherwise throw "no Firebase App" the
  // moment an OTPService is constructed, even when unused.
  FirebaseFunctions get _functions => FirebaseFunctions.instance;

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
        // Stable, deliberately untranslated sentinel — matched by content
        // in ResetPasswordScreen._sendCode's catch block, which shows its
        // own translated replacement message instead of this raw text.
        throw Exception('Email is not registered');
      }

      final callable = _functions.httpsCallable('sendOtpEmail');
      final result = await callable.call({'email': email});

      if (result.data['success'] == true) {
        await _logPasswordResetAttempt(email);
        debugPrint('OTP sent successfully to $email');
        return true;
      } else {
        throw Exception('initials.otp_service.failedToSendOtp'.tr());
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
            'message': 'initials.otp_service.waitBeforeResend'
                .tr(namedArgs: {'seconds': '$remaining'}),
            'reason': 'resend_cooldown',
            'remainingSeconds': remaining,
          };
        }
      }

      return {'canSend': true, 'message': 'initials.otp_service.canResendCode'.tr()};
    } catch (e) {
      debugPrint('Error checking resend cooldown: $e');
      return {'canSend': true, 'message': 'initials.otp_service.canResendCode'.tr()};
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
        throw Exception('initials.otp_service.failedToResetPassword'.tr());
      }

      debugPrint('Password reset successfully for $email');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('resetPassword failed: ${e.code} - ${e.message}');
      throw Exception(_mapResetPasswordError(e));
    } catch (e) {
      debugPrint('Error resetting password: $e');
      throw Exception(
          'initials.otp_service.failedToResetPasswordWithError'.tr(namedArgs: {'error': '$e'}));
    }
  }

  // ============================================================================
  // PRIVATE METHODS
  // ============================================================================

  String _mapFunctionError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'not-found':
        return 'initials.otp_service.noCodeFound'.tr();
      case 'deadline-exceeded':
        return 'initials.otp_service.codeExpired'.tr();
      case 'resource-exhausted':
        return 'initials.otp_service.tooManyAttempts'.tr();
      case 'failed-precondition':
        return 'initials.otp_service.codeAlreadyUsed'.tr();
      case 'invalid-argument':
        return 'initials.otp_service.invalidOrExpiredCode'.tr();
      default:
        return 'initials.otp_service.somethingWentWrong'.tr();
    }
  }

  String _mapResetPasswordError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'failed-precondition':
        return 'initials.otp_service.verifyCodeAgain'.tr();
      case 'not-found':
        return 'initials.otp_service.userNotFoundVerifyEmail'.tr();
      case 'invalid-argument':
        return e.message ?? 'initials.otp_service.invalidRequest'.tr();
      default:
        return 'initials.otp_service.somethingWentWrong'.tr();
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
            'message': 'initials.otp_service.waitBeforeAnotherCode'
                .tr(namedArgs: {'minutes': '$remaining'}),
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
          'message': 'initials.otp_service.dailyLimitReached'
              .tr(namedArgs: {'max': '$MAX_DAILY_RESETS'}),
          'reason': 'daily_limit',
          'attemptsToday': todayAttempts,
          'maxDaily': MAX_DAILY_RESETS,
        };
      }

      return {
        'canSend': true,
        'message': 'initials.otp_service.canRequestCode'.tr(),
        'attemptsToday': todayAttempts,
        'remainingAttempts': MAX_DAILY_RESETS - todayAttempts,
        'cooldownMinutes': RESET_COOLDOWN_MINUTES,
        'maxDaily': MAX_DAILY_RESETS,
      };
    } catch (e) {
      debugPrint('Error checking rate limiting: $e');
      return {
        'canSend': true,
        'message': 'initials.otp_service.canRequestCode'.tr(),
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