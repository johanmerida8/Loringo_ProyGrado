// test/services/content_assignment_guard_test.dart
//
// New coverage for lib/services/content/content_assignment_guard.dart,
// which had zero tests before this suite despite implementing a real,
// confirmed product rule: once a group's student has any progress on a
// content item (completed/attempted an activity or quiz), that content
// can no longer be unassigned from that group. Already DI-ready
// (constructor takes an injectable FirebaseFirestore), so no source
// change was needed to test it.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/services/content/content_assignment_guard.dart';
import 'package:loringo_app/services/database/database.dart';

void main() {
  group('ContentAssignmentGuard - AAA Pattern', () {
    late FakeFirebaseFirestore fakeDb;
    late ContentAssignmentGuard guard;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      guard = ContentAssignmentGuard(Database(firestore: fakeDb), firestore: fakeDb);
    });

    test('ARRANGE-ACT-ASSERT: a group with no students has no progress and is not locked',
        () async {
      // ARRANGE - no students in group_1 at all

      // ACT
      final hasProgress = await guard.hasStudentProgress(
        contentId: 'content_1', groupId: 'group_1');

      // ASSERT
      expect(hasProgress, false);
    });

    test('ARRANGE-ACT-ASSERT: a group whose students have never attempted this content is not locked',
        () async {
      // ARRANGE - a student on the group's roster, but no progress doc referencing content_1
      await fakeDb
          .collection('teacherGroups').doc('group_1')
          .collection('students').doc('student_1')
          .set({'studentId': 'student_1', 'status': 'active'});

      // ACT
      final hasProgress = await guard.hasStudentProgress(
        contentId: 'content_1', groupId: 'group_1');

      // ASSERT
      expect(hasProgress, false);
    });

    test('ARRANGE-ACT-ASSERT: a group where one student has progress on this content is locked',
        () async {
      // ARRANGE
      await fakeDb
          .collection('teacherGroups').doc('group_1')
          .collection('students').doc('student_1')
          .set({'studentId': 'student_1', 'status': 'active'});
      await fakeDb
          .collection('teacherGroups').doc('group_1')
          .collection('students').doc('student_1')
          .collection('progress')
          .doc('activity_1')
          .set({'contentId': 'content_1', 'isCompleted': true});

      // ACT
      final hasProgress = await guard.hasStudentProgress(
        contentId: 'content_1', groupId: 'group_1');

      // ASSERT
      expect(hasProgress, true);
    });

    test('ARRANGE-ACT-ASSERT: progress on a DIFFERENT content does not lock this one', () async {
      // ARRANGE
      await fakeDb
          .collection('teacherGroups').doc('group_1')
          .collection('students').doc('student_1')
          .set({'studentId': 'student_1', 'status': 'active'});
      await fakeDb
          .collection('teacherGroups').doc('group_1')
          .collection('students').doc('student_1')
          .collection('progress')
          .doc('activity_1')
          .set({'contentId': 'some_other_content', 'isCompleted': true});

      // ACT
      final hasProgress = await guard.hasStudentProgress(
        contentId: 'content_1', groupId: 'group_1');

      // ASSERT
      expect(hasProgress, false);
    });

    test('ARRANGE-ACT-ASSERT: lockedGroupIds returns only the groups that actually have progress',
        () async {
      // ARRANGE - group_1 has progress on content_1, group_2 does not
      await fakeDb
          .collection('teacherGroups').doc('group_1')
          .collection('students').doc('s1')
          .set({'studentId': 's1', 'status': 'active'});
      await fakeDb
          .collection('teacherGroups').doc('group_1')
          .collection('students').doc('s1').collection('progress').doc('a1')
          .set({'contentId': 'content_1', 'isCompleted': true});
      await fakeDb
          .collection('teacherGroups').doc('group_2')
          .collection('students').doc('s2')
          .set({'studentId': 's2', 'status': 'active'});

      // ACT
      final locked = await guard.lockedGroupIds(
        contentId: 'content_1', groupIds: ['group_1', 'group_2']);

      // ASSERT
      expect(locked, {'group_1'});
    });
  });
}
