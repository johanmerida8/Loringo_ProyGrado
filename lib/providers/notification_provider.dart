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
    
    await _loadNotificationStatus();
    
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadNotificationStatus() async {
    _isEnabled = await NotificationPermissionService.isPermissionGranted();
    _isPermanentlyDenied = await NotificationPermissionService.isPermanentlyDenied();
  }

  Future<void> enableNotifications(BuildContext context) async {
    if (_userId == null) return;
    
    _isLoading = true;
    notifyListeners();
    
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
      _isLoading = false;
      notifyListeners();
      return;
    } else {
      // User previously declined but not permanently - request again
      granted = await NotificationPermissionService.requestPermission();
    }
    
    if (granted) {
      _isEnabled = true;
      _isPermanentlyDenied = false;
      
      // Initialize OneSignal
      await OneSignalNotificationService.initializeUser(_userId!);
      
      if (context.mounted) {
        _showSnackBar(context, 'Notifications enabled', isError: false);
      }
    } else {
      // Check if now permanently denied
      _isPermanentlyDenied = await NotificationPermissionService.isPermanentlyDenied();
      
      if (context.mounted && _isPermanentlyDenied) {
        _showSnackBar(context, 'Please enable notifications in settings', isError: true);
      } else if (context.mounted) {
        _showSnackBar(context, 'Notifications disabled', isError: true);
      }
    }
    
    _isLoading = false;
    notifyListeners();
  }

  Future<void> disableNotifications(BuildContext context) async {
    if (_userId == null) return;
    
    // Can't revoke programmatically, show settings dialog
    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disable Notifications'),
        content: const Text(
          'Notifications cannot be disabled from within the app. '
          'Would you like to open system settings to disable them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open Settings'),
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