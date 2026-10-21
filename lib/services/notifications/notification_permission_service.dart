// lib/services/notifications/notification_permission_service.dart
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationPermissionService {
  static const String _permissionAskedKey   = 'notification_permission_asked';
  static const String _permissionGrantedKey = 'notification_permission_granted';

  /// Whether we should prompt the user for the first time.
  static Future<bool> shouldAskForPermission() async {
    if (kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_permissionAskedKey) ?? false);
  }

  /// Live check via permission_handler — reflects system-level state.
  static Future<bool> isPermissionGranted() async {
    if (kIsWeb) return false;
    try {
      final status = await Permission.notification.status;
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Returns true if the user has permanently denied (iOS: "Don't Allow" twice,
  /// Android: "Don't ask again"). In that case we must open system settings.
  static Future<bool> isPermanentlyDenied() async {
    if (kIsWeb) return false;
    try {
      final status = await Permission.notification.status;
      return status.isPermanentlyDenied;
    } catch (_) {
      return false;
    }
  }

  /// Request notification permission.
  /// Returns true if granted.
  static Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    try {
      // On Android, swiping the system permission dialog away (rather than
      // tapping "Allow"/"Don't Allow") can leave permission_handler's
      // native completer waiting forever — the dialog is gone but no
      // result callback ever fires, so `.request()` never resolves. A
      // try/catch around it doesn't help since nothing throws; it just
      // hangs. Bounding it with a timeout and falling back to a fresh
      // `.status` read (a separate, lightweight platform-channel call not
      // tied to the dismissed dialog's callback) unblocks the caller
      // either way, reflecting whatever the OS actually recorded.
      final status = await Permission.notification.request().timeout(
        const Duration(seconds: 15),
        onTimeout: () => Permission.notification.status,
      );
      final granted = status.isGranted;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_permissionAskedKey,   true);
      await prefs.setBool(_permissionGrantedKey, granted);

      // Also tell OneSignal
      if (granted) {
        await OneSignal.Notifications.requestPermission(true);
      }
      return granted;
    } catch (_) {
      return false;
    }
  }

  /// Opens system app settings so the user can manually toggle notifications.
  static Future<void> openSettings() => openAppSettings();

  /// Mark that the user explicitly declined (to avoid re-prompting).
  static Future<void> setPermissionDeclined() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_permissionAskedKey,   true);
    await prefs.setBool(_permissionGrantedKey, false);
  }

  static Future<void> resetPermissionState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_permissionAskedKey);
    await prefs.remove(_permissionGrantedKey);
  }
}