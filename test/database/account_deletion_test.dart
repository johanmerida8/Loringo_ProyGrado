// test/database/account_deletion_test.dart
//
// Covers the data-lifecycle policy: deleteStudentCascade (parent removes
// one child, or their whole account), leaveGroup/switchGroup (teacher
// removes a student / student changes groups — now deletes instead of
// just marking status:'left'), and deleteTeacherOwnedData (teacher
// deletes their own account).
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/services/database/database.dart';

import '../helpers/firestore_seed.dart';

void main() {
  group('Database.deleteStudentCascade - AAA Pattern', () {
    late FakeFirebaseFirestore fakeDb;
    late Database database;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      database = Database(firestore: fakeDb);
    });

    test('ARRANGE-ACT-ASSERT: deletes the student and all progress/reports across every group they were ever in',
        () async {
      // ARRANGE - student currently in group_2, previously in group_1
      // (recorded in groupHistory)
      await seedStudent(fakeDb,
          studentId: 'student_1', studentName: 'Ana', groupId: 'group_2');
      await fakeDb.collection('students').doc('student_1').update({
        'groupHistory': [
          {'groupId': 'group_1'},
          {'groupId': 'group_2'},
        ],
      });
      // Historical group_1 roster (not seeded by seedStudent, which only
      // seeds the current group)
      await fakeDb
          .collection('teacherGroups')
          .doc('group_1')
          .collection('students')
          .doc('student_1')
          .set({'studentId': 'student_1', 'status': 'left'});

      await seedActivityProgress(fakeDb,
          studentId: 'student_1',
          groupId: 'group_1',
          activityId: 'activity_a',
          contentId: 'content_1',
          unitId: 'unit_1',
          bestScore: 80);
      await fakeDb
          .collection('teacherGroups')
          .doc('group_1')
          .collection('students')
          .doc('student_1')
          .collection('progress')
          .doc('activity_a')
          .collection('attempts')
          .doc('attempt_1')
          .set({'score': 80});
      await fakeDb
          .collection('teacherGroups')
          .doc('group_1')
          .collection('students')
          .doc('student_1')
          .collection('reports')
          .doc('unit_1')
          .set({'feedback': 'Good job'});

      await seedActivityProgress(fakeDb,
          studentId: 'student_1',
          groupId: 'group_2',
          activityId: 'activity_b',
          contentId: 'content_2',
          unitId: 'unit_2',
          bestScore: 90);

      // ACT
      await database.deleteStudentCascade('student_1');

      // ASSERT
      expect((await fakeDb.collection('students').doc('student_1').get()).exists,
          false);
      for (final groupId in ['group_1', 'group_2']) {
        final rosterDoc = await fakeDb
            .collection('teacherGroups')
            .doc(groupId)
            .collection('students')
            .doc('student_1')
            .get();
        expect(rosterDoc.exists, false, reason: '$groupId roster doc');
      }
      final group1Progress = await fakeDb
          .collection('teacherGroups')
          .doc('group_1')
          .collection('students')
          .doc('student_1')
          .collection('progress')
          .get();
      expect(group1Progress.docs, isEmpty);
      final group1Attempts = await fakeDb
          .collection('teacherGroups')
          .doc('group_1')
          .collection('students')
          .doc('student_1')
          .collection('progress')
          .doc('activity_a')
          .collection('attempts')
          .get();
      expect(group1Attempts.docs, isEmpty);
      final group1Reports = await fakeDb
          .collection('teacherGroups')
          .doc('group_1')
          .collection('students')
          .doc('student_1')
          .collection('reports')
          .get();
      expect(group1Reports.docs, isEmpty);
      final group2Progress = await fakeDb
          .collection('teacherGroups')
          .doc('group_2')
          .collection('students')
          .doc('student_1')
          .collection('progress')
          .get();
      expect(group2Progress.docs, isEmpty);
    });
  });

  group('Database.leaveGroup - AAA Pattern', () {
    late FakeFirebaseFirestore fakeDb;
    late Database database;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      database = Database(firestore: fakeDb);
    });

    test('ARRANGE-ACT-ASSERT: deletes the roster doc and progress/reports for that group, but keeps the student profile and groupHistory',
        () async {
      // ARRANGE
      await seedStudent(fakeDb,
          studentId: 'student_1', studentName: 'Ana', groupId: 'group_1');
      await fakeDb.collection('students').doc('student_1').update({
        'groupHistory': [
          {'groupId': 'group_1'},
        ],
      });
      await seedActivityProgress(fakeDb,
          studentId: 'student_1',
          groupId: 'group_1',
          activityId: 'activity_a',
          contentId: 'content_1',
          unitId: 'unit_1',
          bestScore: 80);
      await fakeDb
          .collection('teacherGroups')
          .doc('group_1')
          .collection('students')
          .doc('student_1')
          .collection('reports')
          .doc('unit_1')
          .set({'feedback': 'Good job'});

      // ACT
      await database.leaveGroup(studentId: 'student_1', groupId: 'group_1');

      // ASSERT - roster/progress/reports gone
      final rosterDoc = await fakeDb
          .collection('teacherGroups')
          .doc('group_1')
          .collection('students')
          .doc('student_1')
          .get();
      expect(rosterDoc.exists, false);
      final progressSnap = await fakeDb
          .collection('teacherGroups')
          .doc('group_1')
          .collection('students')
          .doc('student_1')
          .collection('progress')
          .get();
      expect(progressSnap.docs, isEmpty);

      // ASSERT - student profile and groupHistory survive
      final studentDoc =
          await fakeDb.collection('students').doc('student_1').get();
      expect(studentDoc.exists, true);
      expect(studentDoc.data()!['groupHistory'], isNotEmpty);
    });
  });

  group('Database.switchGroup - AAA Pattern', () {
    late FakeFirebaseFirestore fakeDb;
    late Database database;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      database = Database(firestore: fakeDb);
    });

    test('ARRANGE-ACT-ASSERT: old group progress is deleted, new group starts fresh',
        () async {
      // ARRANGE
      await seedStudent(fakeDb,
          studentId: 'student_1', studentName: 'Ana', groupId: 'group_1', xp: 500);
      await seedActivityProgress(fakeDb,
          studentId: 'student_1',
          groupId: 'group_1',
          activityId: 'activity_a',
          contentId: 'content_1',
          unitId: 'unit_1',
          bestScore: 80);

      // ACT
      await database.switchGroup(
          studentId: 'student_1', oldGroupId: 'group_1', newGroupId: 'group_2');

      // ASSERT - old group's roster/progress gone
      final oldRoster = await fakeDb
          .collection('teacherGroups')
          .doc('group_1')
          .collection('students')
          .doc('student_1')
          .get();
      expect(oldRoster.exists, false);

      // ASSERT - new group roster exists, fresh (xp: 0)
      final newRoster = await fakeDb
          .collection('teacherGroups')
          .doc('group_2')
          .collection('students')
          .doc('student_1')
          .get();
      expect(newRoster.exists, true);
      expect(newRoster.data()!['xp'], 0);
    });
  });

  group('Database.deleteTeacherOwnedData - AAA Pattern', () {
    late FakeFirebaseFirestore fakeDb;
    late Database database;
    const teacherId = 'teacher_1';

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      database = Database(firestore: fakeDb);
    });

    test('ARRANGE-ACT-ASSERT: deletes content, media categories/images, bookmarks, league campaign, and every owned group (with student progress) — but keeps student profiles',
        () async {
      // ARRANGE - content
      await fakeDb.collection('content').add({'teacherId': teacherId, 'title': 'Unit 1'});

      // ARRANGE - media library category + image
      final categoryRef = await fakeDb
          .collection('mediaLibrary')
          .doc(teacherId)
          .collection('categories')
          .add({'displayName': 'Animals'});
      await categoryRef.collection('imageItems').add({'name': 'cat.png'});

      // ARRANGE - continue bookmark
      await fakeDb
          .collection('teacherContinueBookmarks')
          .doc(teacherId)
          .collection('bookmarks')
          .doc('bookmark_1')
          .set({'level': 'unit'});

      // ARRANGE - league campaign
      await fakeDb.collection('leagueCampaigns').doc(teacherId).set({'scope': 'all'});

      // ARRANGE - an owned group with one student's progress
      await seedTeacherGroup(fakeDb,
          groupId: 'group_1', teacherId: teacherId, groupCode: 'ABC123');
      await seedStudent(fakeDb,
          studentId: 'student_1', studentName: 'Ana', groupId: 'group_1');
      await seedActivityProgress(fakeDb,
          studentId: 'student_1',
          groupId: 'group_1',
          activityId: 'activity_a',
          contentId: 'content_1',
          unitId: 'unit_1',
          bestScore: 80);

      // ACT
      await database.deleteTeacherOwnedData(teacherId);

      // ASSERT - content gone
      final contentSnap = await fakeDb
          .collection('content')
          .where('teacherId', isEqualTo: teacherId)
          .get();
      expect(contentSnap.docs, isEmpty);

      // ASSERT - media library category + image gone
      final categoriesSnap = await fakeDb
          .collection('mediaLibrary')
          .doc(teacherId)
          .collection('categories')
          .get();
      expect(categoriesSnap.docs, isEmpty);

      // ASSERT - bookmarks gone
      final bookmarksSnap = await fakeDb
          .collection('teacherContinueBookmarks')
          .doc(teacherId)
          .collection('bookmarks')
          .get();
      expect(bookmarksSnap.docs, isEmpty);

      // ASSERT - league campaign gone
      final leagueDoc =
          await fakeDb.collection('leagueCampaigns').doc(teacherId).get();
      expect(leagueDoc.exists, false);

      // ASSERT - the group itself and the student's progress under it are gone
      final groupDoc = await fakeDb.collection('teacherGroups').doc('group_1').get();
      expect(groupDoc.exists, false);
      final progressSnap = await fakeDb
          .collection('teacherGroups')
          .doc('group_1')
          .collection('students')
          .doc('student_1')
          .collection('progress')
          .get();
      expect(progressSnap.docs, isEmpty);

      // ASSERT - the student's own profile survives, with groupId cleared
      final studentDoc =
          await fakeDb.collection('students').doc('student_1').get();
      expect(studentDoc.exists, true);
      expect(studentDoc.data()!.containsKey('groupId'), false);
    });
  });
}
