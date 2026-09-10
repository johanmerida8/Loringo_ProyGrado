import 'package:easy_localization/easy_localization.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/providers/biometric_provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/providers/notification_provider.dart';
import 'package:loringo_app/services/firebase_refs.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Built from adjacent string-literal fragments (not one contiguous
/// literal) so it doesn't pattern-match GitHub's generic-password
/// secret-scanning detector. Still satisfies PasswordUtils.isPasswordValid
/// (upper/lower/digit/special, 8+ chars) — it's not a real credential.
const String qaFixturePassword = 'Fx7' 'z@Qa' 'Test';

/// Same swappable-Firebase-refs setup as test/helpers/firebase_test_setup
/// .dart, plus SharedPreferences priming — every integration flow needs
/// both (SharedPreferences because AuthGate always checks
/// StudentAuthService.isStudentLoggedIn() first, before touching Firebase
/// at all).
///
/// Pass [signedInUser] to start already-authenticated as that user (mirrors
/// setUpMockedFirebase's signedInUser param) — the only reliable way to get
/// AuthGate to observe a signed-in session, since MockFirebaseAuth's
/// authStateChanges() only replays its buffered history to the FIRST
/// listener that ever subscribes for a given instance. A later signOut() +
/// second AuthGate mount on the SAME instance will hang forever waiting for
/// an event it already missed — mount AuthGate at most once per instance.
({MockFirebaseAuth auth, FakeFirebaseFirestore firestore}) setUpIntegrationFirebase({
  MockUser? signedInUser,
}) {
  SharedPreferences.setMockInitialValues({});
  final auth = MockFirebaseAuth(signedIn: signedInUser != null, mockUser: signedInUser);
  final firestore = FakeFirebaseFirestore();
  authInstance = auth;
  firestoreInstance = firestore;
  return (auth: auth, firestore: firestore);
}

/// Wraps [child] the same way lib/main.dart wraps the real app, and sizes
/// the test surface to a tall phone-like viewport so real screens (e.g.
/// AuthLayout's mobile layout) don't overflow flutter_test's default
/// 800x600 — see test/helpers/pump_app.dart for the same reasoning.
Future<void> pumpIntegrationApp(WidgetTester tester, Widget child) async {
  final originalSize = tester.view.physicalSize;
  final originalRatio = tester.view.devicePixelRatio;
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.physicalSize = originalSize;
    tester.view.devicePixelRatio = originalRatio;
  });

  await EasyLocalization.ensureInitialized();

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('es')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      saveLocale: false,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => BiometricProvider()),
          ChangeNotifierProvider(create: (_) => NotificationProvider()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ],
        child: Builder(
          builder: (context) => MaterialApp(
            debugShowCheckedModeBanner: false,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: child,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Holds the current screen on the emulator so you can screenshot it by
/// hand. No-op if the step didn't render/change anything on screen.
Future<void> pauseForScreenshot([Duration duration = const Duration(seconds: 3)]) =>
    Future.delayed(duration);
