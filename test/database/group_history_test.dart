// test/database/group_history_test.dart
//
// Covers the students/{id}/groupHistory subcollection: joinGroup writes one
// doc per group (no duplicates on rejoin), leaveGroup keeps the entry, and the
// lifetime-history readers (getAllReportsEver) find groups from the
// subcollection, the legacy root-doc array (students not migrated yet) and
// the student's current group.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/services/database/database.dart';

import '../helpers/firestore_seed.dart';

void main() {
  late FakeFirebaseFirestore fakeDb;
  late Database database;

  setUp(() {
    fakeDb = FakeFirebaseFirestore();
    database = Database(firestore: fakeDb);
  });

  Future<void> seedReport(String groupId, String studentId, String unitId) {
    return fakeDb
        .collection('teacherGroups')
        .doc(groupId)
        .collection('students')
        .doc(studentId)
        .collection('reports')
        .doc(unitId)
        .set({'feedback': 'from $groupId'});
  }

  group('Database.joinGroup / leaveGroup - groupHistory subcollection', () {
    test('ARRANGE-ACT-ASSERT: joinGroup records the group in the subcollection, not in a root array',
        () async {
      // ARRANGE
      await seedStudent(fakeDb, studentId: 'student_1', studentName: 'Ana');

      // ACT
      await database.joinGroup(studentId: 'student_1', groupId: 'group_1');

      // ASSERT
      final entry = await database.studentGroupHistory('student_1').doc('group_1').get();
      expect(entry.exists, true);
      expect(entry.data()!['groupId'], 'group_1');
      expect(entry.data()!['joinedAt'], isNotNull);
      final student = await fakeDb.collection('students').doc('student_1').get();
      expect(student.data()!['groupId'], 'group_1');
      expect(student.data()!.containsKey('groupHistory'), false);
    });

    test('ARRANGE-ACT-ASSERT: rejoining the same group does not duplicate the entry',
        () async {
      // ARRANGE
      await seedStudent(fakeDb, studentId: 'student_1', studentName: 'Ana');
      await database.joinGroup(studentId: 'student_1', groupId: 'group_1');
      await database.leaveGroup(studentId: 'student_1', groupId: 'group_1');

      // ACT
      await database.joinGroup(studentId: 'student_1', groupId: 'group_1');

      // ASSERT
      final snap = await database.studentGroupHistory('student_1').get();
      expect(snap.docs.length, 1);
    });

    test('ARRANGE-ACT-ASSERT: leaveGroup keeps the entry',
        () async {
      // ARRANGE
      await seedStudent(fakeDb, studentId: 'student_1', studentName: 'Ana');
      await database.joinGroup(studentId: 'student_1', groupId: 'group_1');

      // ACT
      await database.leaveGroup(studentId: 'student_1', groupId: 'group_1');

      // ASSERT
      final entry = await database.studentGroupHistory('student_1').doc('group_1').get();
      expect(entry.exists, true);
    });

    test('ARRANGE-ACT-ASSERT: leaveGroup on a student with no history entry (legacy) does not invent one',
        () async {
      // ARRANGE - only the legacy array, nothing in the subcollection
      await seedStudent(fakeDb,
          studentId: 'student_1', studentName: 'Ana', groupId: 'group_1');
      await fakeDb.collection('students').doc('student_1').update({
        'groupHistory': [
          {'groupId': 'group_1'},
        ],
      });

      // ACT
      await database.leaveGroup(studentId: 'student_1', groupId: 'group_1');

      // ASSERT
      final snap = await database.studentGroupHistory('student_1').get();
      expect(snap.docs, isEmpty);
    });
  });

  group('Database.getAllReportsEver - where the group list comes from', () {
    test('ARRANGE-ACT-ASSERT: finds reports of groups in the subcollection, the legacy array and the current group',
        () async {
      // ARRANGE - group_a in the subcollection, group_b only in the legacy
      // array, group_c is the current group
      await seedStudent(fakeDb,
          studentId: 'student_1', studentName: 'Ana', groupId: 'group_c');
      await fakeDb.collection('students').doc('student_1').update({
        'groupHistory': [
          {'groupId': 'group_b'},
        ],
      });
      await database
          .studentGroupHistory('student_1')
          .doc('group_a')
          .set({'groupId': 'group_a'});
      await seedReport('group_a', 'student_1', 'unit_a');
      await seedReport('group_b', 'student_1', 'unit_b');
      await seedReport('group_c', 'student_1', 'unit_c');

      // ACT
      final reports = await database.getAllReportsEver('student_1');

      // ASSERT
      expect(reports.map((r) => r['id']).toSet(), {'unit_a', 'unit_b', 'unit_c'});
    });
  });
}
