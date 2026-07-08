import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Check if device supports biometrics
  static Future<bool> isDeviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (e) {
      print('Error checking device support: $e');
      return false;
    }
  }

  /// Get available biometric types
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e) {
      print('Error getting available biometrics: $e');
      return [];
    }
  }

  /// Check if biometrics are available and enrolled
  static Future<bool> canCheckBiometrics() async {
    try {
      return await _auth.canCheckBiometrics;
    } catch (e) {
      print('Error checking biometrics: $e');
      return false;
    }
  }

  /// Authenticate using biometrics
  static Future<bool> authenticate({
    required String reason,
    bool biometricOnly = true,
  }) async {
    try {
      final bool canAuthenticate = await canCheckBiometrics() || 
                                   await _auth.isDeviceSupported();
      
      if (!canAuthenticate) {
        print('Biometrics not available on this device');
        return false;
      }

      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
          useErrorDialogs: true,
          sensitiveTransaction: false,
        ),
      );

      return didAuthenticate;
    } on PlatformException catch (e) {
      // Handle specific cancellation cases
      if (e.code == 'ErrorCanceled' || 
          e.code == 'Canceled' ||
          e.code == 'USER_CANCELED' ||
          e.code == 'NotAvailable' ||
          e.code == 'LockedOut' ||
          e.code == 'PermanentlyLockedOut' ||
          e.message?.contains('cancel') == true ||
          e.message?.contains('Cancel') == true) {
        print('Biometric authentication was canceled by user');
        return false;  // User explicitly canceled
      }
      
      // Other platform errors
      print('Biometric authentication error: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      print('Unexpected authentication error: $e');
      return false;
    }
  }

  /// Authenticate with more detailed result (returns enum for better UX)
  static Future<BiometricResult> authenticateWithResult({
    required String reason,
    bool biometricOnly = true,
  }) async {
    try {
      final bool canAuthenticate = await canCheckBiometrics() || 
                                   await _auth.isDeviceSupported();
      
      if (!canAuthenticate) {
        return const BiometricResult.unavailable();
      }

      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: biometricOnly,
          useErrorDialogs: true,
          sensitiveTransaction: false,
        ),
      );

      if (didAuthenticate) {
        return const BiometricResult.success();
      } else {
        return const BiometricResult.failed();
      }
    } on PlatformException catch (e) {
      if (e.code == 'ErrorCanceled' || 
          e.code == 'Canceled' ||
          e.code == 'USER_CANCELED') {
        return const BiometricResult.canceled();
      }
      
      if (e.code == 'LockedOut' || e.code == 'PermanentlyLockedOut') {
        return const BiometricResult.lockedOut();
      }
      
      if (e.code == 'NotAvailable') {
        return const BiometricResult.notAvailable();
      }
      
      return BiometricResult.error(e.message ?? 'Unknown error');
    } catch (e) {
      return BiometricResult.error(e.toString());
    }
  }

  /// Save biometric preference for user
  static Future<void> setBiometricEnabled({
    required String userId,
    required bool enabled,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('biometric_enabled_$userId', enabled);
      print('🔐✅ SET: biometric_enabled_$userId = $enabled');
      
      // Verify it was saved
      final verifyValue = prefs.getBool('biometric_enabled_$userId');
      print('🔐✅ VERIFY: biometric_enabled_$userId = $verifyValue');
    } catch (e) {
      print('🔐❌ Error saving biometric preference: $e');
    }
  }

  /// Check if biometric is enabled for user
  static Future<bool> isBiometricEnabled(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool('biometric_enabled_$userId') ?? false;
      print('🔐📖 GET: biometric_enabled_$userId = $value');
      return value;
    } catch (e) {
      print('🔐❌ Error checking biometric preference: $e');
      return false;
    }
  }

  /// Get biometric type name for display
  static String getBiometricTypeName(List<BiometricType> types) {
    if (types.isEmpty) return 'Biometrics';
    
    if (types.contains(BiometricType.face)) {
      return 'Face ID';
    } else if (types.contains(BiometricType.fingerprint)) {
      return 'Fingerprint';
    } else if (types.contains(BiometricType.iris)) {
      return 'Iris';
    } else {
      return 'Biometrics';
    }
  }
  
  /// Clear all biometric settings for a user (useful for debugging)
  static Future<void> clearBiometricSettings(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('biometric_enabled_$userId');
      print('🔐🗑️ CLEARED: biometric settings for user $userId');
    } catch (e) {
      print('🔐❌ Error clearing biometric preference: $e');
    }
  }
}

/// Detailed result type for biometric authentication
class BiometricResult {
  final bool success;
  final bool canceled;
  final bool failed;
  final bool unavailable;
  final bool lockedOut;
  final bool notAvailable;
  final String? errorMessage;

  const BiometricResult._({
    required this.success,
    required this.canceled,
    required this.failed,
    required this.unavailable,
    required this.lockedOut,
    required this.notAvailable,
    this.errorMessage,
  });

  const BiometricResult.success() 
    : this._(success: true, canceled: false, failed: false, unavailable: false, lockedOut: false, notAvailable: false);
  
  const BiometricResult.canceled() 
    : this._(success: false, canceled: true, failed: false, unavailable: false, lockedOut: false, notAvailable: false);
  
  const BiometricResult.failed() 
    : this._(success: false, canceled: false, failed: true, unavailable: false, lockedOut: false, notAvailable: false);
  
  const BiometricResult.unavailable() 
    : this._(success: false, canceled: false, failed: false, unavailable: true, lockedOut: false, notAvailable: false);
  
  const BiometricResult.lockedOut() 
    : this._(success: false, canceled: false, failed: false, unavailable: false, lockedOut: true, notAvailable: false);
  
  const BiometricResult.notAvailable() 
    : this._(success: false, canceled: false, failed: false, unavailable: false, lockedOut: false, notAvailable: true);
  
  const BiometricResult.error(String message) 
    : this._(success: false, canceled: false, failed: true, unavailable: false, lockedOut: false, notAvailable: false, errorMessage: message);

  bool get isSuccess => success;
  bool get isCanceled => canceled;
  bool get isFailed => failed;
  bool get isUnavailable => unavailable;
  bool get isLockedOut => lockedOut;
  bool get isNotAvailable => notAvailable;
  bool get hasError => errorMessage != null;
}