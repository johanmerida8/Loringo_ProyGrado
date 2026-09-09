// test/database/quiz_completion_test.dart
//
// New coverage for Database.saveQuizCompletion — a different real code
// path from saveActivityCompletion (test/database/activity_progress_test
// .dart): quiz XP/pass rules depend on whether the caller passes a
// lessonId ('lesson' quizzes always count as passed and only pay XP once;
// 'unit' quizzes — no lessonId — use the caller's `passed`/`xpEarned`
// verbatim), which had zero test coverage before this suite.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/services/database/database.dart';

import '../helpers/firestore_seed.dart';

void main() {
  group('Database.saveQuizCompletion - AAA Pattern', () {
    late FakeFirebaseFirestore fakeDb;
    late Database database;

    setUp(() async {
      fakeDb = FakeFirebaseFirestore();
      database = Database(firestore: fakeDb);
      await seedStudent(fakeDb, studentId: 'student_1', studentName: 'Ana', groupId: 'g');
    });

    test('ARRANGE-ACT-ASSERT: a first Lesson Quiz attempt always counts as passed and pays its configured XP',
        () async {
      // ARRANGE - a lesson-scope quiz worth 10 XP
      await database.createQuiz(
        contentId: 'c', unitId: 'u', quizId: 'quiz_1', title: 'Lesson Quiz',
        questions: const [], passingScore: 0, xpReward: 10, maxAttempts: 3,
        groupId: 'g', lessonId: 'l');

      // ACT - the caller passes passed: false (a real UI wouldn't for a
      // lesson quiz, but this proves lessonId overrides the caller's value)
      await database.saveQuizCompletion(
        studentId: 'student_1', quizId: 'quiz_1', contentId: 'c', unitId: 'u',
        lessonId: 'l',
        correctAnswers: 3, totalQuestions: 5, answers: const [],
        xpEarned: 999, passed: false);

      // ASSERT - lessonId != null forces passed=true and uses the quiz's own
      // configured xpReward (10), not the caller's xpEarned (999); the
      // lessonId is also recorded onto the progress doc
      final progress = await fakeDb
          .collection('teacherGroups').doc('g')
          .collection('students').doc('student_1')
          .collection('progress').doc('quiz_1').get();
      expect(progress.data()!['passed'], true);
      expect(progress.data()!['xpEarned'], 10);
      expect(progress.data()!['lessonId'], 'l');
      final student = await fakeDb.collection('teacherGroups').doc('g').collection('students').doc('student_1').get();
      expect(student.data()!['xp'], 10);
    });

    test('ARRANGE-ACT-ASSERT: replaying an already-completed Lesson Quiz pays only the flat 5 XP retry bonus',
        () async {
      // ARRANGE - completed once already
      await database.createQuiz(
        contentId: 'c', unitId: 'u', quizId: 'quiz_1', title: 'Lesson Quiz',
        questions: const [], passingScore: 0, xpReward: 10, maxAttempts: 3,
        groupId: 'g', lessonId: 'l');
      await database.saveQuizCompletion(
        studentId: 'student_1', quizId: 'quiz_1', contentId: 'c', unitId: 'u',
        lessonId: 'l',
        correctAnswers: 3, totalQuestions: 5, answers: const [],
        xpEarned: 10, passed: true);

      // ACT - replay
      await database.saveQuizCompletion(
        studentId: 'student_1', quizId: 'quiz_1', contentId: 'c', unitId: 'u',
        lessonId: 'l',
        correctAnswers: 5, totalQuestions: 5, answers: const [],
        xpEarned: 10, passed: true);

      // ASSERT - flat 5 XP on replay, not the configured 10 again
      final progress = await fakeDb
          .collection('teacherGroups').doc('g')
          .collection('students').doc('student_1')
          .collection('progress').doc('quiz_1').get();
      expect(progress.data()!['xpEarned'], 5);
      final student = await fakeDb.collection('teacherGroups').doc('g').collection('students').doc('student_1').get();
      expect(student.data()!['xp'], 15); // 10 (first) + 5 (replay)
    });

    test('ARRANGE-ACT-ASSERT: a failed Unit Quiz attempt earns no XP and is not marked passed',
        () async {
      // ARRANGE - the min-3-Lesson-Quiz gate must be satisfied first (see
      // test/database/quiz_test.dart for that rule's own coverage)
      for (var i = 0; i < 3; i++) {
        await database.personalizedLessons('c', 'u').doc('lesson_$i').set({'title': 'L$i', 'order': i + 1});
        await database.createQuiz(
          contentId: 'c', unitId: 'u', quizId: 'lq_$i', title: 'Lesson Quiz $i',
          questions: const [], passingScore: 0, xpReward: 10, maxAttempts: 3,
          groupId: 'g', lessonId: 'lesson_$i');
      }
      await database.createQuiz(
        contentId: 'c', unitId: 'u', quizId: 'quiz_2', title: 'Unit Exam',
        questions: const [], passingScore: 60, xpReward: 100, maxAttempts: 1,
        groupId: 'g');

      // ACT - the caller reports the attempt failed (no lessonId ⇒ unit quiz)
      await database.saveQuizCompletion(
        studentId: 'student_1', quizId: 'quiz_2', contentId: 'c', unitId: 'u',
        correctAnswers: 2, totalQuestions: 10, answers: const [],
        xpEarned: 0, passed: false);

      // ASSERT - unlike a lesson quiz, unit-scope respects the caller's passed value
      final progress = await fakeDb
          .collection('teacherGroups').doc('g')
          .collection('students').doc('student_1')
          .collection('progress').doc('quiz_2').get();
      expect(progress.data()!['passed'], false);
      expect(progress.data()!.containsKey('lessonId'), false);
      final student = await fakeDb.collection('teacherGroups').doc('g').collection('students').doc('student_1').get();
      expect(student.data()!['xp'], 0); // seeded at 0, unchanged since the attempt failed
    });

    test('ARRANGE-ACT-ASSERT: a passing Unit Quiz attempt records the real score percentage and stars',
        () async {
      // ARRANGE - the min-3-Lesson-Quiz gate must be satisfied first
      for (var i = 0; i < 3; i++) {
        await database.personalizedLessons('c', 'u').doc('lesson2_$i').set({'title': 'L$i', 'order': i + 1});
        await database.createQuiz(
          contentId: 'c', unitId: 'u', quizId: 'lq2_$i', title: 'Lesson Quiz $i',
          questions: const [], passingScore: 0, xpReward: 10, maxAttempts: 3,
          groupId: 'g', lessonId: 'lesson2_$i');
      }
      await database.createQuiz(
        contentId: 'c', unitId: 'u', quizId: 'quiz_3', title: 'Unit Exam',
        questions: const [], passingScore: 60, xpReward: 100, maxAttempts: 1,
        groupId: 'g');

      // ACT - 9/10 = 90%
      await database.saveQuizCompletion(
        studentId: 'student_1', quizId: 'quiz_3', contentId: 'c', unitId: 'u',
        correctAnswers: 9, totalQuestions: 10, answers: const [],
        xpEarned: 100, passed: true);

      // ASSERT
      final progress = await fakeDb
          .collection('teacherGroups').doc('g')
          .collection('students').doc('student_1')
          .collection('progress').doc('quiz_3').get();
      expect(progress.data()!['bestScore'], 90);
      expect(progress.data()!['stars'], 3);
      expect(progress.data()!['passed'], true);
    });
  });
}
