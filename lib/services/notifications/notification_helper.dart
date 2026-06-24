// lib/services/notifications/notification_helper.dart
//
// Single place that handles the full "enable notifications" flow, used by
// both parent_home_screen.dart (reminder card / first-time dialog) and
// parent_profile_screen.dart (toggle). No duplicated dialog logic.

import 'package:flutter/material.dart';
import 'package:loringo_app/services/notifications/notification_permission_service.dart';
import 'package:loringo_app/services/notifications/one_signal_service.dart';
import 'package:loringo_app/theme/app_theme.dart';

class NotificationHelper {

  /// Full flow for enabling notifications.
  /// Shows the system dialog, or routes to Settings if permanently denied.
  /// Returns true if permission is now granted.
  static Future<bool> requestEnable({
    required BuildContext context,
    String? userId,
  }) async {
    final permanentlyDenied =
        await NotificationPermissionService.isPermanentlyDenied();

    if (permanentlyDenied) {
      // OS won't show the dialog — must go to Settings
      final goSettings = await _showSettingsDialog(
        context: context,
        title: 'Enable Notifications',
        icon: Icons.notifications_off_rounded,
        iconColor: AppColors.warning,
        message:
            'Notifications were previously denied.\n\n'
            'To receive updates about your child\'s progress, please '
            'enable notifications in your device settings.',
        actionLabel: 'Open Settings',
      );
      if (goSettings) NotificationPermissionService.openSettings();
      return false;
    }

    final granted = await NotificationPermissionService.requestPermission();
    if (granted && userId != null) {
      await OneSignalNotificationService.initializeUser(userId);
    }
    return granted;
  }

  /// Flow for disabling notifications — always routes to Settings because
  /// neither iOS nor Android allow apps to revoke permission programmatically.
  static Future<void> requestDisable({required BuildContext context}) async {
    final goSettings = await _showSettingsDialog(
      context: context,
      title: 'Disable Notifications',
      icon: Icons.settings_rounded,
      iconColor: AppColors.primary,
      message:
          'To turn off notifications, please go to your device settings '
          'and disable notifications for this app.',
      actionLabel: 'Open Settings',
    );
    if (goSettings) NotificationPermissionService.openSettings();
  }

  /// Shows the first-time permission dialog (called from home on first login).
  /// Returns true if the user chose to enable; false if they dismissed.
  static Future<bool> showFirstTimeDialog({
    required BuildContext context,
    String? userId,
  }) async {
    final shouldEnable = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.primarySoft(0.1),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: const Icon(Icons.notifications_active_rounded,
                color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: Text('Stay Updated',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ]),
        content: const Text(
          'Enable notifications to know when your child completes a unit '
          'quiz and receives a report.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not Now',
                style: TextStyle(color: AppColors.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.sm)),
              elevation: 0,
            ),
            child: const Text('Enable',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (shouldEnable == true) {
      return await requestEnable(context: context, userId: userId);
    }

    // User tapped "Not Now" — mark as asked so we don't re-prompt
    await NotificationPermissionService.setPermissionDeclined();
    return false;
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  static Future<bool> _showSettingsDialog({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color iconColor,
    required String message,
    required String actionLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Row(children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: AppSpacing.sm),
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        content: Text(message,
            style: const TextStyle(fontSize: 14, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.sm)),
              elevation: 0,
            ),
            child: Text(actionLabel,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}