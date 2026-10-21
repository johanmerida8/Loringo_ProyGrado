// test/parent/parent_join_group_test.dart
//
// Replaces test/parent/group_joining_test.dart, which reimplemented a
// `GroupJoiningValidator` with a 6-char regex format check that does NOT
// exist in the real screen — parent_join_group_screen.dart's _joinGroup
// only checks for an empty field client-side; any other invalid code is
// only caught after querying Firestore ("Invalid group code" exception).
// This screen doesn't eagerly touch Firestore during build()/initState()
// (unlike most other screens in this app), so it can be pumped directly;
// its Firestore calls were switched to the same swappable
// lib/services/firebase_refs.dart indirection already used for
// login/register/auth_gate, letting this test exercise the REAL full
// join flow against FakeFirebaseFirestore instead of stopping at
// client-side validation only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/screens/parent/parent_join_group_screen.dart';

import '../helpers/firebase_test_setup.dart';
import '../helpers/firestore_seed.dart';
import '../helpers/pump_app.dart';

void main() {
  group('ParentJoinGroupScreen - AAA Pattern', () {
    tearDown(() {
      tearDownMockedFirebase();
    });

    testWidgets('ARRANGE-ACT-ASSERT: submitting an empty group code shows a validation snackbar',
        (tester) async {
      // ARRANGE
      setUpMockedFirebase();
      await pumpApp(
        tester,
        ParentJoinGroupScreen(child: const {'id': 'student_1', 'names': 'Laura'}),
      );

      // ACT
      await tester.tap(find.widgetWithText(ElevatedButton, 'Join Group'));
      await tester.pump();

      // ASSERT
      expect(find.text('Please enter the group code'), findsOneWidget);
    });

    testWidgets('ARRANGE-ACT-ASSERT: a valid, existing group code joins the student to that group',
        (tester) async {
      // ARRANGE
      final firebase = setUpMockedFirebase();
      await seedTeacherGroup(
        firebase.firestore, groupId: 'group_1', teacherId: 'teacher_1',
        groupCode: 'ABC123', name: 'Grade 1');
      await seedStudent(
        firebase.firestore, studentId: 'student_1', studentName: 'Laura');
      await pumpApp(
        tester,
        ParentJoinGroupScreen(child: const {'id': 'student_1', 'names': 'Laura'}),
      );

      // ACT
      await tester.enterText(find.byType(TextField), 'ABC123');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Join Group'));
      await tester.pumpAndSettle();

      // ASSERT
      final studentDoc =
          await firebase.firestore.collection('students').doc('student_1').get();
      expect(studentDoc.data()!['groupId'], 'group_1');
      final membership = await firebase.firestore
          .collection('teacherGroups')
          .doc('group_1')
          .collection('students')
          .doc('student_1')
          .get();
      expect(membership.exists, true);
    });

    testWidgets('ARRANGE-ACT-ASSERT: a group code with no matching group shows an error and does not update the student',
        (tester) async {
      // ARRANGE
      final firebase = setUpMockedFirebase();
      await seedStudent(
        firebase.firestore, studentId: 'student_1', studentName: 'Laura');
      await pumpApp(
        tester,
        ParentJoinGroupScreen(child: const {'id': 'student_1', 'names': 'Laura'}),
      );

      // ACT
      await tester.enterText(find.byType(TextField), 'NOPE99');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Join Group'));
      await tester.pumpAndSettle();

      // ASSERT
      expect(find.textContaining('Invalid group code'), findsOneWidget);
      final studentDoc =
          await firebase.firestore.collection('students').doc('student_1').get();
      expect(studentDoc.data()!.containsKey('groupId'), false);
    });

    testWidgets('ARRANGE-ACT-ASSERT: an archived group rejects the join attempt',
        (tester) async {
      // ARRANGE
      final firebase = setUpMockedFirebase();
      await firebase.firestore.collection('teacherGroups').doc('group_2').set({
        'teacherId': 'teacher_1',
        'groupCode': 'OLD999',
        'name': 'Archived Group',
        'archived': true,
      });
      await seedStudent(
        firebase.firestore, studentId: 'student_1', studentName: 'Laura');
      await pumpApp(
        tester,
        ParentJoinGroupScreen(child: const {'id': 'student_1', 'names': 'Laura'}),
      );

      // ACT
      await tester.enterText(find.byType(TextField), 'OLD999');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Join Group'));
      await tester.pumpAndSettle();

      // ASSERT
      expect(find.textContaining('no longer accepting new students'), findsOneWidget);
    });
  });
}
