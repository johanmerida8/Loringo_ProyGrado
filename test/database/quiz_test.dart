// test/database/quiz_test.dart
//
// Replaces test/teacher/quizzes/{unit,lesson}_quiz_validation_test.dart,
// which reimplemented invented validation rules (e.g. "max attempts
// between 1 and 5") with no counterpart in lib/. The real gating rules for
// quiz creation live in Database.createQuiz: no duplicate quiz per
// unit/lesson, a Unit Quiz requires at least kMinLessonQuizzesForUnitQuiz
// Lesson Quizzes to already exist, and xpReward is clamped to a
// unit/lesson-dependent max — all tested here for real against
// FakeFirebaseFirestore.
//
// Quizzes live nested under content/{contentId}/units/{unitId}/quizzes
// (Unit Quiz) or .../lessons/{lessonId}/quizzes (Lesson Quiz) — no more
// top-level 'quizzes' collection, no more 'scope' field on the doc itself
// (lessonId == null is the unit-vs-lesson signal now).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/services/database/database.dart';

void main() {
  group('Database.createQuiz/updateQuiz - AAA Pattern', () {
    late FakeFirebaseFirestore fakeDb;
    late Database database;

    DocumentReference quizDoc(
      String contentId,
      String unitId,
      String quizId, {
      String? lessonId,
    }) {
      final unitRef = fakeDb
          .collection('content')
          .doc(contentId)
          .collection('units')
          .doc(unitId);
      return (lessonId != null
              ? unitRef.collection('lessons').doc(lessonId).collection('quizzes')
              : unitRef.collection('quizzes'))
          .doc(quizId);
    }

    Future<void> seedLessonQuizzes(int count) async {
      for (var i = 0; i < count; i++) {
        // countLessonQuizzesForUnit walks the unit's actual lessons
        // subcollection to find each one's quizzes — matches how the real
        // app always has an existing lesson before a quiz can be attached
        // to it via CreateQuizScreen, unlike the old flat-collection query
        // which counted purely off the quizzes collection with no
        // dependency on the lesson doc existing.
        await database.personalizedLessons('content_1', 'unit_1').doc('lesson_$i').set({
          'title': 'Lesson $i',
          'order': i + 1,
        });
        await database.createQuiz(
          contentId: 'content_1',
          unitId: 'unit_1',
          quizId: 'lesson_quiz_$i',
          title: 'Lesson Quiz $i',
          questions: const [],
          passingScore: 0,
          xpReward: 10,
          maxAttempts: 3,
          groupId: 'group_1',
          lessonId: 'lesson_$i',
        );
      }
    }

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      database = Database(firestore: fakeDb);
    });

    test('ARRANGE-ACT-ASSERT: a Lesson Quiz can be created directly, with xpReward clamped to 50 max',
        () async {
      // ARRANGE & ACT
      await database.createQuiz(
        contentId: 'content_1',
        unitId: 'unit_1',
        quizId: 'quiz_1',
        title: 'Practice Quiz',
        questions: [
          {'question': 'Q1', 'options': ['A', 'B'], 'correctIndex': 0, 'order': 1},
        ],
        passingScore: 0,
        xpReward: 999, // way over the lesson-scope max
        maxAttempts: 3,
        groupId: 'group_1',
        lessonId: 'lesson_1',
      );

      // ASSERT
      final doc = await quizDoc('content_1', 'unit_1', 'quiz_1', lessonId: 'lesson_1').get();
      final data = doc.data() as Map<String, dynamic>;
      expect(data['xpReward'], 50);
      expect(data['isGraded'], false);
      expect(data['totalQuestions'], 1);
      expect(data.containsKey('scope'), false);
      expect(data.containsKey('lessonId'), false);
    });

    test('ARRANGE-ACT-ASSERT: a Unit Quiz is rejected until the unit has at least 3 Lesson Quizzes',
        () async {
      // ARRANGE - only 2 lesson quizzes exist for this unit
      await seedLessonQuizzes(2);

      // ACT & ASSERT
      expect(
        () => database.createQuiz(
          contentId: 'content_1',
          unitId: 'unit_1',
          quizId: 'unit_quiz_1',
          title: 'Unit Exam',
          questions: const [],
          passingScore: 60,
          xpReward: 100,
          maxAttempts: 1,
          groupId: 'group_1',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('ARRANGE-ACT-ASSERT: a Unit Quiz can be created once the unit has 3+ Lesson Quizzes, with xpReward clamped to 100 max',
        () async {
      // ARRANGE
      await seedLessonQuizzes(3);

      // ACT
      await database.createQuiz(
        contentId: 'content_1',
        unitId: 'unit_1',
        quizId: 'unit_quiz_1',
        title: 'Unit Exam',
        questions: const [],
        passingScore: 60,
        xpReward: 500, // way over the unit-scope max
        maxAttempts: 1,
        groupId: 'group_1',
      );

      // ASSERT
      final doc = await quizDoc('content_1', 'unit_1', 'unit_quiz_1').get();
      final data = doc.data() as Map<String, dynamic>;
      expect(data['xpReward'], 100);
      expect(data['isGraded'], true);
    });

    test('ARRANGE-ACT-ASSERT: creating a second Unit Quiz for the same unit is rejected',
        () async {
      // ARRANGE - a unit quiz already exists (after satisfying the lesson-quiz gate)
      await seedLessonQuizzes(3);
      await database.createQuiz(
        contentId: 'content_1',
        unitId: 'unit_1',
        quizId: 'unit_quiz_1',
        title: 'Unit Exam',
        questions: const [],
        passingScore: 60,
        xpReward: 100,
        maxAttempts: 1,
        groupId: 'group_1',
      );

      // ACT & ASSERT
      expect(
        () => database.createQuiz(
          contentId: 'content_1',
          unitId: 'unit_1',
          quizId: 'unit_quiz_2',
          title: 'Duplicate Unit Exam',
          questions: const [],
          passingScore: 60,
          xpReward: 100,
          maxAttempts: 1,
          groupId: 'group_1',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('ARRANGE-ACT-ASSERT: two different lessons in the same unit can each have their own Lesson Quiz',
        () async {
      // ARRANGE & ACT
      await database.personalizedLessons('content_1', 'unit_1').doc('lesson_a').set({'title': 'A', 'order': 1});
      await database.personalizedLessons('content_1', 'unit_1').doc('lesson_b').set({'title': 'B', 'order': 2});
      await database.createQuiz(
        contentId: 'content_1', unitId: 'unit_1', quizId: 'lq_a',
        title: 'Lesson A Quiz', questions: const [], passingScore: 0,
        xpReward: 10, maxAttempts: 3, groupId: 'g',
        lessonId: 'lesson_a');
      await database.createQuiz(
        contentId: 'content_1', unitId: 'unit_1', quizId: 'lq_b',
        title: 'Lesson B Quiz', questions: const [], passingScore: 0,
        xpReward: 10, maxAttempts: 3, groupId: 'g',
        lessonId: 'lesson_b');

      // ASSERT
      final count = await database.countLessonQuizzesForUnit(
        contentId: 'content_1', unitId: 'unit_1');
      expect(count, 2);
    });

    test('ARRANGE-ACT-ASSERT: updateQuiz replaces the question set and re-clamps xpReward to the target lessonId',
        () async {
      // ARRANGE - an existing lesson-scope quiz (max 50 XP). The old
      // question uses a non-colliding order/doc-id (q_9) from the new
      // ones (q_1/q_2) so this test isn't coincidentally dependent on
      // fake_cloud_firestore's same-batch delete+set-on-same-id ordering.
      await database.createQuiz(
        contentId: 'content_1', unitId: 'unit_1', quizId: 'quiz_1',
        title: 'Original', questions: [
          {'question': 'Old Q', 'options': ['A'], 'correctIndex': 0, 'order': 9},
        ], passingScore: 0, xpReward: 20, maxAttempts: 3,
        groupId: 'g', lessonId: 'lesson_1');

      // ACT
      await database.updateQuiz(
        contentId: 'content_1',
        unitId: 'unit_1',
        lessonId: 'lesson_1',
        quizId: 'quiz_1',
        title: 'Updated',
        passingScore: 0,
        xpReward: 999,
        maxAttempts: 5,
        questions: [
          {'question': 'New Q1', 'options': ['A', 'B'], 'correctIndex': 1, 'order': 1},
          {'question': 'New Q2', 'options': ['A', 'B'], 'correctIndex': 0, 'order': 2},
        ],
      );

      // ASSERT - re-clamped using the caller-supplied lessonId ('lesson_1' -> max 50)
      final ref = quizDoc('content_1', 'unit_1', 'quiz_1', lessonId: 'lesson_1');
      final doc = await ref.get();
      final data = doc.data() as Map<String, dynamic>;
      expect(data['title'], 'Updated');
      expect(data['xpReward'], 50);
      expect(data['totalQuestions'], 2);
      final questions = await ref.collection('questions').get();
      expect(questions.docs.length, 2);
      expect(questions.docs.any((d) => d.data()['question'] == 'Old Q'), false);
    });
  });
}
