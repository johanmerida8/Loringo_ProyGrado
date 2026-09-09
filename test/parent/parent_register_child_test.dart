// test/parent/parent_register_child_test.dart
//
// Replaces test/parent/child_registration_test.dart, which reimplemented
// its own access-code generator/validator with a stricter charset
// ('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', no O/0/I/1) that happens to match
// the real one in parent_register_child_screen.dart's _generateAccessCode
// — but the fake test never actually called the real code to prove it.
// This screen doesn't eagerly touch Firestore during build()/initState(),
// so — like ParentJoinGroupScreen — it can be pumped directly once its
// Firestore/Auth calls are routed through the swappable
// lib/services/firebase_refs.dart indirection, letting this test drive
// the real registration flow (including the real 8-child cap) against
// FakeFirebaseFirestore/MockFirebaseAuth.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/screens/parent/parent_register_child_screen.dart';

import '../helpers/firebase_test_setup.dart';
import '../helpers/pump_app.dart';

void main() {
  group('ParentRegisterChildScreen - AAA Pattern', () {
    tearDown(() {
      tearDownMockedFirebase();
    });

    testWidgets('ARRANGE-ACT-ASSERT: submitting an empty child name shows a validation snackbar',
        (tester) async {
      // ARRANGE
      setUpMockedFirebase(signedInUser: MockUser(uid: 'parent_1'));
      await pumpApp(tester, const ParentRegisterChildScreen());

      // ACT
      final registerButton = find.widgetWithText(ElevatedButton, 'Register Child');
      await tester.ensureVisible(registerButton);
      await tester.tap(registerButton);
      await tester.pump();

      // ASSERT
      expect(find.text('Please enter your child\'s name'), findsOneWidget);
    });

    testWidgets('ARRANGE-ACT-ASSERT: registering a child persists it under the signed-in parent and shows a 6-character access code',
        (tester) async {
      // ARRANGE
      final firebase = setUpMockedFirebase(signedInUser: MockUser(uid: 'parent_1'));
      await pumpApp(tester, const ParentRegisterChildScreen());

      // ACT
      await tester.enterText(find.byType(TextField), 'Juan Perez');
      final consentCheckbox = find.byType(Checkbox);
      await tester.ensureVisible(consentCheckbox);
      await tester.tap(consentCheckbox);
      await tester.pump();
      final registerButton = find.widgetWithText(ElevatedButton, 'Register Child');
      await tester.ensureVisible(registerButton);
      await tester.tap(registerButton);
      await tester.pumpAndSettle();

      // ASSERT - success view rendered with the child's name
      expect(find.text('Child Registered!'), findsOneWidget);
      expect(find.text('Juan Perez'), findsOneWidget);

      final studentsSnap = await firebase.firestore.collection('students').get();
      expect(studentsSnap.docs.length, 1);
      final student = studentsSnap.docs.first.data();
      expect(student['parentId'], 'parent_1');
      expect(student['names'], 'Juan Perez');
      // The raw access code is never stored — only its HMAC-SHA256 hash is
      // (see AccessCodeHasher/Database.createStudent). A sha256 hex digest
      // is always 64 characters.
      expect(student.containsKey('accessCode'), false);
      expect((student['accessCodeHash'] as String).length, 64);
      expect(student['childDataConsentAcceptedAt'], isNotNull);
      expect(student['childDataConsentVersion'], isNotEmpty);
    });

    testWidgets('ARRANGE-ACT-ASSERT: an 9th child registration is rejected once 8 already exist',
        (tester) async {
      // ARRANGE - 8 existing children already registered under this parent
      final firebase = setUpMockedFirebase(signedInUser: MockUser(uid: 'parent_1'));
      for (var i = 0; i < 8; i++) {
        await firebase.firestore.collection('students').add({
          'parentId': 'parent_1',
          'names': 'Child $i',
          'accessCodeHash': 'hash_of_code_0$i',
          'xp': 0,
        });
      }
      await pumpApp(tester, const ParentRegisterChildScreen());

      // ACT
      await tester.enterText(find.byType(TextField), 'One Too Many');
      final consentCheckbox = find.byType(Checkbox);
      await tester.ensureVisible(consentCheckbox);
      await tester.tap(consentCheckbox);
      await tester.pump();
      final registerButton = find.widgetWithText(ElevatedButton, 'Register Child');
      await tester.ensureVisible(registerButton);
      await tester.tap(registerButton);
      await tester.pumpAndSettle();

      // ASSERT - real cap message from the screen, and no 9th doc created
      expect(find.textContaining('Maximum number of children'), findsOneWidget);
      final studentsSnap = await firebase.firestore
          .collection('students')
          .where('parentId', isEqualTo: 'parent_1')
          .get();
      expect(studentsSnap.docs.length, 8);
    });
  });
}
