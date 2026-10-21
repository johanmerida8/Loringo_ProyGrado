// test/database/league_season_xp_test.dart
//
// Covers Database's new active-campaign gating for the roster's seasonXp
// counter (lib/services/database/database.dart's
// _isLeagueCampaignActiveForGroup, used by saveActivityCompletion and
// saveQuizCompletion). Lifetime xp always accrues regardless of campaign
// state; seasonXp should only accrue while a leagueCampaigns/{teacherId}
// doc exists, applies to this student's group, and the current time falls
// within its startDate/endDate window.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/services/database/database.dart';

import '../helpers/firestore_seed.dart';

void main() {
  group('Database seasonXp - active league campaign gating', () {
    late FakeFirebaseFirestore fakeDb;
    late Database database;
    const teacherId = 'teacher_1';
    const groupId = 'group_1';

    setUp(() async {
      fakeDb = FakeFirebaseFirestore();
      database = Database(firestore: fakeDb);
      await seedTeacherGroup(
          fakeDb, groupId: groupId, teacherId: teacherId, groupCode: 'ABC123');
      await seedStudent(
          fakeDb, studentId: 'student_1', studentName: 'Ana', groupId: groupId);
    });

    Future<Map<String, dynamic>> rosterFor(String studentId) async {
      final doc = await fakeDb
          .collection('teacherGroups')
          .doc(groupId)
          .collection('students')
          .doc(studentId)
          .get();
      return doc.data()!;
    }

    Future<void> completeActivity() => database.saveActivityCompletion(
          studentId: 'student_1',
          activityId: 'activity_1',
          contentId: 'content_1',
          unitId: 'unit_1',
          score: 100,
          correctAnswers: 5,
          wrongAnswers: 0,
          xpBase: 100,
          bonusXP: 50,
        );

    test('ARRANGE-ACT-ASSERT: no seasonXp accrues when no campaign exists for the teacher',
        () async {
      // ARRANGE - no leagueCampaigns doc seeded at all

      // ACT
      await completeActivity();

      // ASSERT - xp always accrues; seasonXp stays absent/0 with no campaign
      final roster = await rosterFor('student_1');
      expect(roster['xp'], 150);
      expect(roster['seasonXp'] ?? 0, 0);
    });

    test('ARRANGE-ACT-ASSERT: seasonXp accrues when an active campaign (now within start/end) exists',
        () async {
      // ARRANGE - an 'all'-scope campaign spanning today
      await seedLeagueCampaign(
        fakeDb,
        teacherId: teacherId,
        scope: 'all',
        startDate: DateTime.now().subtract(const Duration(days: 5)),
        endDate: DateTime.now().add(const Duration(days: 5)),
      );

      // ACT
      await completeActivity();

      // ASSERT
      final roster = await rosterFor('student_1');
      expect(roster['xp'], 150);
      expect(roster['seasonXp'], 150);
    });

    test('ARRANGE-ACT-ASSERT: seasonXp does not accrue before the campaign startDate',
        () async {
      // ARRANGE - a campaign that hasn't started yet
      await seedLeagueCampaign(
        fakeDb,
        teacherId: teacherId,
        scope: 'all',
        startDate: DateTime.now().add(const Duration(days: 1)),
        endDate: DateTime.now().add(const Duration(days: 30)),
      );

      // ACT
      await completeActivity();

      // ASSERT - xp still accrues, seasonXp does not
      final roster = await rosterFor('student_1');
      expect(roster['xp'], 150);
      expect(roster['seasonXp'] ?? 0, 0);
    });

    test('ARRANGE-ACT-ASSERT: seasonXp does not accrue after the campaign endDate, even if the doc still exists',
        () async {
      // ARRANGE - a campaign whose window already closed (simulating the gap
      // before resetLeagueSeasons.ts's daily cron deletes the expired doc)
      await seedLeagueCampaign(
        fakeDb,
        teacherId: teacherId,
        scope: 'all',
        startDate: DateTime.now().subtract(const Duration(days: 30)),
        endDate: DateTime.now().subtract(const Duration(days: 1)),
      );

      // ACT
      await completeActivity();

      // ASSERT
      final roster = await rosterFor('student_1');
      expect(roster['xp'], 150);
      expect(roster['seasonXp'] ?? 0, 0);
    });

    test('ARRANGE-ACT-ASSERT: a single-scope campaign targeting a different group does not grant this student seasonXp',
        () async {
      // ARRANGE - campaign targets a different group than this student's
      await seedLeagueCampaign(
        fakeDb,
        teacherId: teacherId,
        scope: 'single',
        groupId: 'some_other_group',
        startDate: DateTime.now().subtract(const Duration(days: 1)),
        endDate: DateTime.now().add(const Duration(days: 1)),
      );

      // ACT
      await completeActivity();

      // ASSERT
      final roster = await rosterFor('student_1');
      expect(roster['xp'], 150);
      expect(roster['seasonXp'] ?? 0, 0);
    });

    test('ARRANGE-ACT-ASSERT: a single-scope campaign targeting this student\'s own group grants seasonXp',
        () async {
      // ARRANGE
      await seedLeagueCampaign(
        fakeDb,
        teacherId: teacherId,
        scope: 'single',
        groupId: groupId,
        startDate: DateTime.now().subtract(const Duration(days: 1)),
        endDate: DateTime.now().add(const Duration(days: 1)),
      );

      // ACT
      await completeActivity();

      // ASSERT
      final roster = await rosterFor('student_1');
      expect(roster['xp'], 150);
      expect(roster['seasonXp'], 150);
    });

    test('ARRANGE-ACT-ASSERT: an all-scope campaign grants seasonXp regardless of which of the teacher\'s groups the student is in',
        () async {
      // ARRANGE - a second group for the same teacher, with its own student
      const otherGroupId = 'group_2';
      await seedTeacherGroup(fakeDb,
          groupId: otherGroupId, teacherId: teacherId, groupCode: 'XYZ789');
      await seedStudent(fakeDb,
          studentId: 'student_2', studentName: 'Beto', groupId: otherGroupId);
      await seedLeagueCampaign(
        fakeDb,
        teacherId: teacherId,
        scope: 'all',
        startDate: DateTime.now().subtract(const Duration(days: 1)),
        endDate: DateTime.now().add(const Duration(days: 1)),
      );

      // ACT
      await database.saveActivityCompletion(
        studentId: 'student_2',
        activityId: 'activity_1',
        contentId: 'content_1',
        unitId: 'unit_1',
        score: 100,
        correctAnswers: 5,
        wrongAnswers: 0,
        xpBase: 100,
        bonusXP: 50,
      );

      // ASSERT
      final roster = await fakeDb
          .collection('teacherGroups')
          .doc(otherGroupId)
          .collection('students')
          .doc('student_2')
          .get();
      expect(roster.data()!['xp'], 150);
      expect(roster.data()!['seasonXp'], 150);
    });
  });
}
