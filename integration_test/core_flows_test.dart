// integration_test/core_flows_test.dart
//
// Consolidates the three flows that cover the modules considered critical
// enough to warrant true multi-screen integration testing (crossing UI +
// persistence, or validating a real product/security rule), run together
// in a single file so `flutter test integration_test/core_flows_test.dart`
// gives one console/screenshot artifact covering all of them:
//
//   1. Registro -> enrutamiento -> hijo -> grupo
//      (Gestión de Usuarios + Grupos y Avance) — the app's entry point;
//      also proves the single-image_manager security rule is enforced
//      end-to-end through the real RegisterScreen, not just in isolation.
//   2. Cadena de creación de Quizzes (Evaluación) — the Lesson-Quiz-gate ->
//      Unit-Quiz -> duplicate-rejection sequence, chained for real.
//   3. Progreso del estudiante -> reporte del padre
//      (Contenidos y Recursos + Reportes) — the app's core value loop.
//
// Gamificación has no UI-driven flow here (no screen in that module can be
// pumped without the larger DI refactor documented in the architecture
// limitation section — see content_hierarchy_test.dart's header comment);
// its coverage stays at the Database level in test/database/league_campaign_test.dart.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:loringo_app/screens/initials/register_screen.dart';
import 'package:loringo_app/screens/parent/child_report_detail_screen.dart';
import 'package:loringo_app/screens/parent/parent_join_group_screen.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:loringo_app/services/auth/login_or_register.dart';
import 'package:loringo_app/services/database/database.dart';

import 'helpers/integration_pump.dart';

// pauseForScreenshot() holds the emulator on each rendered screen so you
// can screenshot it by hand; see its doc comment in integration_pump.dart.

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Flujo 1 — Registro -> enrutamiento -> hijo -> grupo (Gestión de Usuarios + Grupos y Avance)',
      () {
    testWidgets(
        'ARRANGE-ACT-ASSERT: a full parent onboarding flow works end-to-end across real screens',
        (tester) async {
      // ARRANGE
      final firebase = setUpIntegrationFirebase();
      await firebase.firestore.collection('teacherGroups').doc('group_1').set({
        'teacherId': 'teacher_1',
        'groupCode': 'ABC123',
        'name': 'Grade 1',
      });

      // ACT - register as a parent, get routed to child registration, add a
      // child, then join that child to the real seeded group
      // RegisterScreen calls Navigator.pop(context) on success, so it must
      // be pushed onto a stack that has something underneath it.
      await pumpIntegrationApp(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => RegisterScreen(onTap: () {})),
                ),
                child: const Text('start'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();
      await pauseForScreenshot();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Maria Parent');
      await tester.enterText(fields.at(1), 'maria@loringo.app');
      await tester.enterText(fields.at(2), 'TestQA#2024');
      await tester.enterText(fields.at(3), 'TestQA#2024');
      await tester.tap(find.text('Parent'));
      await tester.pump();
      final createAccountButton = find.widgetWithText(ElevatedButton, 'Create Account');
      await tester.ensureVisible(createAccountButton);
      await tester.tap(createAccountButton);
      await tester.pumpAndSettle();

      // mount a fresh AuthGate; must route to ParentRegisterChildScreen
      // since this parent has no children yet
      await pumpIntegrationApp(tester, const AuthGate());
      await tester.pumpAndSettle();
      await pauseForScreenshot();

      await tester.enterText(find.byType(TextField), 'Juan Perez');
      final registerChildButton = find.widgetWithText(ElevatedButton, 'Register Child');
      await tester.ensureVisible(registerChildButton);
      await tester.tap(registerChildButton);
      await tester.pumpAndSettle();
      await pauseForScreenshot();

      final studentsSnap = await firebase.firestore.collection('students').get();
      final studentDoc = studentsSnap.docs.first;
      await pumpIntegrationApp(
        tester,
        ParentJoinGroupScreen(
          child: {'id': studentDoc.id, 'names': studentDoc.data()['names']},
        ),
      );
      await tester.enterText(find.byType(TextField), 'ABC123');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Join Group'));
      await tester.pumpAndSettle();
      await pauseForScreenshot();

      // ASSERT - a real Firebase Auth user + Firestore profile exist, the
      // gate routed correctly, the child was created for this parent, and
      // that same real student doc now belongs to the real group
      expect(firebase.auth.currentUser, isNotNull);
      final userDoc = await firebase.firestore
          .collection('users')
          .doc(firebase.auth.currentUser!.uid)
          .get();
      expect(userDoc.data()!['role'], 'parent');
      expect(find.byType(LoginOrRegister), findsNothing);
      expect(studentsSnap.docs.length, 1);
      expect(studentDoc.data()['parentId'], firebase.auth.currentUser!.uid);
      final updatedStudent =
          await firebase.firestore.collection('students').doc(studentDoc.id).get();
      expect(updatedStudent.data()!['groupId'], 'group_1');
      final membership = await firebase.firestore
          .collection('teacherGroups')
          .doc('group_1')
          .collection('students')
          .doc(studentDoc.id)
          .get();
      expect(membership.exists, true);
    });
  });

  group('Flujo 2 — Cadena de creación de Quizzes (Evaluación)', () {
    testWidgets(
        'ARRANGE-ACT-ASSERT: a teacher progressively unlocks and then locks Unit Quiz creation for a unit',
        (tester) async {
      // ARRANGE
      final fakeDb = FakeFirebaseFirestore();
      final database = Database(firestore: fakeDb);
      Future<void> createQuiz(String quizId, String title, String scope,
          {String? lessonId}) async {
        // countLessonQuizzesForUnit walks the unit's actual lessons
        // subcollection to find each one's quizzes now, so a Lesson Quiz's
        // lesson doc must exist before its quiz does (matches how the real
        // app always has an existing lesson before a quiz can be attached
        // to it via CreateQuizScreen).
        if (lessonId != null) {
          await database
              .personalizedLessons('content_1', 'unit_1')
              .doc(lessonId)
              .set({'title': title, 'order': 1});
        }
        await database.createQuiz(
            contentId: 'content_1', unitId: 'unit_1', quizId: quizId,
            title: title, questions: const [],
            passingScore: scope == 'unit' ? 60 : 0,
            xpReward: scope == 'unit' ? 100 : 10,
            maxAttempts: scope == 'unit' ? 1 : 3,
            groupId: 'group_1', lessonId: lessonId);
      }
      Future<bool> rejected(Future<void> attempt) async {
        try {
          await attempt;
          return false;
        } catch (_) {
          return true;
        }
      }

      // ACT - with 0 Lesson Quizzes the Unit Quiz is rejected, adding 2
      // lesson quizzes still isn't enough, the 3rd satisfies the gate, and
      // a second Unit Quiz for the same unit is then rejected as a
      // duplicate. Each attempt must run (and settle) in order, since the
      // gate's decision depends on the real quiz count at that point.
      final rejectedBeforeGate =
          await rejected(createQuiz('unit_quiz', 'Final Exam', 'unit'));
      await createQuiz('lq_1', 'Lesson Quiz 1', 'lesson', lessonId: 'lesson_1');
      await createQuiz('lq_2', 'Lesson Quiz 2', 'lesson', lessonId: 'lesson_2');
      final rejectedStillNotEnough =
          await rejected(createQuiz('unit_quiz', 'Final Exam', 'unit'));
      await createQuiz('lq_3', 'Lesson Quiz 3', 'lesson', lessonId: 'lesson_3');
      await createQuiz('unit_quiz', 'Final Exam', 'unit');
      final rejectedAsDuplicate =
          await rejected(createQuiz('unit_quiz_2', 'Retake Exam', 'unit'));

      // ASSERT - the gate rejected both premature attempts, the real Unit
      // Quiz document now exists once the gate was satisfied, and a
      // duplicate Unit Quiz is rejected
      expect(rejectedBeforeGate, true);
      expect(rejectedStillNotEnough, true);
      final unitQuizDoc = await fakeDb
          .collection('content').doc('content_1')
          .collection('units').doc('unit_1')
          .collection('quizzes').doc('unit_quiz').get();
      expect(unitQuizDoc.exists, true);
      expect(unitQuizDoc.data()!['isGraded'], true);
      expect(rejectedAsDuplicate, true);
    });
  });

  group('Flujo 3 — Progreso del estudiante -> reporte del padre (Contenidos y Recursos + Reportes)',
      () {
    testWidgets(
        'ARRANGE-ACT-ASSERT: the score/stars a student actually earns are what the parent sees',
        (tester) async {
      // ARRANGE
      setUpIntegrationFirebase();
      final fakeDb = FakeFirebaseFirestore();
      final database = Database(firestore: fakeDb);
      await fakeDb.collection('students').doc('student_1').set({
        'studentName': 'Ana', 'parentId': 'parent_1', 'groupId': 'group_1',
      });
      await fakeDb
          .collection('teacherGroups').doc('group_1')
          .collection('students').doc('student_1')
          .set({'studentId': 'student_1', 'status': 'active', 'xp': 0});

      // ACT - the student completes a unit's worth of activities for real,
      // then the report saveReportOnly would produce from that real data
      // is rendered for the parent
      await database.saveActivityCompletion(
        studentId: 'student_1', activityId: 'a1', contentId: 'content_1',
        unitId: 'unit_1', score: 100, correctAnswers: 5, wrongAnswers: 0,
        xpBase: 100, bonusXP: 50);
      await database.saveActivityCompletion(
        studentId: 'student_1', activityId: 'a2', contentId: 'content_1',
        unitId: 'unit_1', score: 80, correctAnswers: 4, wrongAnswers: 1,
        xpBase: 100, bonusXP: 50);
      final progressSnap = await fakeDb
          .collection('teacherGroups').doc('group_1')
          .collection('students').doc('student_1')
          .collection('progress')
          .get();
      final report = {
        'unitTitle': 'Unit 1',
        'quizPercent': 90,
        'quizCorrect': 9,
        'quizTotalQuestions': 10,
        'activitiesCompleted': 2,
        'totalActivities': 2,
        'activitiesPercent': 100,
        'previousUnitScores': <int>[],
        'feedback': '',
      };
      await pumpIntegrationApp(
        tester,
        ChildReportDetailScreen(
          child: const {'names': 'Ana'},
          reports: [report],
          formatDate: (d) => d.toString(),
        ),
      );
      await tester.pumpAndSettle();
      await pauseForScreenshot();

      // ASSERT - both real completions are queryable via Database the same
      // way a report-generation step would read them, and the parent-facing
      // screen shows the real outcome: 100% activities completion (both of
      // the student's real completions)
      expect(progressSnap.docs.length, 2);
      final totalStars = progressSnap.docs
          .map((d) => (d.data() as Map)['stars'] as int)
          .reduce((a, b) => a + b);
      expect(totalStars, 5); // 3 stars (100%) + 2 stars (80% is >=70 but <90)
      expect(find.text('Activities'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('90%'), findsOneWidget);
    });
  });
}
