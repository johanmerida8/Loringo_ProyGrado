// lib/services/otp_service.dart
// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:http/http.dart' as http;

class OTPService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Only one URL (no longer need verify-otp)
  static const String _sendOtpFunctionUrl = 'https://woltjhrvnompchyccqiy.supabase.co/functions/v1/send-otp-email';
  
  // Rate limiting configuration
  static const int RESEND_COOLDOWN_SECONDS = 30; // 30 seconds between resends (for OTPScreen)
  static const int RESET_COOLDOWN_MINUTES = 15; // 15 minutes between reset attempts (for ResetPasswordScreen)
  static const int MAX_DAILY_RESETS = 3; // Maximum 3 attempts per day

  /// Send OTP to user's email using Edge Function
  Future<bool> sendOTPToEmail(String email) async {
    try {
      debugPrint('Sending OTP to: $email');
      
      // Check rate limiting first (15 minute cooldown + daily limit)
      final canSend = await canRequestOTP(email);
      if (!canSend['canSend']) {
        throw Exception(canSend['message']);
      }
      
      // Check if email exists in Firestore (collection 'users')
      final emailExists = await _checkEmailInFirestore(email);
      if (!emailExists) {
        throw Exception('Email is not registered');
      }
      
      // Call Edge Function to send OTP
      final response = await http.post(
        Uri.parse(_sendOtpFunctionUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // Save OTP to Firestore (comes from Edge Function)
          final otp = data['otp'];
          
          // Mark old OTPs as used
          final oldOtps = await _firestore
              .collection('otps')
              .where('email', isEqualTo: email.toLowerCase().trim())
              .where('used', isEqualTo: false)
              .get();
          
          for (var doc in oldOtps.docs) {
            await doc.reference.update({'used': true});
          }
          
          // Save new OTP
          await _firestore.collection('otps').add({
            'email': email.toLowerCase().trim(),
            'otp': otp,
            'expiresAt': DateTime.now().add(const Duration(minutes: 15)),
            'used': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
          
          // Log the attempt in Firestore
          await _logPasswordResetAttempt(email);
          debugPrint('OTP sent successfully to $email');
          return true;
        } else {
          throw Exception(data['error'] ?? 'Failed to send OTP');
        }
      } else {
        final error = jsonDecode(response.body);  
        throw Exception(error['error'] ?? 'Failed to send OTP');
      }
      
    } catch (e) {
      debugPrint('Error sending OTP: $e');
      rethrow;
    }
  }

  /// Verify OTP directly from Firestore (without Edge Function)
  Future<bool> verifyOTP(String email, String otpCode) async {
    try {
      debugPrint('Verifying OTP for: $email');
      debugPrint('Entered code: $otpCode');
      
      // Search for valid OTP in Firestore
      final snapshot = await _firestore
          .collection('otps')
          .where('email', isEqualTo: email.toLowerCase().trim())
          .where('otp', isEqualTo: otpCode)
          .where('used', isEqualTo: false)
          .where('expiresAt', isGreaterThan: DateTime.now())
          .limit(1)
          .get();
      
      if (snapshot.docs.isNotEmpty) {
        // Mark OTP as used
        await snapshot.docs.first.reference.update({'used': true});
        debugPrint('OTP verified successfully');
        return true;
      } else {
        debugPrint('Invalid or expired OTP code');
        return false;
      }
      
    } catch (e) {
      debugPrint('Error verifying OTP: $e');
      return false;
    }
  }

  /// Check if user can resend OTP (short cooldown for OTPScreen)
  Future<Map<String, dynamic>> canResendOTP(String email) async {
    try {
      final normalizedEmail = email.toLowerCase().trim();
      
      // Check 30 second cooldown between resends
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
        
        debugPrint('Last resend attempt: $diffSeconds seconds ago');
        
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
      
      return {
        'canSend': true,
        'message': 'You can resend the code',
      };
      
    } catch (e) {
      debugPrint('Error checking resend cooldown: $e');
      return {
        'canSend': true,
        'message': 'You can resend the code',
      };
    }
  }

  /// Check if user can request a new password reset (long cooldown for ResetPasswordScreen)
  Future<Map<String, dynamic>> canRequestOTP(String email) async {
    return await _canRequestOTP(email);
  }
  
  /// Clean any active Supabase session
  Future<void> cleanupSession() async {
    try {
      final session = _supabase.auth.currentSession;
      if (session != null) {
        await _supabase.auth.signOut();
        debugPrint('Supabase session cleaned');
      }
    } catch (e) {
      debugPrint('Error cleaning session: $e');
    }
  }

  /// Update password in Firebase Auth after OTP verification
  Future<void> updatePassword(String newPassword, {bool updateFirestore = false}) async {
    try {
      debugPrint('Updating password in Firebase Auth for user');
      
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      
      if (firebaseUser == null) {
        throw Exception('User not authenticated in Firebase. Please log in again.');
      }
      
      final userEmail = firebaseUser.email;
      debugPrint('Updating password for: $userEmail');
      
      await firebaseUser.updatePassword(newPassword);
      debugPrint('Password updated successfully in Firebase Auth');
      
      if (updateFirestore && userEmail != null) {
        await _firestore.collection('users').doc(userEmail).update({
          'password_updated_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        });
        debugPrint('Firestore updated with password change timestamp');
      }
      
      await firebase_auth.FirebaseAuth.instance.signOut();
      debugPrint('User signed out from Firebase after password update');
      
      await cleanupSession();
      
    } catch (e) {
      debugPrint('Error updating password in Firebase: $e');
      
      if (e is firebase_auth.FirebaseAuthException) {
        switch (e.code) {
          case 'requires-recent-login':
            throw Exception('Session has expired. Please request a new code.');
          case 'weak-password':
            throw Exception('Password is too weak. Please use a stronger password.');
          case 'user-not-found':
            throw Exception('User not found. Please verify your email.');
          default:
            throw Exception('Error updating password: ${e.message}');
        }
      }
      
      throw Exception('Failed to update password: $e');
    }
  }

  // ============================================================================
  // PRIVATE METHODS - Firestore Integration
  // ============================================================================
  
  Future<bool> _checkEmailInFirestore(String email) async {
    try {
      debugPrint('Checking email in Firestore: $email');
      
      final userQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email.toLowerCase().trim())
          .limit(1)
          .get();
      
      final exists = userQuery.docs.isNotEmpty;
      
      if (exists) {
        debugPrint('Email found in Firestore');
      } else {
        debugPrint('Email NOT found in Firestore');
      }
      
      return exists;
      
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
      
      debugPrint('Password reset attempt logged in password_reset_logs for: $email');
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
        debugPrint('Cleaned up ${oldLogs.docs.length} old logs');
      }
      
    } catch (e) {
      debugPrint('Error cleaning up old logs: $e');
    }
  }
  
  Future<Map<String, dynamic>> _canRequestOTP(String email) async {
    try {
      final normalizedEmail = email.toLowerCase().trim();
      
      // 1. Check 15 minute cooldown
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
        
        debugPrint('Last reset attempt: $diffMinutes minutes ago');
        
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
      
      // 2. Check daily limit of 3 attempts
      final todayAttempts = await _getTodayAttemptsCount(normalizedEmail);
      
      debugPrint('Today\'s reset attempts: $todayAttempts of $MAX_DAILY_RESETS');
      
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