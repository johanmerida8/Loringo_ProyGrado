// lib/services/notification/onesignal_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter/foundation.dart';

class OneSignalNotificationService {
  // Set external user ID after login (simplified)
  static Future<void> initializeUser(String userId) async {
    if (kIsWeb) return;

    try {
      // Just set external user ID - no tags
      await OneSignal.login(userId);

      // Store player ID in Firestore
      final playerId = OneSignal.User.pushSubscription.id;
      if (playerId != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .set({
              'oneSignalPlayerId': playerId,
            }, SetOptions(merge: true));

        debugPrint('OneSignal initialized for user: $userId');
      }
    } catch (e) {
      debugPrint('Error initializing OneSignal: $e');
    }
  }

  // Remove user on logout
  static Future<void> removeUser() async {
    if (kIsWeb) return;

    try {
      await OneSignal.logout();
      debugPrint('OneSignal user removed');
    } catch (e) {
      debugPrint('Error removing OneSignal user: $e');
    }
  }

  // Send notification using the Cloud Function `sendNotification`
  static Future<void> sendNotification({
    required String userId,
    required String title,
    required String message,
  }) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('sendNotification');
      final result = await callable.call({
        'userId': userId,
        'title': title,
        'body': message,
      });

      if (result.data['success'] == true) {
        debugPrint('Notification sent to user: $userId');
      } else {
        debugPrint('Failed to send notification: ${result.data}');
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint('sendNotification failed: ${e.code} - ${e.message}');
    } catch (e) {
      debugPrint('Error sending notification: $e');
    }
  }
}