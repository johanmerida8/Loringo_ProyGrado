import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

class SpeechPermissions {
  /// Request microphone permission
  static Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    
    switch (status) {
      case PermissionStatus.granted:
        debugPrint('Microphone permission granted');
        return true;
      case PermissionStatus.denied:
        debugPrint('Microphone permission denied');
        return false;
      case PermissionStatus.permanentlyDenied:
        debugPrint('Microphone permission permanently denied');
        await openAppSettings();
        return false;
      default:
        return false;
    }
  }

  /// Check if microphone permission is granted
  static Future<bool> isMicrophonePermissionGranted() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  /// Show permission dialog
  static Future<bool> showPermissionDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Microphone Access Needed'),
        content: const Text(
          'This app needs microphone access to practice your English pronunciation. '
          'Please grant permission to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('Grant Permission'),
          ),
        ],
      ),
    );
    
    if (result == true) {
      return await requestMicrophonePermission();
    }
    return false;
  }
}