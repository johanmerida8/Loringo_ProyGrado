// test/database/child_activity_status_test.dart
//
// New coverage for Database.getChildActivityStatusList — the
// turn-in-status classification (completed/past_due/not_open_yet/
// due_today/due_tomorrow/later) that parent_child_activity_status_screen
// .dart renders, and previously had zero test coverage anywhere. Built on
// top of the real content-hierarchy CRUD already exercised in
// content_hierarchy_test.dart, so every fixture here is created through
// the same Database methods a teacher's real actions would call, not
// hand-built Firestore documents.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/services/database/database.dart';

import '../helpers/firestore_seed.dart';

void main() {
  group('Database.getChildActivityStatusList - AAA Pattern', () {
    late FakeFirebaseFirestore fakeDb;
    late Database database;

    setUp(() async {
      fakeDb = FakeFirebaseFirestore();
      database = Database(firestore: fakeDb);
      await seedStudent(
        fakeDb, studentId: 'student_1', studentName: 'Ana', groupId: 'group_1');
      await database.createPersonalizedContent(
        contentId: 'content_1',
        title: 'Unit Content',
        description: 'desc',
        ageGroup: '7-8 years',
        order: 1,
        teacherId: 'teacher_1',
        groupId: 'group_1',
      );
      await database.createPersonalizedUnit(
        groupId: 'group_1', contentId: 'content_1', unitId: 'unit_1',
        title: 'Unit 1', order: 1);
      await database.createPersonalizedLesson(
        groupId: 'group_1', contentId: 'content_1', unitId: 'unit_1',
        lessonId: 'lesson_1', title: 'Lesson 1', order: 1);
    });

    Future<Map<String, dynamic>> statusFor(String activityId) async {
      final list = await database.getChildActivityStatusList(
        groupId: 'group_1', studentId: 'student_1');
      return list.firstWhere((item) => item['activityId'] == activityId);
    }

    test('ARRANGE-ACT-ASSERT: a completed activity is classified as completed, with its real stars',
        () async {
      // ARRANGE
      await database.createPersonalizedActivity(
        groupId: 'group_1', contentId: 'content_1', unitId: 'unit_1',
        lessonId: 'lesson_1', activityId: 'a1', title: 'A1', order: 1);
      await database.saveActivityCompletion(
        studentId: 'student_1', activityId: 'a1', contentId: 'content_1',
        unitId: 'unit_1', score: 95, correctAnswers: 5, wrongAnswers: 0,
        xpBase: 100, bonusXP: 50);

      // ACT
      final status = await statusFor('a1');

      // ASSERT
      expect(status['status'], 'completed');
      expect(status['stars'], 3);
    });

    test('ARRANGE-ACT-ASSERT: an incomplete activity past its dueDate is past_due', () async {
      // ARRANGE
      await database.createPersonalizedActivity(
        groupId: 'group_1', contentId: 'content_1', unitId: 'unit_1',
        lessonId: 'lesson_1', activityId: 'a1', title: 'A1', order: 1,
        dueDate: DateTime.now().subtract(const Duration(days: 2)));

      // ACT
      final status = await statusFor('a1');

      // ASSERT
      expect(status['status'], 'past_due');
    });

    test('ARRANGE-ACT-ASSERT: an activity scheduled in the future is not_open_yet with reason scheduled',
        () async {
      // ARRANGE
      await database.createPersonalizedActivity(
        groupId: 'group_1', contentId: 'content_1', unitId: 'unit_1',
        lessonId: 'lesson_1', activityId: 'a1', title: 'A1', order: 1,
        scheduledDate: DateTime.now().add(const Duration(days: 3)));

      // ACT
      final status = await statusFor('a1');

      // ASSERT
      expect(status['status'], 'not_open_yet');
      expect(status['notOpenReason'], 'scheduled');
    });

    test('ARRANGE-ACT-ASSERT: a second activity is not_open_yet/locked until the first (its prerequisite) is completed',
        () async {
      // ARRANGE - a1 then a2, a2's requiredActivityId is derived as a1 (see content_hierarchy_test.dart)
      await database.createPersonalizedActivity(
        groupId: 'group_1', contentId: 'content_1', unitId: 'unit_1',
        lessonId: 'lesson_1', activityId: 'a1', title: 'A1', order: 1);
      await database.createPersonalizedActivity(
        groupId: 'group_1', contentId: 'content_1', unitId: 'unit_1',
        lessonId: 'lesson_1', activityId: 'a2', title: 'A2', order: 2);

      // ACT - a1 is left incomplete
      final status = await statusFor('a2');

      // ASSERT
      expect(status['status'], 'not_open_yet');
      expect(status['notOpenReason'], 'locked');
    });

    test('ARRANGE-ACT-ASSERT: once its prerequisite is completed, the next activity becomes reachable (later, with no due date)',
        () async {
      // ARRANGE
      await database.createPersonalizedActivity(
        groupId: 'group_1', contentId: 'content_1', unitId: 'unit_1',
        lessonId: 'lesson_1', activityId: 'a1', title: 'A1', order: 1);
      await database.createPersonalizedActivity(
        groupId: 'group_1', contentId: 'content_1', unitId: 'unit_1',
        lessonId: 'lesson_1', activityId: 'a2', title: 'A2', order: 2);
      await database.saveActivityCompletion(
        studentId: 'student_1', activityId: 'a1', contentId: 'content_1',
        unitId: 'unit_1', score: 100, correctAnswers: 5, wrongAnswers: 0,
        xpBase: 100, bonusXP: 50);

      // ACT
      final status = await statusFor('a2');

      // ASSERT - unlocked now, no dueDate set, so it falls into 'later'
      expect(status['status'], 'later');
    });

    test('ARRANGE-ACT-ASSERT: an activity due today is due_today', () async {
      // ARRANGE
      final now = DateTime.now();
      await database.createPersonalizedActivity(
        groupId: 'group_1', contentId: 'content_1', unitId: 'unit_1',
        lessonId: 'lesson_1', activityId: 'a1', title: 'A1', order: 1,
        dueDate: DateTime(now.year, now.month, now.day, 23, 59));

      // ACT
      final status = await statusFor('a1');

      // ASSERT
      expect(status['status'], 'due_today');
    });
  });
}
