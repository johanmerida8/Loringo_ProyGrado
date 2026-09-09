import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/services/notifications/notification_permission_service.dart';
import 'package:loringo_app/services/notifications/one_signal_service.dart';

class NotificationProvider extends ChangeNotifier {
  bool _isEnabled = false;
  bool _isLoading = true;
  bool _isPermanentlyDenied = false;
  String? _userId;

  bool get isEnabled => _isEnabled;
  bool get isLoading => _isLoading;
  bool get isPermanentlyDenied => _isPermanentlyDenied;

  Future<void> initialize(String userId) async {
    if (_userId == userId && _userId != null) return;

    _userId = userId;
    _isLoading = true;
    notifyListeners();

    try {
      await _loadNotificationStatus();
    } finally {
      // finally guarantees this runs even if _loadNotificationStatus()
      // throws (e.g. plugin/platform-channel error) — without it, an
      // exception here would leave isLoading stuck true forever, since
      // nothing else ever resets it.
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadNotificationStatus() async {
    _isEnabled = await NotificationPermissionService.isPermissionGranted();
    _isPermanentlyDenied = await NotificationPermissionService.isPermanentlyDenied();
  }

  Future<void> enableNotifications(BuildContext context) async {
    if (_userId == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      // Check if we should ask for permission
      final shouldAsk = await NotificationPermissionService.shouldAskForPermission();

      bool granted = false;

      if (shouldAsk) {
        // First time - request permission
        granted = await NotificationPermissionService.requestPermission();
      } else if (_isPermanentlyDenied) {
        // User permanently denied - open settings
        await NotificationPermissionService.openSettings();
        // After returning from settings, reload status
        await _loadNotificationStatus();
        return;
      } else {
        // User previously declined but not permanently - request again.
        // Note: after a first denial most platforms won't show the OS
        // dialog again (it silently resolves to denied) — that's a
        // platform restriction, not something this app controls. The
        // permanently-denied check below still catches the case where
        // the OS has since escalated the denial, routing the user to
        // Settings instead of leaving them stuck with no feedback.
        granted = await NotificationPermissionService.requestPermission();
      }

      if (granted) {
        _isEnabled = true;
        _isPermanentlyDenied = false;

        // Initialize OneSignal
        await OneSignalNotificationService.initializeUser(_userId!);

        if (context.mounted) {
          _showSnackBar(context, 'common.notificationsEnabled'.tr(), isError: false);
        }
      } else {
        // Check if now permanently denied
        _isPermanentlyDenied = await NotificationPermissionService.isPermanentlyDenied();

        if (context.mounted && _isPermanentlyDenied) {
          _showSnackBar(context,
              'providers.notification_provider.enableInSettings'.tr(), isError: true);
        } else if (context.mounted) {
          _showSnackBar(context,
              'providers.notification_provider.notificationsDisabled'.tr(), isError: true);
        }
      }
    } catch (e) {
      if (context.mounted) {
        _showSnackBar(
            context, 'common.errorWithMessage'.tr(namedArgs: {'error': '$e'}),
            isError: true);
      }
    } finally {
      // finally guarantees isLoading always resets, including the early
      // `return` above and any exception thrown by the permission plugin
      // or OneSignal init — previously this was plain sequential code at
      // the end of the method, so any throw left the toggle spinning
      // forever with no way to retry short of restarting the app.
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> disableNotifications(BuildContext context) async {
    if (_userId == null) return;
    
    // Can't revoke programmatically, show settings dialog
    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('common.disableNotifications'.tr()),
        content: Text(
          'providers.notification_provider.disableDialogBody'.tr(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('providers.notification_provider.openSettings'.tr()),
          ),
        ],
      ),
    );
    
    if (shouldOpenSettings == true) {
      await NotificationPermissionService.openSettings();
      // Reload status after returning from settings
      await _loadNotificationStatus();
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await _loadNotificationStatus();
    notifyListeners();
  }

  void _showSnackBar(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}