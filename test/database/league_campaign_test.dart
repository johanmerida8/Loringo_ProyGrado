// test/database/league_campaign_test.dart
//
// Replaces test/student/student_league_test.dart, which reimplemented its
// own private `LeagueSystem` class (league tiers, XP-to-next-league math)
// that has no counterpart anywhere in lib/ — the real league tier/XP
// thresholds live in lib/screens/student/student_league_screen.dart and
// lib/screens/teacher/teacher_league_screen.dart as UI-only rendering
// logic, not a reusable class, and the actual persisted business rule is
// Database.saveLeagueCampaign/getLeagueCampaign (the per-teacher reward
// campaign config), tested here for real against FakeFirebaseFirestore.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/services/database/database.dart';

void main() {
  group('Database.saveLeagueCampaign/getLeagueCampaign - AAA Pattern', () {
    late FakeFirebaseFirestore fakeDb;
    late Database database;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      database = Database(firestore: fakeDb);
    });

    test('ARRANGE-ACT-ASSERT: an "all groups" campaign is saved with a null groupId',
        () async {
      // ARRANGE
      final start = DateTime(2026, 1, 1);
      final end = DateTime(2026, 1, 31);

      // ACT
      await database.saveLeagueCampaign(
        teacherId: 'teacher_1',
        scope: 'all',
        startDate: start,
        endDate: end,
        rewards: {'1': 'gold_medal', '2': 'silver_medal'},
      );
      final campaign = await database.getLeagueCampaign('teacher_1');

      // ASSERT
      final data = campaign.data() as Map<String, dynamic>;
      expect(data['scope'], 'all');
      expect(data['groupId'], null);
      expect(data['rewards'], {'1': 'gold_medal', '2': 'silver_medal'});
    });

    test('ARRANGE-ACT-ASSERT: a "single group" campaign preserves its groupId', () async {
      // ARRANGE & ACT
      await database.saveLeagueCampaign(
        teacherId: 'teacher_2',
        scope: 'single',
        groupId: 'group_42',
        rewards: {'1': 'trophy'},
      );
      final campaign = await database.getLeagueCampaign('teacher_2');

      // ASSERT
      final data = campaign.data() as Map<String, dynamic>;
      expect(data['scope'], 'single');
      expect(data['groupId'], 'group_42');
    });

    test('ARRANGE-ACT-ASSERT: an invalid scope value is rejected', () async {
      // ARRANGE & ACT & ASSERT
      expect(
        () => database.saveLeagueCampaign(
          teacherId: 'teacher_3',
          scope: 'invalid_scope',
          rewards: const {},
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('ARRANGE-ACT-ASSERT: scope "single" without a groupId is rejected', () async {
      // ARRANGE & ACT & ASSERT
      expect(
        () => database.saveLeagueCampaign(
          teacherId: 'teacher_4',
          scope: 'single',
          rewards: const {},
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('ARRANGE-ACT-ASSERT: saving a campaign again for the same teacher overwrites the previous one',
        () async {
      // ARRANGE - an existing "all" campaign
      await database.saveLeagueCampaign(
        teacherId: 'teacher_5',
        scope: 'all',
        rewards: {'1': 'bronze'},
      );

      // ACT - the teacher switches to a single-group campaign
      await database.saveLeagueCampaign(
        teacherId: 'teacher_5',
        scope: 'single',
        groupId: 'group_9',
        rewards: {'1': 'gold'},
      );
      final campaign = await database.getLeagueCampaign('teacher_5');

      // ASSERT
      final data = campaign.data() as Map<String, dynamic>;
      expect(data['scope'], 'single');
      expect(data['groupId'], 'group_9');
      expect(data['rewards'], {'1': 'gold'});
    });
  });
}
