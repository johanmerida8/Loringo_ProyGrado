// test/database/activity_progress_test.dart
//
// Replaces test/student/student_activity_progress_test.dart and
// test/student/student_activity_play_test.dart, which both reimplemented
// their own private `ActivityProgressSimulator`/`TaskTypeSimulator` classes
// instead of testing real app code (grep -rl "package:loringo_app" test/
// never matched either file). This exercises the real
// Database.saveActivityCompletion (lib/services/database/database.dart)
// against a FakeFirebaseFirestore instead.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/services/database/database.dart';

import '../helpers/firestore_seed.dart';

void main() {
  group('Database.saveActivityCompletion - AAA Pattern', () {
    late FakeFirebaseFirestore fakeDb;
    late Database database;
    const groupId = 'group_1';

    setUp(() async {
      fakeDb = FakeFirebaseFirestore();
      database = Database(firestore: fakeDb);
      await seedStudent(
          fakeDb, studentId: 'student_1', studentName: 'Ana', groupId: groupId);
    });

    Future<DocumentSnapshot<Map<String, dynamic>>> progressDocFor(
            String activityId) =>
        fakeDb
            .collection('teacherGroups')
            .doc(groupId)
            .collection('students')
            .doc('student_1')
            .collection('progress')
            .doc(activityId)
            .get();

    test('ARRANGE-ACT-ASSERT: first attempt computes XP from score plus the flat bonus',
        () async {
      // ARRANGE - no prior progress doc exists for this activity yet
      const xpBase = 100;
      const bonusXP = 50;

      // ACT - first, perfect attempt
      final xpEarned = await database.saveActivityCompletion(
        studentId: 'student_1',
        activityId: 'activity_1',
        contentId: 'content_1',
        unitId: 'unit_1',
        score: 100,
        correctAnswers: 5,
        wrongAnswers: 0,
        xpBase: xpBase,
        bonusXP: bonusXP,
      );

      // ASSERT - xpEarned = round(100 * 100/100) + 50 = 150 on a first attempt
      expect(xpEarned, 150);
      final progressDoc = await progressDocFor('activity_1');
      expect(progressDoc.data()!['bestScore'], 100);
      expect(progressDoc.data()!['totalAttempts'], 1);
      expect(progressDoc.data()!['stars'], 3); // bestScore >= 90 -> 3 stars
      final rosterDoc = await fakeDb
          .collection('teacherGroups')
          .doc(groupId)
          .collection('students')
          .doc('student_1')
          .get();
      expect(rosterDoc.data()!['xp'], 150);
    });

    test('ARRANGE-ACT-ASSERT: first attempt with a partial score still gets the flat bonus, but fewer stars',
        () async {
      // ARRANGE
      const xpBase = 100;
      const bonusXP = 50;

      // ACT - only 60% correct. A first attempt's XP formula is
      // round(xpBase * score/100) + bonusXP regardless of correctAnswers/
      // wrongAnswers or whether the run was perfect — bonusXP is NOT
      // conditional on a perfect score, unlike what the old (fake) test
      // for this file assumed.
      final xpEarned = await database.saveActivityCompletion(
        studentId: 'student_1',
        activityId: 'activity_2',
        contentId: 'content_1',
        unitId: 'unit_1',
        score: 60,
        correctAnswers: 3,
        wrongAnswers: 2,
        xpBase: xpBase,
        bonusXP: bonusXP,
      );

      // ASSERT - round(100 * 60/100) + 50 = 110, and 60% -> 1 star (below the 70 threshold)
      expect(xpEarned, 110);
      final progressDoc = await progressDocFor('activity_2');
      expect(progressDoc.data()!['stars'], 1);
    });

    test('ARRANGE-ACT-ASSERT: a retry that beats the previous best updates bestScore/stars, earns the one-time flat 5 XP bonus, and adds it to the roster',
        () async {
      // ARRANGE - a prior attempt already scored 60 (1 star)
      await seedActivityProgress(
        fakeDb,
        studentId: 'student_1',
        groupId: groupId,
        activityId: 'activity_3',
        contentId: 'content_1',
        unitId: 'unit_1',
        bestScore: 60,
        totalAttempts: 1,
        stars: 1,
        xpEarned: 60,
      );

      // ACT - retry scores 95, a strictly better attempt
      final xpEarned = await database.saveActivityCompletion(
        studentId: 'student_1',
        activityId: 'activity_3',
        contentId: 'content_1',
        unitId: 'unit_1',
        score: 95,
        correctAnswers: 5,
        wrongAnswers: 0,
        xpBase: 100,
        bonusXP: 50,
      );

      // ASSERT - the first improving retry earns a flat 5 XP bonus
      // (only a first attempt uses the xpBase/bonus formula), the bonus is
      // marked used so it can never be paid again for this activity, the
      // progress doc's xpEarned is the running sum (60 + 5 = 65, not a raw
      // overwrite), and the roster's xp counter is credited the same 5.
      expect(xpEarned, 5);
      final progressDoc = await progressDocFor('activity_3');
      expect(progressDoc.data()!['bestScore'], 95);
      expect(progressDoc.data()!['stars'], 3);
      expect(progressDoc.data()!['totalAttempts'], 2);
      expect(progressDoc.data()!['xpEarned'], 65);
      expect(progressDoc.data()!['retryBonusAwarded'], true);
      final rosterDoc = await fakeDb
          .collection('teacherGroups')
          .doc(groupId)
          .collection('students')
          .doc('student_1')
          .get();
      expect(rosterDoc.data()!['xp'], 5);
    });

    test('ARRANGE-ACT-ASSERT: a non-improving retry earns 0 XP and does not touch the roster or the progress doc xpEarned',
        () async {
      // ARRANGE - a prior attempt already scored 90
      await seedActivityProgress(
        fakeDb,
        studentId: 'student_1',
        groupId: groupId,
        activityId: 'activity_3b',
        contentId: 'content_1',
        unitId: 'unit_1',
        bestScore: 90,
        totalAttempts: 1,
        stars: 3,
        xpEarned: 140,
      );

      // ACT - retry ties at 90 (not a new best: strictly-greater required)
      final tieXp = await database.saveActivityCompletion(
        studentId: 'student_1',
        activityId: 'activity_3b',
        contentId: 'content_1',
        unitId: 'unit_1',
        score: 90,
        correctAnswers: 4,
        wrongAnswers: 1,
        xpBase: 100,
        bonusXP: 50,
      );

      // ASSERT
      expect(tieXp, 0);
      final progressDoc = await progressDocFor('activity_3b');
      expect(progressDoc.data()!['xpEarned'], 140);
      expect(progressDoc.data()!.containsKey('retryBonusAwarded'), false);
      final rosterDoc = await fakeDb
          .collection('teacherGroups')
          .doc(groupId)
          .collection('students')
          .doc('student_1')
          .get();
      expect(rosterDoc.data()!['xp'], 0);
    });

    test('ARRANGE-ACT-ASSERT: the retry bonus can only be paid once — a later attempt that improves further earns 0 extra XP',
        () async {
      // ARRANGE - first attempt (60), then an improving retry (95) that
      // already consumed the one-time bonus.
      await database.saveActivityCompletion(
        studentId: 'student_1',
        activityId: 'activity_3c',
        contentId: 'content_1',
        unitId: 'unit_1',
        score: 60,
        correctAnswers: 3,
        wrongAnswers: 2,
        xpBase: 100,
        bonusXP: 50,
      );
      await database.saveActivityCompletion(
        studentId: 'student_1',
        activityId: 'activity_3c',
        contentId: 'content_1',
        unitId: 'unit_1',
        score: 95,
        correctAnswers: 5,
        wrongAnswers: 0,
        xpBase: 100,
        bonusXP: 50,
      );
      final progressAfterBonus = await progressDocFor('activity_3c');
      final xpEarnedAfterBonus = progressAfterBonus.data()!['xpEarned'] as int;
      final rosterAfterBonus = await fakeDb
          .collection('teacherGroups')
          .doc(groupId)
          .collection('students')
          .doc('student_1')
          .get();
      final rosterXpAfterBonus = rosterAfterBonus.data()!['xp'] as int;

      // ACT - a third attempt improves further to a perfect 100
      final thirdXp = await database.saveActivityCompletion(
        studentId: 'student_1',
        activityId: 'activity_3c',
        contentId: 'content_1',
        unitId: 'unit_1',
        score: 100,
        correctAnswers: 5,
        wrongAnswers: 0,
        xpBase: 100,
        bonusXP: 50,
      );

      // ASSERT - the bonus was already used on attempt 2, so a further
      // improving attempt 3 earns nothing more, and neither the progress
      // doc's xpEarned nor the roster's xp increase beyond what attempt 2
      // already granted.
      expect(thirdXp, 0);
      final progressDoc = await progressDocFor('activity_3c');
      expect(progressDoc.data()!['bestScore'], 100);
      expect(progressDoc.data()!['xpEarned'], xpEarnedAfterBonus);
      final rosterDoc = await fakeDb
          .collection('teacherGroups')
          .doc(groupId)
          .collection('students')
          .doc('student_1')
          .get();
      expect(rosterDoc.data()!['xp'], rosterXpAfterBonus);
    });

    test('ARRANGE-ACT-ASSERT: a retry that scores worse keeps the previous bestScore and discards its taskAnswers',
        () async {
      // ARRANGE - a prior attempt already scored 90
      await seedActivityProgress(
        fakeDb,
        studentId: 'student_1',
        groupId: groupId,
        activityId: 'activity_4',
        contentId: 'content_1',
        unitId: 'unit_1',
        bestScore: 90,
        totalAttempts: 1,
        stars: 3,
        xpEarned: 140,
      );

      // ACT - retry scores only 40, strictly worse
      await database.saveActivityCompletion(
        studentId: 'student_1',
        activityId: 'activity_4',
        contentId: 'content_1',
        unitId: 'unit_1',
        score: 40,
        correctAnswers: 2,
        wrongAnswers: 3,
        xpBase: 100,
        bonusXP: 50,
        taskAnswers: {'task_1': {'answer': 'wrong'}},
      );

      // ASSERT - bestScore/stars stay at the prior best; the worse
      // attempt's taskAnswers are never persisted over the better one's;
      // xpEarned stays at the previously-granted total (no regression).
      final progressDoc = await progressDocFor('activity_4');
      expect(progressDoc.data()!['bestScore'], 90);
      expect(progressDoc.data()!['stars'], 3);
      expect(progressDoc.data()!['totalAttempts'], 2);
      expect(progressDoc.data()!['taskAnswers'], <String, dynamic>{});
      expect(progressDoc.data()!['xpEarned'], 140);
    });

    test('ARRANGE-ACT-ASSERT: a retry that ties the previous best still refreshes taskAnswers',
        () async {
      // ARRANGE - a prior attempt already scored 100
      await seedActivityProgress(
        fakeDb,
        studentId: 'student_1',
        groupId: groupId,
        activityId: 'activity_5',
        contentId: 'content_1',
        unitId: 'unit_1',
        bestScore: 100,
        totalAttempts: 1,
        stars: 3,
        xpEarned: 150,
      );

      // ACT - retry ties at 100 with a fresh set of answers
      await database.saveActivityCompletion(
        studentId: 'student_1',
        activityId: 'activity_5',
        contentId: 'content_1',
        unitId: 'unit_1',
        score: 100,
        correctAnswers: 5,
        wrongAnswers: 0,
        xpBase: 100,
        bonusXP: 50,
        taskAnswers: {'task_1': {'answer': 'correct again'}},
      );

      // ASSERT - a tie is not a new best, but the UI should still show
      // what just happened, so taskAnswers refreshes even on a tie; xpEarned
      // does not change on a tie (0 XP granted for this attempt).
      final progressDoc = await progressDocFor('activity_5');
      expect(progressDoc.data()!['bestScore'], 100);
      expect(progressDoc.data()!['taskAnswers'], {'task_1': {'answer': 'correct again'}});
      expect(progressDoc.data()!['xpEarned'], 150);
    });

    test('ARRANGE-ACT-ASSERT: a second activity completion is reflected on the group roster progress subcollection',
        () async {
      // ARRANGE - no progress doc yet for this activity
      final before = await progressDocFor('activity_6');

      // ACT - complete the activity
      await database.saveActivityCompletion(
        studentId: 'student_1',
        activityId: 'activity_6',
        contentId: 'content_1',
        unitId: 'unit_1',
        score: 80,
        correctAnswers: 4,
        wrongAnswers: 1,
        xpBase: 100,
        bonusXP: 50,
      );
      final after = await progressDocFor('activity_6');

      // ASSERT
      expect(before.exists, false);
      expect(after.data()!['isCompleted'], true);
    });
  });
}
