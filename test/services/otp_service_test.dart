// test/services/otp_service_test.dart
//
// New coverage for lib/services/auth/otp_service.dart's rate-limiting math
// (canResendOTP/canRequestOTP), which reads/writes the real
// `password_reset_logs` collection via the swappable
// lib/services/firebase_refs.dart indirection (already applied to this
// file for the Database DI work). sendOTPToEmail/verifyOTP/updatePassword
// call FirebaseFunctions.instance.httpsCallable(...) directly — Cloud
// Functions, out of scope for this Flutter-only suite — so only the
// client-side cooldown/daily-limit logic is tested here.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/services/auth/otp_service.dart';
import 'package:loringo_app/services/firebase_refs.dart';

void main() {
  group('OTPService rate limiting - AAA Pattern', () {
    late FakeFirebaseFirestore fakeDb;
    late OTPService otpService;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      firestoreInstance = fakeDb;
      otpService = OTPService();
    });

    // Reset to a fresh fake, NOT the real FirebaseFirestore.instance — see
    // test/helpers/firebase_test_setup.dart for why.
    tearDown(() {
      firestoreInstance = FakeFirebaseFirestore();
    });

    test('ARRANGE-ACT-ASSERT: a first-time request with no prior log entries can resend',
        () async {
      // ARRANGE - no password_reset_logs for this email

      // ACT
      final result = await otpService.canResendOTP('parent@loringo.app');

      // ASSERT
      expect(result['canSend'], true);
    });

    test('ARRANGE-ACT-ASSERT: resending within the cooldown window is blocked', () async {
      // ARRANGE - a log entry from 10 seconds ago (cooldown is 30s)
      await fakeDb.collection('password_reset_logs').add({
        'email': 'parent@loringo.app',
        'timestamp': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(seconds: 10))),
      });

      // ACT
      final result = await otpService.canResendOTP('parent@loringo.app');

      // ASSERT
      expect(result['canSend'], false);
      expect(result['reason'], 'resend_cooldown');
      expect((result['remainingSeconds'] as int) <= 20, true);
    });

    test('ARRANGE-ACT-ASSERT: resending after the cooldown window has passed is allowed',
        () async {
      // ARRANGE - a log entry from 60 seconds ago (cooldown is 30s)
      await fakeDb.collection('password_reset_logs').add({
        'email': 'parent@loringo.app',
        'timestamp': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(seconds: 60))),
      });

      // ACT
      final result = await otpService.canResendOTP('parent@loringo.app');

      // ASSERT
      expect(result['canSend'], true);
    });

    test('ARRANGE-ACT-ASSERT: a request within the long cooldown (15 min) is blocked with the remaining minutes',
        () async {
      // ARRANGE - a log entry from 5 minutes ago (long cooldown is 15 min)
      await fakeDb.collection('password_reset_logs').add({
        'email': 'parent@loringo.app',
        'timestamp': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(minutes: 5))),
      });

      // ACT
      final result = await otpService.canRequestOTP('parent@loringo.app');

      // ASSERT
      expect(result['canSend'], false);
      expect(result['reason'], 'cooldown');
      expect(result['remainingMinutes'], 10);
    });

    test('ARRANGE-ACT-ASSERT: reaching the daily limit (3 attempts) blocks further requests even outside cooldown',
        () async {
      // ARRANGE - 3 attempts today, the most recent 20 minutes ago (past the 15-min cooldown)
      final now = DateTime.now();
      for (var i = 0; i < 3; i++) {
        await fakeDb.collection('password_reset_logs').add({
          'email': 'parent@loringo.app',
          'timestamp': Timestamp.fromDate(now.subtract(Duration(minutes: 20 + i))),
        });
      }

      // ACT
      final result = await otpService.canRequestOTP('parent@loringo.app');

      // ASSERT
      expect(result['canSend'], false);
      expect(result['reason'], 'daily_limit');
      expect(result['attemptsToday'], 3);
    });
  });
}
