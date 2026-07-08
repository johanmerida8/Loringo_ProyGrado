// test/notification/notification_storage_test.dart
import 'package:flutter_test/flutter_test.dart';

class NotificationStorage {
  static const int MAX_NOTIFICATIONS = 100;
  
  static List<Map<String, dynamic>> filterByType(
    List<Map<String, dynamic>> notifications, 
    String type
  ) {
    return notifications.where((n) => n['type'] == type).toList();
  }

  static List<Map<String, dynamic>> getUnread(
    List<Map<String, dynamic>> notifications
  ) {
    return notifications.where((n) => n['isRead'] == false).toList();
  }

  static int getUnreadCount(List<Map<String, dynamic>> notifications) {
    return notifications.where((n) => n['isRead'] == false).length;
  }

  static List<Map<String, dynamic>> markAllAsRead(
    List<Map<String, dynamic>> notifications
  ) {
    return notifications.map((n) => {...n, 'isRead': true}).toList();
  }

  static List<Map<String, dynamic>> sortByDate(
    List<Map<String, dynamic>> notifications
  ) {
    return List.from(notifications)..sort((a, b) {
      final aDate = DateTime.parse(a['createdAt'] as String);
      final bDate = DateTime.parse(b['createdAt'] as String);
      return bDate.compareTo(aDate);
    });
  }

  static bool isWithinLimit(int currentCount) {
    return currentCount < MAX_NOTIFICATIONS;
  }
}

void main() {
  group('Notification Storage Logic', () {
    
    final notifications = [
      {'type': 'quiz_report', 'isRead': false, 'createdAt': '2024-01-15T10:00:00'},
      {'type': 'group_invitation', 'isRead': true, 'createdAt': '2024-01-14T10:00:00'},
      {'type': 'quiz_report', 'isRead': false, 'createdAt': '2024-01-13T10:00:00'},
    ];

    test('Should filter notifications by type - quiz_report', () {
      // ARRANGE
      const filterType = 'quiz_report';
      final expectedCount = 2;
      
      // ACT
      final filtered = NotificationStorage.filterByType(notifications, filterType);
      
      // ASSERT
      expect(filtered.length, expectedCount);
      expect(filtered.every((n) => n['type'] == filterType), true);
    });

    test('Should filter notifications by type - group_invitation', () {
      // ARRANGE
      const filterType = 'group_invitation';
      final expectedCount = 1;
      
      // ACT
      final filtered = NotificationStorage.filterByType(notifications, filterType);
      
      // ASSERT
      expect(filtered.length, expectedCount);
      expect(filtered.first['type'], filterType);
    });

    test('Should return only unread notifications', () {
      // ARRANGE
      final expectedUnreadCount = 2;
      
      // ACT
      final unread = NotificationStorage.getUnread(notifications);
      
      // ASSERT
      expect(unread.length, expectedUnreadCount);
      expect(unread.every((n) => n['isRead'] == false), true);
    });

    test('Should return correct unread count', () {
      // ARRANGE
      final expectedCount = 2;
      
      // ACT
      final count = NotificationStorage.getUnreadCount(notifications);
      
      // ASSERT
      expect(count, expectedCount);
    });

    test('Should return 0 unread count for empty list', () {
      // ARRANGE
      const emptyNotifications = <Map<String, dynamic>>[];
      const expectedCount = 0;
      
      // ACT
      final count = NotificationStorage.getUnreadCount(emptyNotifications);
      
      // ASSERT
      expect(count, expectedCount);
    });

    test('Should mark all notifications as read', () {
      // ARRANGE
      const expectedAllRead = true;
      
      // ACT
      final markedAll = NotificationStorage.markAllAsRead(notifications);
      
      // ASSERT
      expect(markedAll.every((n) => n['isRead'] == true), expectedAllRead);
    });

    test('Should sort notifications by date descending (newest first)', () {
      // ARRANGE
      final expectedFirstDate = '2024-01-15T10:00:00';
      final expectedSecondDate = '2024-01-14T10:00:00';
      final expectedThirdDate = '2024-01-13T10:00:00';
      
      // ACT
      final sorted = NotificationStorage.sortByDate(notifications);
      
      // ASSERT
      expect(sorted[0]['createdAt'], expectedFirstDate);
      expect(sorted[1]['createdAt'], expectedSecondDate);
      expect(sorted[2]['createdAt'], expectedThirdDate);
    });

    test('Should return true when notification count is within limit', () {
      // ARRANGE
      const currentCount = 50;
      
      // ACT
      final result = NotificationStorage.isWithinLimit(currentCount);
      
      // ASSERT
      expect(result, true);
    });

    test('Should return false when notification count reaches limit', () {
      // ARRANGE
      const currentCount = 100;
      
      // ACT
      final result = NotificationStorage.isWithinLimit(currentCount);
      
      // ASSERT
      expect(result, false);
    });
  });
}