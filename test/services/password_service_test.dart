// test/services/password_service_test.dart
//
// New coverage for lib/services/auth/password_service.dart's
// canRequestPasswordReset (rate limiting, per-user under
// users/{uid}/password_resets) and the pure getErrorMessage mapping.
// sendPasswordResetEmail/updatePassword call FirebaseAuth methods
// directly and are excluded (thin wrappers with no independent logic once
// canRequestPasswordReset already covers the gating rule).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/services/auth/password_service.dart';
import 'package:loringo_app/services/firebase_refs.dart';

void main() {
  group('PasswordService.canRequestPasswordReset - AAA Pattern', () {
    late FakeFirebaseFirestore fakeDb;

    setUp(() async {
      fakeDb = FakeFirebaseFirestore();
      firestoreInstance = fakeDb;
      await fakeDb.collection('users').doc('uid_1').set({
        'email': 'parent@loringo.app',
        'name': 'Parent',
      });
    });

    // Reset to a fresh fake, NOT the real FirebaseFirestore.instance —
    // plain `flutter test` runs never call Firebase.initializeApp(), so
    // touching the real singleton here would throw a "no Firebase App"
    // error (see test/helpers/firebase_test_setup.dart for the same
    // reasoning).
    tearDown(() {
      firestoreInstance = FakeFirebaseFirestore();
    });

    test('ARRANGE-ACT-ASSERT: an email with no account on file cannot request a reset',
        () async {
      // ARRANGE & ACT
      final result =
          await PasswordService.canRequestPasswordReset('nobody@loringo.app');

      // ASSERT
      expect(result['canReset'], false);
      expect(result['reason'], 'user_not_found');
    });

    test('ARRANGE-ACT-ASSERT: a known email with no prior attempts can request a reset',
        () async {
      // ARRANGE & ACT
      final result =
          await PasswordService.canRequestPasswordReset('parent@loringo.app');

      // ASSERT
      expect(result['canReset'], true);
      expect(result['attemptsToday'], 0);
    });

    test('ARRANGE-ACT-ASSERT: requesting again within the 15-minute cooldown is blocked',
        () async {
      // ARRANGE - a reset attempt 5 minutes ago
      await fakeDb
          .collection('users')
          .doc('uid_1')
          .collection('password_resets')
          .add({
        'email': 'parent@loringo.app',
        'requestedAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(minutes: 5))),
      });

      // ACT
      final result =
          await PasswordService.canRequestPasswordReset('parent@loringo.app');

      // ASSERT
      expect(result['canReset'], false);
      expect(result['reason'], 'cooldown');
      expect(result['remainingMinutes'], 10);
    });

    test('ARRANGE-ACT-ASSERT: reaching 3 attempts today blocks further requests even outside cooldown',
        () async {
      // ARRANGE - 3 attempts today, most recent 20 minutes ago
      final resetsRef = fakeDb
          .collection('users')
          .doc('uid_1')
          .collection('password_resets');
      final now = DateTime.now();
      for (var i = 0; i < 3; i++) {
        await resetsRef.add({
          'email': 'parent@loringo.app',
          'requestedAt': Timestamp.fromDate(now.subtract(Duration(minutes: 20 + i))),
        });
      }

      // ACT
      final result =
          await PasswordService.canRequestPasswordReset('parent@loringo.app');

      // ASSERT
      expect(result['canReset'], false);
      expect(result['reason'], 'daily_limit');
      expect(result['attempts'], 3);
    });
  });

  group('PasswordService.getErrorMessage - AAA Pattern', () {
    test('ARRANGE-ACT-ASSERT: user-not-found maps to a friendly message', () {
      // ARRANGE
      final exception = FirebaseAuthException(code: 'user-not-found');

      // ACT
      final message = PasswordService.getErrorMessage(exception);

      // ASSERT
      expect(message, 'No account found with this email');
    });

    test('ARRANGE-ACT-ASSERT: an unmapped code falls back to the raw Firebase message', () {
      // ARRANGE
      final exception = FirebaseAuthException(
        code: 'some-unmapped-code', message: 'Something odd happened');

      // ACT
      final message = PasswordService.getErrorMessage(exception);

      // ASSERT
      expect(message, 'Error: Something odd happened');
    });
  });
}
