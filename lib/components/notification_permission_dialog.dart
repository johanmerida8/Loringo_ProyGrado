// lib/components/notification_permission_dialog.dart
import 'package:flutter/material.dart';
// import 'package:loringo_app/services/notification/notification_permission_service.dart';
import 'package:loringo_app/services/notifications/notification_permission_service.dart';
import 'package:loringo_app/theme/app_theme.dart';

class NotificationPermissionDialog extends StatelessWidget {
  final VoidCallback onPermissionGranted;
  final VoidCallback onPermissionDenied;

  const NotificationPermissionDialog({
    super.key,
    required this.onPermissionGranted,
    required this.onPermissionDenied,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_active_rounded,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),

            // Title
            const Text(
              'Enable Notifications',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // Description
            const Text(
              'Stay updated when your child completes quizzes and activities. '
              'You will receive instant reports about their progress.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),

            // Enable Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final granted = await NotificationPermissionService.requestPermission();
                  Navigator.pop(context);
                  if (granted) {
                    onPermissionGranted();
                  } else {
                    onPermissionDenied();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Enable Notifications',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Maybe Later Button
            TextButton(
              onPressed: () async {
                await NotificationPermissionService.setPermissionDeclined();
                Navigator.pop(context);
                onPermissionDenied();
              },
              child: const Text(
                'Maybe Later',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}