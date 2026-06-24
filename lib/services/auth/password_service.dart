// lib/services/auth/password_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class PasswordService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // configuration
  static const int RESET_COOLDOWN_MINUTES = 15;
  static const int MAX_DAILY_RESETS = 3;

  // Get user ID from email (helper method)
  static Future<String?> _getUserIdFromEmail(String email) async {
    try {
      // Query users collection to find user by email
      final userQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email.toLowerCase().trim())
          .limit(1)
          .get();
      
      if (userQuery.docs.isNotEmpty) {
        return userQuery.docs.first.id;
      }
      return null;
    } catch (e) {
      debugPrint('Error finding user by email: $e');
      return null;
    }
  }

  // Check if user can request a password reset
  static Future<Map<String, dynamic>> canRequestPasswordReset(String email) async {
    try {
      final normalizedEmail = email.toLowerCase().trim();
      
      // Get user ID first
      final userId = await _getUserIdFromEmail(normalizedEmail);
      if (userId == null) {
        return {
          'canReset': false,
          'reason': 'user_not_found',
          'message': 'No account found with this email.',
        };
      }

      // Reference to password_resets subcollection inside the user document
      final userResetsRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('password_resets');
      
      // 1. Check last reset attempt (cooldown)
      final lastAttemptSnapshot = await userResetsRef
          .orderBy('requestedAt', descending: true)
          .limit(1)
          .get();

      if (lastAttemptSnapshot.docs.isNotEmpty) {
        final lastAttempt = lastAttemptSnapshot.docs.first.data();
        final lastResetTime = (lastAttempt['requestedAt'] as Timestamp).toDate();
        final timeDifference = DateTime.now().difference(lastResetTime);

        if (timeDifference.inMinutes < RESET_COOLDOWN_MINUTES) {
          final remainingMinutes = RESET_COOLDOWN_MINUTES - timeDifference.inMinutes;
          return {
            'canReset': false,
            'reason': 'cooldown',
            'remainingMinutes': remainingMinutes,
            'message': 'Please wait $remainingMinutes minutes before trying again.',
          };
        }
      }

      // 2. Check daily limit
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      final todayAttemptsSnapshot = await userResetsRef
          .where('requestedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .get();

      if (todayAttemptsSnapshot.docs.length >= MAX_DAILY_RESETS) {
        return {
          'canReset': false,
          'reason': 'daily_limit',
          'attempts': todayAttemptsSnapshot.docs.length,
          'message': 'You have reached the daily limit of $MAX_DAILY_RESETS attempts. Please try again tomorrow.'
        };
      }

      return {
        'canReset': true,
        'attemptsToday': todayAttemptsSnapshot.docs.length,
        'message': 'You can request a password reset',
      };
    } catch (e) {
      debugPrint('Error checking password reset eligibility: $e');
      return {
        'canReset': true, // Allow on error (fail open)
        'reason': 'error',
        'message': 'Unable to verify limits. Please try again.',
      };
    }
  }

  // Log a password reset attempt
  static Future<void> logPasswordResetAttempt(String email) async {
    try {
      final normalizedEmail = email.toLowerCase().trim();
      
      // Get user ID
      final userId = await _getUserIdFromEmail(normalizedEmail);
      if (userId == null) return;

      // Store inside user's subcollection
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('password_resets')
          .add({
            'email': normalizedEmail,
            'requestedAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('Error logging password reset attempt: $e');
    }
  }

  // Send password reset email with rate limit
  static Future<void> sendPasswordResetEmail(String email) async {
    // First check if user can request
    final eligibility = await canRequestPasswordReset(email);
    
    if (eligibility['canReset'] != true) {
      throw Exception(eligibility['message'] ?? 'Cannot request password reset at this time');
    }
    
    // Send the email
    await _auth.sendPasswordResetEmail(email: email);
    
    // Log the attempt
    await logPasswordResetAttempt(email);
  }

  // Update user's password (when logged in)
  static Future<void> updatePassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user logged in');
    await user.updatePassword(newPassword);
  }

  // Get error message from FirebaseAuthException
  static String getErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email';
      case 'invalid-email':
        return 'Invalid email address';
      case 'too-many-requests':
        return 'Too many requests. Try again later';
      default:
        return 'Error: ${e.message}';
    }
  }
}