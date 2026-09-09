// test/database/content_hierarchy_test.dart
//
// Replaces test/teacher/content/{content,unit,lesson,activity,task}_
// validation_test.dart. All five reimplemented their own private
// *Validator classes (title length >= 3, numeric order >= 1, XP-to-
// difficulty mapping, etc.) with rules that have no counterpart in lib/ —
// those checks are inline TextFormField validators inside
// create_content_screen.dart/create_unit_screen.dart/etc., and every one
// of those screens builds Database() and opens a Firestore
// StreamBuilder/FutureBuilder during initState(), so the real screens
// can't be pumped in a test without a working Firestore connection (no
// constructor injection point exists on the widgets themselves, unlike
// Database, which this suite already made injectable).
//
// What IS real, reachable, and worth testing here is the persistence layer
// every one of those screens' submit handlers calls into: Database's
// content/unit/lesson/activity/task CRUD, including the delete-time
// sibling-reorder behavior and the activity prerequisite chain
// (_relinkActivityChain) — real business logic with no fake-test coverage
// before this suite.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/services/database/database.dart';

void main() {
  group('Database content hierarchy CRUD - AAA Pattern', () {
    late FakeFirebaseFirestore fakeDb;
    late Database database;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      database = Database(firestore: fakeDb);
    });

    test('ARRANGE-ACT-ASSERT: creating content persists it assigned to its group', () async {
      // ARRANGE & ACT
      await database.createPersonalizedContent(
        contentId: 'content_1',
        title: 'Present Tense Verbs',
        description: 'Learn how to conjugate regular verbs',
        ageGroup: '7-8 years',
        order: 1,
        teacherId: 'teacher_1',
        groupId: 'group_1',
      );

      // ASSERT
      final doc = await fakeDb.collection('content').doc('content_1').get();
      expect(doc.data()!['title'], 'Present Tense Verbs');
      expect(doc.data()!['assignedTo'], ['group_1']);
      expect(doc.data()!['archived'], false);
    });

    test('ARRANGE-ACT-ASSERT: deleting content shifts the order of later siblings down by one',
        () async {
      // ARRANGE - three content items in order 1, 2, 3
      for (final entry in [(id: 'c1', order: 1), (id: 'c2', order: 2), (id: 'c3', order: 3)]) {
        await database.createPersonalizedContent(
          contentId: entry.id,
          title: 'Content ${entry.order}',
          description: 'desc',
          ageGroup: '7-8 years',
          order: entry.order,
          teacherId: 'teacher_1',
          groupId: 'group_1',
        );
      }

      // ACT - delete the middle one (order 2)
      await database.deletePersonalizedContent('c2');

      // ASSERT - c3's order shifts from 3 to 2, c1 is untouched, c2 is gone
      final c1 = await fakeDb.collection('content').doc('c1').get();
      final c2 = await fakeDb.collection('content').doc('c2').get();
      final c3 = await fakeDb.collection('content').doc('c3').get();
      expect(c1.data()!['order'], 1);
      expect(c2.exists, false);
      expect(c3.data()!['order'], 2);
    });

    test('ARRANGE-ACT-ASSERT: creating a unit persists it under its content', () async {
      // ARRANGE & ACT
      await database.createPersonalizedUnit(
        groupId: 'group_1',
        contentId: 'content_1',
        unitId: 'unit_1',
        title: 'Introduction to Numbers',
        order: 1,
      );

      // ASSERT
      final doc = await fakeDb
          .collection('content')
          .doc('content_1')
          .collection('units')
          .doc('unit_1')
          .get();
      expect(doc.data()!['title'], 'Introduction to Numbers');
      expect(doc.data()!['order'], 1);
    });

    test('ARRANGE-ACT-ASSERT: deleting a unit shifts later sibling units down by one', () async {
      // ARRANGE
      await database.createPersonalizedUnit(
        groupId: 'g', contentId: 'content_1', unitId: 'u1', title: 'Unit 1', order: 1);
      await database.createPersonalizedUnit(
        groupId: 'g', contentId: 'content_1', unitId: 'u2', title: 'Unit 2', order: 2);

      // ACT
      await database.deletePersonalizedUnit('g', 'content_1', 'u1');

      // ASSERT
      final unitsCol = fakeDb.collection('content').doc('content_1').collection('units');
      final u2 = await unitsCol.doc('u2').get();
      expect(u2.data()!['order'], 1);
    });

    test('ARRANGE-ACT-ASSERT: creating a lesson persists it under its unit', () async {
      // ARRANGE & ACT
      await database.createPersonalizedLesson(
        groupId: 'g',
        contentId: 'content_1',
        unitId: 'unit_1',
        lessonId: 'lesson_1',
        title: 'Past Tense Basics',
        order: 1,
      );

      // ASSERT
      final doc = await fakeDb
          .collection('content')
          .doc('content_1')
          .collection('units')
          .doc('unit_1')
          .collection('lessons')
          .doc('lesson_1')
          .get();
      expect(doc.data()!['title'], 'Past Tense Basics');
    });

    test('ARRANGE-ACT-ASSERT: creating the first activity in a lesson gets no prerequisite',
        () async {
      // ARRANGE & ACT
      await database.createPersonalizedActivity(
        groupId: 'g',
        contentId: 'content_1',
        unitId: 'unit_1',
        lessonId: 'lesson_1',
        activityId: 'activity_1',
        title: 'Listening Exercise',
        order: 1,
      );

      // ASSERT
      final doc = await fakeDb
          .collection('content')
          .doc('content_1')
          .collection('units')
          .doc('unit_1')
          .collection('lessons')
          .doc('lesson_1')
          .collection('activities')
          .doc('activity_1')
          .get();
      expect(doc.data()!['requiredActivityId'], null);
      expect(doc.data()!['xpBase'], 100); // default when not provided
      expect(doc.data()!['difficulty'], 'easy'); // default when not provided
    });

    test('ARRANGE-ACT-ASSERT: a second activity created after the first requires the first to be completed',
        () async {
      // ARRANGE
      await database.createPersonalizedActivity(
        groupId: 'g',
        contentId: 'content_1',
        unitId: 'unit_1',
        lessonId: 'lesson_1',
        activityId: 'activity_1',
        title: 'First',
        order: 1,
      );

      // ACT
      await database.createPersonalizedActivity(
        groupId: 'g',
        contentId: 'content_1',
        unitId: 'unit_1',
        lessonId: 'lesson_1',
        activityId: 'activity_2',
        title: 'Second',
        order: 2,
      );

      // ASSERT - the chain is derived purely from order, not manually set
      final activitiesCol = fakeDb
          .collection('content').doc('content_1')
          .collection('units').doc('unit_1')
          .collection('lessons').doc('lesson_1')
          .collection('activities');
      final activity2 = await activitiesCol.doc('activity_2').get();
      expect(activity2.data()!['requiredActivityId'], 'activity_1');
    });

    test('ARRANGE-ACT-ASSERT: reordering activities relinks the whole prerequisite chain to match the new order',
        () async {
      // ARRANGE - two activities, 1 then 2
      await database.createPersonalizedActivity(
        groupId: 'g', contentId: 'c', unitId: 'u', lessonId: 'l',
        activityId: 'a1', title: 'A1', order: 1);
      await database.createPersonalizedActivity(
        groupId: 'g', contentId: 'c', unitId: 'u', lessonId: 'l',
        activityId: 'a2', title: 'A2', order: 2);

      // ACT - teacher reorders so a2 now comes first
      await database.reorderPersonalizedActivities(
        contentId: 'c', unitId: 'u', lessonId: 'l',
        orderedActivityIds: ['a2', 'a1'],
      );

      // ASSERT - a2 is now the chain's entry point (no prerequisite), a1 now requires a2
      final activitiesCol = fakeDb
          .collection('content').doc('c')
          .collection('units').doc('u')
          .collection('lessons').doc('l')
          .collection('activities');
      final a1 = await activitiesCol.doc('a1').get();
      final a2 = await activitiesCol.doc('a2').get();
      expect(a2.data()!['order'], 1);
      expect(a2.data()!['requiredActivityId'], null);
      expect(a1.data()!['order'], 2);
      expect(a1.data()!['requiredActivityId'], 'a2');
    });

    test('ARRANGE-ACT-ASSERT: deleting the first activity relinks the second to become the new entry point',
        () async {
      // ARRANGE - a1 (order 1) -> a2 (order 2, requires a1) -> a3 (order 3, requires a2)
      await database.createPersonalizedActivity(
        groupId: 'g', contentId: 'c', unitId: 'u', lessonId: 'l',
        activityId: 'a1', title: 'A1', order: 1);
      await database.createPersonalizedActivity(
        groupId: 'g', contentId: 'c', unitId: 'u', lessonId: 'l',
        activityId: 'a2', title: 'A2', order: 2);
      await database.createPersonalizedActivity(
        groupId: 'g', contentId: 'c', unitId: 'u', lessonId: 'l',
        activityId: 'a3', title: 'A3', order: 3);

      // ACT
      await database.deletePersonalizedActivity('g', 'c', 'u', 'l', 'a1');

      // ASSERT - a2 becomes the entry point, a3 now requires a2 directly (not the deleted a1)
      final activitiesCol = fakeDb
          .collection('content').doc('c')
          .collection('units').doc('u')
          .collection('lessons').doc('l')
          .collection('activities');
      final a2 = await activitiesCol.doc('a2').get();
      final a3 = await activitiesCol.doc('a3').get();
      expect(a2.data()!['order'], 1);
      expect(a2.data()!['requiredActivityId'], null);
      expect(a3.data()!['order'], 2);
      expect(a3.data()!['requiredActivityId'], 'a2');
    });

    test('ARRANGE-ACT-ASSERT: creating a task persists its type-specific data under its activity',
        () async {
      // ARRANGE & ACT
      await database.createPersonalizedTask(
        groupId: 'g',
        contentId: 'c',
        unitId: 'u',
        lessonId: 'l',
        activityId: 'a1',
        taskId: 'task_1',
        type: 'match',
        title: 'Match Colors',
        question: 'Match the English word to its translation',
        order: 1,
        data: {
          'pairs': [
            {'english': 'Red', 'translated': 'Rojo'},
            {'english': 'Blue', 'translated': 'Azul'},
          ],
        },
      );

      // ASSERT
      final doc = await fakeDb
          .collection('content').doc('c')
          .collection('units').doc('u')
          .collection('lessons').doc('l')
          .collection('activities').doc('a1')
          .collection('tasks').doc('task_1')
          .get();
      expect(doc.data()!['type'], 'match');
      expect((doc.data()!['data'] as Map)['pairs'], hasLength(2));
    });
  });
}
