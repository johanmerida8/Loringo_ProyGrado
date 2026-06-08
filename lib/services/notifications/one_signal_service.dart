// lib/services/notification/onesignal_service.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
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
        
        debugPrint('✅ OneSignal initialized for user: $userId');
      }
    } catch (e) {
      debugPrint('❌ Error initializing OneSignal: $e');
    }
  }

  // Remove user on logout
  static Future<void> removeUser() async {
    if (kIsWeb) return;
    
    try {
      await OneSignal.logout();
      debugPrint('✅ OneSignal user removed');
    } catch (e) {
      debugPrint('❌ Error removing OneSignal user: $e');
    }
  }

  // Send notification using Edge Function
  static Future<void> sendNotification({
    required String userId,
    required String title,
    required String message,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("https://woltjhrvnompchyccqiy.supabase.co/functions/v1/send-notifications"),
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "userId": userId,
          "title": title,
          "body": message,
        }),
      );
      
      if (response.statusCode == 200) {
        debugPrint('✅ Notification sent to user: $userId');
      } else {
        debugPrint('❌ Failed to send notification: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Error sending notification: $e');
    }
  }
}