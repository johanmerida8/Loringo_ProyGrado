// test/database/activity_feedback_test.dart
//
// Replaces test/teacher/progress/feedback_test.dart, which reimplemented
// its own `FeedbackValidator` (length limits, default feedback templates)
// with no counterpart in lib/ — that screen's actual feedback text field
// has no such length validation in the source, and the "default feedback"
// templates don't exist anywhere in lib/. What IS real is the persistence
// step: Database.saveActivityFeedback/saveLessonQuizFeedback, tested here
// against FakeFirebaseFirestore.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/services/database/database.dart';

import '../helpers/firestore_seed.dart';

void main() {
  group('Database.saveActivityFeedback/saveLessonQuizFeedback - AAA Pattern', () {
    late FakeFirebaseFirestore fakeDb;
    late Database database;
    const groupId = 'group_1';

    setUp(() async {
      fakeDb = FakeFirebaseFirestore();
      database = Database(firestore: fakeDb);
      await seedStudent(
          fakeDb, studentId: 'student_1', studentName: 'Ana', groupId: groupId);
    });

    test('ARRANGE-ACT-ASSERT: saving activity feedback merges it onto the existing progress doc',
        () async {
      // ARRANGE - a progress doc already exists from a completed activity
      await seedActivityProgress(
        fakeDb,
        studentId: 'student_1',
        groupId: groupId,
        activityId: 'activity_1',
        contentId: 'content_1',
        unitId: 'unit_1',
        bestScore: 80,
      );

      // ACT
      await database.saveActivityFeedback(
        groupId: groupId,
        studentId: 'student_1',
        activityId: 'activity_1',
        feedback: 'Great job on this one!',
      );

      // ASSERT - feedback added without clobbering the existing score fields
      final doc = await fakeDb
          .collection('teacherGroups')
          .doc(groupId)
          .collection('students')
          .doc('student_1')
          .collection('progress')
          .doc('activity_1')
          .get();
      expect(doc.data()!['feedback'], 'Great job on this one!');
      expect(doc.data()!['bestScore'], 80);
    });

    test('ARRANGE-ACT-ASSERT: saving lesson quiz feedback merges it onto the quiz progress doc',
        () async {
      // ARRANGE - no prior progress doc for this quiz yet
      // ACT
      await database.saveLessonQuizFeedback(
        groupId: groupId,
        studentId: 'student_1',
        quizId: 'quiz_1',
        feedback: 'Review question 3.',
      );

      // ASSERT - saveLessonQuizFeedback creates the doc via merge if absent
      final doc = await fakeDb
          .collection('teacherGroups')
          .doc(groupId)
          .collection('students')
          .doc('student_1')
          .collection('progress')
          .doc('quiz_1')
          .get();
      expect(doc.data()!['feedback'], 'Review question 3.');
    });

    test('ARRANGE-ACT-ASSERT: saving feedback again overwrites the previous feedback text',
        () async {
      // ARRANGE
      await database.saveActivityFeedback(
        groupId: groupId,
        studentId: 'student_1', activityId: 'activity_2', feedback: 'First note');

      // ACT
      await database.saveActivityFeedback(
        groupId: groupId,
        studentId: 'student_1', activityId: 'activity_2', feedback: 'Updated note');

      // ASSERT
      final doc = await fakeDb
          .collection('teacherGroups')
          .doc(groupId)
          .collection('students')
          .doc('student_1')
          .collection('progress')
          .doc('activity_2')
          .get();
      expect(doc.data()!['feedback'], 'Updated note');
    });
  });
}
