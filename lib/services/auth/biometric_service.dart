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
      print('Biometric authentication error: ${e.message}');
      return false;
    } catch (e) {
      print('Unexpected authentication error: $e');
      return false;
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
    } catch (e) {
      print('Error saving biometric preference: $e');
    }
  }

  /// Check if biometric is enabled for user
  static Future<bool> isBiometricEnabled(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('biometric_enabled_$userId') ?? false;
    } catch (e) {
      print('Error checking biometric preference: $e');
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
}
