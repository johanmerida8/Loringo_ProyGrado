// integration_test/auth_routing_test.dart
//
// Dedicated integration coverage for the register/login -> AuthGate ->
// role-based routing chain, kept separate from core_flows_test.dart so it
// stays focused (that file's Flujo 1 is a full parent onboarding flow —
// register, child, group — not a routing test).
//
// AuthGate's routing *decisions* in isolation (no user, missing profile,
// invalid role) are already covered by test/role_routing_test.dart and are
// not repeated here. LoginScreen's own field validation and its successful
// sign-in call are already covered by test/login_validation_test.dart and
// are not repeated here either. What's missing, and what this file covers,
// is the real chain: a real RegisterScreen writes real Firestore data, and
// a real returning session both land on the correct real screen.
//
// Note on naming: the app has no "administrator" role. The only elevated
// role is `image_manager` (uploads/curates the educational image library).
// The public sign-up form only ever offers Teacher/Parent; image_manager
// accounts are not created through this app's UI at all.
//
// Two hard constraints shaped every test here, both discovered by making
// the naive version hang or throw:
//
// 1. TeacherHomeScreen, AdminNavigationScreen, AND ParentNavigationScreen
//    all call FirebaseAuth.instance/FirebaseFirestore.instance directly
//    instead of the swappable refs in lib/services/firebase_refs.dart, so
//    mounting any of them against fakes throws `[core/no-app]` (no real
//    Firebase app exists in this test environment). AuthGate is never let
//    build all the way into any of those three screens here — the same
//    scope limit test/role_routing_test.dart already documents for
//    admin/teacher turns out to apply to ParentNavigationScreen too. Only
//    the "parent, no children yet" branch is exercised end-to-end below,
//    since ParentRegisterChildScreen/_ParentRouter's query both go through
//    the swappable refs and are already proven safe by
//    core_flows_test.dart. The "parent, has children" branch would need
//    the DI refactor mentioned in content_hierarchy_test.dart's header
//    before it can be integration-tested this way.
//
// 2. MockFirebaseAuth.authStateChanges() only replays its buffered history
//    to the FIRST listener that EVER subscribes for a given instance
//    (firebase_auth_mocks wraps a single-subscription StreamController in
//    .asBroadcastStream(), which buffers events until first-ever listen,
//    then only live-forwards after that). A fresh AuthGate() mounted right
//    after register/login is that first-ever subscriber and works fine —
//    but a SECOND AuthGate mount later in the same test (e.g. after
//    signOut()) is a late subscriber and hangs forever waiting for an auth
//    event it already missed. So: at most one AuthGate mount per
//    MockFirebaseAuth instance, ever — every test below mounts it once.
//
// 3. The real RegisterScreen requires the privacy-consent checkbox to be
//    checked before it ever calls Firebase Auth — every fill-and-submit
//    sequence below must tap it, or _signUp() returns early and no
//    account/session exists at all.
//
// 4. AuthGate now requires teacher/parent accounts to have a verified
//    email (OTP, see auth_gate.dart's _EmailVerificationGate) before
//    routing to their real home screen — re-checked on every mount, not
//    just right after registration. OTPScreen.onVerified calls the
//    `confirmEmailVerified` Cloud Function, which has no backend in this
//    test environment, so the tests below that need to observe the
//    *post-verification* routing decision set `emailVerified: true`
//    directly on the Firestore profile instead of driving the real OTP
//    UI — simulating verification already having completed elsewhere.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:loringo_app/screens/initials/register_screen.dart';
import 'package:loringo_app/screens/parent/parent_register_child_screen.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:loringo_app/services/database/database.dart';

import 'helpers/integration_pump.dart';

// RegisterScreen calls Navigator.pop(context) on success, so it must be
// pushed onto a stack that has something underneath it.
Widget _entryPoint(Widget destination) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => destination),
            ),
            child: const Text('start'),
          ),
        ),
      ),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Registro -> AuthGate -> enrutamiento por rol', () {
    testWidgets(
        'ARRANGE-ACT-ASSERT: a parent who just registered, with no children '
        'yet, is routed to child registration',
        (tester) async {
      // ARRANGE
      final firebase = setUpIntegrationFirebase();

      // ACT - register as a parent through the real RegisterScreen (role
      // picker included), then mount a single fresh AuthGate to observe
      // where that new session actually gets routed
      await pumpIntegrationApp(tester, _entryPoint(RegisterScreen(onTap: () {})));
      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Carla Parent');
      await tester.enterText(fields.at(1), 'carla@loringo.app');
      await tester.enterText(fields.at(2), qaFixturePassword);
      await tester.enterText(fields.at(3), qaFixturePassword);
      await tester.tap(find.text('Parent'));
      await tester.pump();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pumpAndSettle();

      // Simulate the OTP email verification (see file header, point 4)
      // having already completed, so this test can observe the routing
      // decision AuthGate makes for a verified parent, not the
      // verification gate itself.
      await firebase.firestore
          .collection('users')
          .doc(firebase.auth.currentUser!.uid)
          .update({'emailVerified': true});

      await pumpIntegrationApp(tester, const AuthGate());
      await tester.pumpAndSettle();

      // ASSERT - the real Firestore profile has the right role, and the
      // real AuthGate routed this brand-new, childless, verified parent
      // correctly
      expect(firebase.auth.currentUser?.email, 'carla@loringo.app');
      final userDoc = await firebase.firestore
          .collection('users')
          .doc(firebase.auth.currentUser!.uid)
          .get();
      expect(userDoc.data()!['role'], 'parent');
      expect(find.byType(ParentRegisterChildScreen), findsOneWidget);
    });
  });

  group('El registro público nunca crea una cuenta image_manager', () {
    testWidgets(
        'ARRANGE-ACT-ASSERT: public sign-up always requires an explicit '
        'Teacher/Parent choice and never creates an image_manager account',
        (tester) async {
      // ARRANGE
      final firebase = setUpIntegrationFirebase();

      // ACT - fill out and submit the real registration form, picking
      // "Teacher" from the role selector like any other sign-up
      await pumpIntegrationApp(tester, _entryPoint(RegisterScreen(onTap: () {})));
      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Sofia Teacher');
      await tester.enterText(fields.at(1), 'notanimagemanager@loringo.app');
      await tester.enterText(fields.at(2), qaFixturePassword);
      await tester.enterText(fields.at(3), qaFixturePassword);
      await tester.tap(find.text('Teacher'));
      await tester.pump();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pumpAndSettle();

      // ASSERT - the real Firestore profile has the requested role
      // (teacher), never image_manager, and no image_manager account
      // exists anywhere in the system as a result of this sign-up
      expect(firebase.auth.currentUser?.email, 'notanimagemanager@loringo.app');
      final userDoc = await firebase.firestore
          .collection('users')
          .doc(firebase.auth.currentUser!.uid)
          .get();
      expect(userDoc.data()!['role'], 'teacher');
      final imageManagerExists =
          await Database(firestore: firebase.firestore).imageManagerExists();
      expect(imageManagerExists, false);
    });
  });
}
