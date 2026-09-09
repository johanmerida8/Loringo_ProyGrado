// test/services/notification_permission_service_test.dart
//
// Replaces test/notification/notification_permission_test.dart,
// test/notification/notification_service_test.dart,
// test/notification/notification_storage_test.dart, and
// test/parent/notification_logic_test.dart. All four reimplemented
// private classes (icon/title lookups, a notification "storage" filter/
// sort/mark-all-read API, a "build notification data" builder,
// formatTimeAgo) with no reachable real counterpart:
//   - The icon/title/time-ago/filter/sort/mark-all-read logic lives only
//     inline inside lib/screens/shared/notifications_screen.dart (shared
//     by both the teacher and parent nav, since both roles read the same
//     `notifications` collection filtered by userId), which calls
//     FirebaseAuth.instance/FirebaseFirestore.instance directly inside
//     initState() (loads the signed-in user's notifications the instant
//     the widget mounts) and has no constructor injection point —
//     so, like the blocked screens documented in
//     content_hierarchy_test.dart, it can't be pumped in a test.
//   - Unlike the content/quiz/progress screens, there's no fallback
//     Database method to pivot to either: `Database`
//     (lib/services/database/database.dart) has zero notification-related
//     methods — the `notifications` collection this screen reads is
//     populated entirely server-side by Cloud Functions
//     (functions/src/activityCreatedNotifications.ts,
//     scheduledNotifications.ts, notifyOverdueActivities.ts), which are
//     out of scope for this Flutter-only test suite.
//
// What IS real, reachable, and worth testing on the client is
// NotificationPermissionService's SharedPreferences-backed state
// (lib/services/notifications/notification_permission_service.dart) —
// the "have we already asked/declined" bookkeeping that drives whether
// the first-time permission dialog shows again. Its
// isPermissionGranted/isPermanentlyDenied/requestPermission methods call
// permission_handler (a platform channel with no handler registered in a
// plain `flutter test` run) — those are excluded here, not faked.
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/services/notifications/notification_permission_service.dart';

import '../helpers/shared_prefs_helper.dart';

void main() {
  group('NotificationPermissionService - AAA Pattern', () {
    setUp(() {
      setUpMockSharedPreferences();
    });

    test('ARRANGE-ACT-ASSERT: a fresh install should ask for permission', () async {
      // ARRANGE - setUp already primes empty SharedPreferences

      // ACT
      final shouldAsk = await NotificationPermissionService.shouldAskForPermission();

      // ASSERT
      expect(shouldAsk, true);
    });

    test('ARRANGE-ACT-ASSERT: after the user declines, shouldAskForPermission returns false',
        () async {
      // ARRANGE & ACT
      await NotificationPermissionService.setPermissionDeclined();
      final shouldAsk = await NotificationPermissionService.shouldAskForPermission();

      // ASSERT
      expect(shouldAsk, false);
    });

    test('ARRANGE-ACT-ASSERT: resetPermissionState clears the declined flag and asks again',
        () async {
      // ARRANGE - the user previously declined
      await NotificationPermissionService.setPermissionDeclined();

      // ACT
      await NotificationPermissionService.resetPermissionState();
      final shouldAsk = await NotificationPermissionService.shouldAskForPermission();

      // ASSERT
      expect(shouldAsk, true);
    });
  });
}
