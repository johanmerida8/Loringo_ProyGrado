// test/parent/notification_logic_test.dart
import 'package:flutter_test/flutter_test.dart';

class NotificationHelper {
  static int getUnreadCount(List<Map<String, dynamic>> notifications) {
    return notifications.where((n) => n['isRead'] == false).length;
  }

  static String formatTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inDays > 0) return '${difference.inDays}d ago';
    if (difference.inHours > 0) return '${difference.inHours}h ago';
    if (difference.inMinutes > 0) return '${difference.inMinutes}m ago';
    return 'Just now';
  }

  static String getNotificationIcon(String type) {
    switch (type) {
      case 'group_invitation':
        return 'group_add';
      case 'quiz_report':
        return 'quiz';
      default:
        return 'notifications';
    }
  }

  static String getNotificationTitle(String type) {
    switch (type) {
      case 'group_invitation':
        return 'Group Invitation';
      case 'quiz_report':
        return 'New Report Available';
      default:
        return 'Notification';
    }
  }
}

void main() {
  group('Notification Logic - AAA Pattern', () {

    test('ARRANGE-ACT-ASSERT: Unread count calculation', () {
      // ARRANGE
      final notifications = [
        {'isRead': false},
        {'isRead': true},
        {'isRead': false},
      ];

      // ACT
      final unreadCount = NotificationHelper.getUnreadCount(notifications);

      // ASSERT
      expect(unreadCount, 2);
    });

    test('ARRANGE-ACT-ASSERT: Empty notifications return 0 unread', () {
      // ARRANGE
      const List<Map<String, dynamic>> emptyNotifications = [];

      // ACT
      final unreadCount = NotificationHelper.getUnreadCount(emptyNotifications);

      // ASSERT
      expect(unreadCount, 0);
    });

    test('ARRANGE-ACT-ASSERT: Time ago - Just now', () {
      // ARRANGE
      final now = DateTime.now();

      // ACT
      final timeAgo = NotificationHelper.formatTimeAgo(now);

      // ASSERT
      expect(timeAgo, 'Just now');
    });

    test('ARRANGE-ACT-ASSERT: Time ago - Minutes ago', () {
      // ARRANGE
      final minutesAgo = DateTime.now().subtract(const Duration(minutes: 5));

      // ACT
      final timeAgo = NotificationHelper.formatTimeAgo(minutesAgo);

      // ASSERT
      expect(timeAgo, '5m ago');
    });

    test('ARRANGE-ACT-ASSERT: Time ago - Hours ago', () {
      // ARRANGE
      final hoursAgo = DateTime.now().subtract(const Duration(hours: 3));

      // ACT
      final timeAgo = NotificationHelper.formatTimeAgo(hoursAgo);

      // ASSERT
      expect(timeAgo, '3h ago');
    });

    test('ARRANGE-ACT-ASSERT: Time ago - Days ago', () {
      // ARRANGE
      final daysAgo = DateTime.now().subtract(const Duration(days: 2));

      // ACT
      final timeAgo = NotificationHelper.formatTimeAgo(daysAgo);

      // ASSERT
      expect(timeAgo, '2d ago');
    });

    test('ARRANGE-ACT-ASSERT: Notification icon for group invitation', () {
      // ARRANGE
      const String type = 'group_invitation';

      // ACT
      final icon = NotificationHelper.getNotificationIcon(type);

      // ASSERT
      expect(icon, 'group_add');
    });

    test('ARRANGE-ACT-ASSERT: Notification icon for quiz report', () {
      // ARRANGE
      const String type = 'quiz_report';

      // ACT
      final icon = NotificationHelper.getNotificationIcon(type);

      // ASSERT
      expect(icon, 'quiz');
    });

    test('ARRANGE-ACT-ASSERT: Notification icon for unknown type', () {
      // ARRANGE
      const String type = 'unknown';

      // ACT
      final icon = NotificationHelper.getNotificationIcon(type);

      // ASSERT
      expect(icon, 'notifications');
    });
  });
}