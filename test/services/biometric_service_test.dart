// test/services/biometric_service_test.dart
//
// New coverage for lib/services/auth/biometric_service.dart. Only its
// SharedPreferences-backed methods (setBiometricEnabled/isBiometricEnabled/
// clearBiometricSettings) and the pure getBiometricTypeName mapping are
// tested here — authenticate/authenticateWithResult/isDeviceSupported/
// canCheckBiometrics/getAvailableBiometrics all call LocalAuthentication()
// directly (a `static final` field, no injection point), a real platform
// channel with no handler registered in a plain `flutter test` run.
// Deliberately not faked or skipped silently — excluded and documented,
// same treatment as the other platform-channel-bound code in this suite
// (permission_handler in notification_permission_service_test.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:loringo_app/services/auth/biometric_service.dart';

import '../helpers/shared_prefs_helper.dart';

void main() {
  group('BiometricService - AAA Pattern', () {
    setUp(() {
      setUpMockSharedPreferences();
    });

    test('ARRANGE-ACT-ASSERT: biometric is disabled by default for a user who never set a preference',
        () async {
      // ARRANGE - setUp already primes empty SharedPreferences

      // ACT
      final isEnabled = await BiometricService.isBiometricEnabled('user_1');

      // ASSERT
      expect(isEnabled, false);
    });

    test('ARRANGE-ACT-ASSERT: setBiometricEnabled(true) persists per-user, not globally', () async {
      // ARRANGE & ACT
      await BiometricService.setBiometricEnabled(userId: 'user_1', enabled: true);
      final user1Enabled = await BiometricService.isBiometricEnabled('user_1');
      final user2Enabled = await BiometricService.isBiometricEnabled('user_2');

      // ASSERT
      expect(user1Enabled, true);
      expect(user2Enabled, false);
    });

    test('ARRANGE-ACT-ASSERT: clearBiometricSettings resets the preference back to disabled',
        () async {
      // ARRANGE
      await BiometricService.setBiometricEnabled(userId: 'user_1', enabled: true);

      // ACT
      await BiometricService.clearBiometricSettings('user_1');
      final isEnabled = await BiometricService.isBiometricEnabled('user_1');

      // ASSERT
      expect(isEnabled, false);
    });

    test('ARRANGE-ACT-ASSERT: getBiometricTypeName prefers Face ID over other available types',
        () {
      // ARRANGE
      const types = [BiometricType.fingerprint, BiometricType.face];

      // ACT
      final name = BiometricService.getBiometricTypeName(types);

      // ASSERT
      expect(name, 'Face ID');
    });

    test('ARRANGE-ACT-ASSERT: getBiometricTypeName falls back to Fingerprint when Face is unavailable',
        () {
      // ARRANGE
      const types = [BiometricType.fingerprint];

      // ACT
      final name = BiometricService.getBiometricTypeName(types);

      // ASSERT
      expect(name, 'Fingerprint');
    });

    test('ARRANGE-ACT-ASSERT: getBiometricTypeName returns a generic label for an empty type list',
        () {
      // ARRANGE
      const types = <BiometricType>[];

      // ACT
      final name = BiometricService.getBiometricTypeName(types);

      // ASSERT
      expect(name, 'Biometrics');
    });
  });
}
