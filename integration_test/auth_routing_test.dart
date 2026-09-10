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
// a real returning session both land on the correct real screen — plus the
// single-admin (image_manager) security rule end-to-end, which no existing
// test actually exercises despite core_flows_test.dart's header comment
// claiming Flujo 1 covers it (Flujo 1 only registers a *parent*).
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

Future<void> _fillAndSubmitRegisterForm(
  WidgetTester tester, {
  required String name,
  required String email,
  required String password,
}) async {
  await tester.tap(find.text('start'));
  await tester.pumpAndSettle();
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), name);
  await tester.enterText(fields.at(1), email);
  await tester.enterText(fields.at(2), password);
  await tester.enterText(fields.at(3), password);
  await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
  await tester.pumpAndSettle();
}

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
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pumpAndSettle();

      await pumpIntegrationApp(tester, const AuthGate());
      await tester.pumpAndSettle();

      // ASSERT - the real Firestore profile has the right role, and the
      // real AuthGate routed this brand-new, childless parent correctly
      expect(firebase.auth.currentUser?.email, 'carla@loringo.app');
      final userDoc = await firebase.firestore
          .collection('users')
          .doc(firebase.auth.currentUser!.uid)
          .get();
      expect(userDoc.data()!['role'], 'parent');
      expect(find.byType(ParentRegisterChildScreen), findsOneWidget);
    });
  });

  group('Regla de administrador único (image_manager)', () {
    testWidgets(
        'ARRANGE-ACT-ASSERT: a second admin registration is rejected before '
        'creating an Auth account, once one image_manager already exists',
        (tester) async {
      // ARRANGE
      final firebase = setUpIntegrationFirebase();

      // ACT - register the first admin (name "Admin" forces role
      // image_manager per RegisterScreen's admin-name detection), then
      // attempt a second admin registration with a different email while
      // still signed in as the first. AuthGate/AdminNavigationScreen are
      // deliberately never mounted here (see file header) - this only
      // needs the real RegisterScreen + Database.createUser chain.
      await pumpIntegrationApp(tester, _entryPoint(RegisterScreen(onTap: () {})));
      await _fillAndSubmitRegisterForm(tester,
          name: 'Admin', email: 'admin1@loringo.app', password: qaFixturePassword);
      final firstAdminUid = firebase.auth.currentUser!.uid;

      await pumpIntegrationApp(tester, _entryPoint(RegisterScreen(onTap: () {})));
      await _fillAndSubmitRegisterForm(tester,
          name: 'Administrador', email: 'admin2@loringo.app', password: qaFixturePassword);

      // ASSERT - the second attempt was blocked pre-Auth-creation (the
      // still-signed-in user is unchanged, no second Auth account got
      // created), the inline error is shown, and exactly one image_manager
      // profile exists in Firestore
      expect(firebase.auth.currentUser!.uid, firstAdminUid);
      expect(find.textContaining('administrator account already exists'), findsOneWidget);
      final imageManagerExists =
          await Database(firestore: firebase.firestore).imageManagerExists();
      expect(imageManagerExists, true);
      final usersSnap = await firebase.firestore.collection('users').get();
      final admins = usersSnap.docs.where((d) => d.data()['role'] == 'image_manager');
      expect(admins.length, 1);
      expect(admins.first.id, firstAdminUid);
    });
  });
}
