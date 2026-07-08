// lib/services/notification/notification_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
// import 'package:loringo_app/services/notification/onesignal_notification_service.dart';
import 'package:loringo_app/services/notifications/one_signal_service.dart';

class NotificationService {
  // Send report notification to parent using OneSignal
  static Future<void> sendReportNotification({
    required String studentId,
    required String studentName,
    required String unitTitle,
  }) async {
    try {
      // Get parent ID from student document
      final studentDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(studentId)
          .get();
      
      final parentId = studentDoc.data()?['parentId'] as String?;
      
      if (parentId == null || parentId.isEmpty) {
        debugPrint('[NotificationService] Parent ID not found for student: $studentId');
        return;
      }
      
      // Save to Firestore (for notification history)
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': parentId,
        'type': 'quiz_report',
        'title': 'New Report Available',
        'message': '$studentName completed "$unitTitle" - Tap to view details',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'data': {
          'studentId': studentId,
          'studentName': studentName,
          'unitTitle': unitTitle,
        },
      });
      
      debugPrint('[NotificationService] Notification saved to Firestore for parent: $parentId');
      
      // Send push notification via OneSignal
      await OneSignalNotificationService.sendNotification(
        userId: parentId,  // ← This is the external user ID
        title: 'New Report Available',
        message: '$studentName completed "$unitTitle" - Tap to view details',
      );
      
      debugPrint('[NotificationService] Notification sent to parent: $parentId');
    } catch (e) {
      debugPrint('[NotificationService] Error: $e');
    }
  }
}