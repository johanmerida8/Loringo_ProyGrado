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
        questions: const [], xpReward: 10,
        lessonId: 'l');

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

    test('ARRANGE-ACT-ASSERT: replaying an already-completed Lesson Quiz earns 0 additional XP',
        () async {
      // ARRANGE - completed once already
      await database.createQuiz(
        contentId: 'c', unitId: 'u', quizId: 'quiz_1', title: 'Lesson Quiz',
        questions: const [], xpReward: 10,
        lessonId: 'l');
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

      // ASSERT - a lesson quiz has no retry-bonus mechanic; only the first
      // completion ever pays XP, so xpEarned stays at the running sum (10),
      // not the configured 10 again and not a flat retry bonus.
      final progress = await fakeDb
          .collection('teacherGroups').doc('g')
          .collection('students').doc('student_1')
          .collection('progress').doc('quiz_1').get();
      expect(progress.data()!['xpEarned'], 10);
      final student = await fakeDb.collection('teacherGroups').doc('g').collection('students').doc('student_1').get();
      expect(student.data()!['xp'], 10); // unchanged by the replay
    });

    test('ARRANGE-ACT-ASSERT: a failed Unit Quiz attempt earns no XP and is not marked passed',
        () async {
      // ARRANGE - the min-3-Lesson-Quiz gate must be satisfied first (see
      // test/database/quiz_test.dart for that rule's own coverage)
      for (var i = 0; i < 3; i++) {
        await database.personalizedLessons('c', 'u').doc('lesson_$i').set({'title': 'L$i', 'order': i + 1});
        await database.createQuiz(
          contentId: 'c', unitId: 'u', quizId: 'lq_$i', title: 'Lesson Quiz $i',
          questions: const [], xpReward: 10,
          lessonId: 'lesson_$i');
      }
      await database.createQuiz(
        contentId: 'c', unitId: 'u', quizId: 'quiz_2', title: 'Unit Exam',
        questions: const [], passingScore: 60, xpReward: 100, maxAttempts: 1);

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
          questions: const [], xpReward: 10,
          lessonId: 'lesson2_$i');
      }
      await database.createQuiz(
        contentId: 'c', unitId: 'u', quizId: 'quiz_3', title: 'Unit Exam',
        questions: const [], passingScore: 60, xpReward: 100, maxAttempts: 1);

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

    test('ARRANGE-ACT-ASSERT: a Unit Quiz retry that scores lower than the previous best earns 0 XP even if the client claims otherwise',
        () async {
      // ARRANGE - the min-3-Lesson-Quiz gate, then a first passing attempt at 90%
      for (var i = 0; i < 3; i++) {
        await database.personalizedLessons('c', 'u').doc('lesson4_$i').set({'title': 'L$i', 'order': i + 1});
        await database.createQuiz(
          contentId: 'c', unitId: 'u', quizId: 'lq4_$i', title: 'Lesson Quiz $i',
          questions: const [], xpReward: 10,
          lessonId: 'lesson4_$i');
      }
      await database.createQuiz(
        contentId: 'c', unitId: 'u', quizId: 'quiz_4', title: 'Unit Exam',
        questions: const [], passingScore: 60, xpReward: 100, maxAttempts: 3);
      await database.saveQuizCompletion(
        studentId: 'student_1', quizId: 'quiz_4', contentId: 'c', unitId: 'u',
        correctAnswers: 9, totalQuestions: 10, answers: const [],
        xpEarned: 100, passed: true);

      // ACT - a passing retry that scores lower (70% < 90%), but the client
      // still (incorrectly, or maliciously) sends a nonzero xpEarned
      await database.saveQuizCompletion(
        studentId: 'student_1', quizId: 'quiz_4', contentId: 'c', unitId: 'u',
        correctAnswers: 7, totalQuestions: 10, answers: const [],
        xpEarned: 8, passed: true);

      // ASSERT - the server ignores the client's xpEarned for a
      // non-improving retry: no XP granted, progress/roster unchanged.
      final progress = await fakeDb
          .collection('teacherGroups').doc('g')
          .collection('students').doc('student_1')
          .collection('progress').doc('quiz_4').get();
      expect(progress.data()!['bestScore'], 90);
      expect(progress.data()!['xpEarned'], 100);
      final student = await fakeDb.collection('teacherGroups').doc('g').collection('students').doc('student_1').get();
      expect(student.data()!['xp'], 100);
    });

    test('ARRANGE-ACT-ASSERT: a Unit Quiz retry bonus can only be paid once — a second improving retry earns 0 extra XP',
        () async {
      // ARRANGE - the min-3-Lesson-Quiz gate, a first attempt (70%), then an
      // improving retry (90%) that consumes the one-time retry bonus.
      for (var i = 0; i < 3; i++) {
        await database.personalizedLessons('c', 'u').doc('lesson5_$i').set({'title': 'L$i', 'order': i + 1});
        await database.createQuiz(
          contentId: 'c', unitId: 'u', quizId: 'lq5_$i', title: 'Lesson Quiz $i',
          questions: const [], xpReward: 10,
          lessonId: 'lesson5_$i');
      }
      await database.createQuiz(
        contentId: 'c', unitId: 'u', quizId: 'quiz_5', title: 'Unit Exam',
        questions: const [], passingScore: 60, xpReward: 100, maxAttempts: 3);
      await database.saveQuizCompletion(
        studentId: 'student_1', quizId: 'quiz_5', contentId: 'c', unitId: 'u',
        correctAnswers: 7, totalQuestions: 10, answers: const [],
        xpEarned: 70, passed: true);
      await database.saveQuizCompletion(
        studentId: 'student_1', quizId: 'quiz_5', contentId: 'c', unitId: 'u',
        correctAnswers: 9, totalQuestions: 10, answers: const [],
        xpEarned: 8, passed: true);
      final progressAfterBonus = await fakeDb
          .collection('teacherGroups').doc('g')
          .collection('students').doc('student_1')
          .collection('progress').doc('quiz_5').get();
      final xpEarnedAfterBonus = progressAfterBonus.data()!['xpEarned'] as int;

      // ACT - a second improving retry (100%), after the bonus is used up
      await database.saveQuizCompletion(
        studentId: 'student_1', quizId: 'quiz_5', contentId: 'c', unitId: 'u',
        correctAnswers: 10, totalQuestions: 10, answers: const [],
        xpEarned: 10, passed: true);

      // ASSERT
      final progress = await fakeDb
          .collection('teacherGroups').doc('g')
          .collection('students').doc('student_1')
          .collection('progress').doc('quiz_5').get();
      expect(progress.data()!['bestScore'], 100);
      expect(progress.data()!['xpEarned'], xpEarnedAfterBonus);
      final student = await fakeDb.collection('teacherGroups').doc('g').collection('students').doc('student_1').get();
      expect(student.data()!['xp'], xpEarnedAfterBonus);
    });
  });
}
