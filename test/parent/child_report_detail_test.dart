// test/parent/child_report_detail_test.dart
//
// Replaces test/parent/report_logic_test.dart, which reimplemented a
// `ReportCalculator` including a `getStars` and `getScoreMessage` API that
// has NO counterpart anywhere in lib/ — child_report_detail_screen.dart
// (the real screen this was meant to mirror) never renders a star rating
// or a canned "Excellent! Outstanding performance!"-style message; a
// grep across lib/screens/parent/ for that logic finds nothing. What IS
// real is the quiz score color threshold (>=80 green, >=60 amber,
// otherwise orange) and the quiz/activities percent display, both inline
// in _buildReportCard. This screen takes its data via constructor
// parameters (child/reports/formatDate) rather than fetching internally,
// so — unlike most other teacher/admin screens in this app — it can be
// pumped directly with fake report data, no Firestore involved at all.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/screens/parent/child_report_detail_screen.dart';

import '../helpers/pump_app.dart';

void main() {
  group('ChildReportDetailScreen - AAA Pattern', () {
    Map<String, dynamic> buildReport({
      required String unitTitle,
      required int quizPercent,
      required int quizCorrect,
      required int quizTotal,
      required int activitiesPercent,
    }) {
      return {
        'unitTitle': unitTitle,
        'quizPercent': quizPercent,
        'quizCorrect': quizCorrect,
        'quizTotalQuestions': quizTotal,
        'activitiesCompleted': 0,
        'totalActivities': 0,
        'activitiesPercent': activitiesPercent,
        'previousUnitScores': <int>[],
        'feedback': '',
      };
    }

    testWidgets(
        'ARRANGE-ACT-ASSERT: a report with quizPercent >= 80 renders its score in green',
        (tester) async {
      // ARRANGE
      final report = buildReport(
        unitTitle: 'Unit 1', quizPercent: 90, quizCorrect: 9, quizTotal: 10,
        activitiesPercent: 100);

      // ACT - the most-recent report (index 0) starts expanded by default
      await pumpApp(
        tester,
        ChildReportDetailScreen(
          child: const {'names': 'Laura'},
          reports: [report],
          formatDate: (d) => d.toString(),
        ),
      );
      await tester.pumpAndSettle();

      // ASSERT
      expect(find.text('Quiz Score'), findsOneWidget);
      expect(find.text('90%'), findsOneWidget);
      expect(find.text('9✓ / 10'), findsOneWidget);
      final scoreText = tester.widget<Text>(find.text('90%'));
      expect(scoreText.style?.color, const Color(0xFF4CAF50));
    });

    testWidgets(
        'ARRANGE-ACT-ASSERT: a report with quizPercent between 60 and 79 renders its score in amber',
        (tester) async {
      // ARRANGE
      final report = buildReport(
        unitTitle: 'Unit 2', quizPercent: 65, quizCorrect: 6, quizTotal: 10,
        activitiesPercent: 50);

      // ACT
      await pumpApp(
        tester,
        ChildReportDetailScreen(
          child: const {'names': 'Laura'},
          reports: [report],
          formatDate: (d) => d.toString(),
        ),
      );
      await tester.pumpAndSettle();

      // ASSERT
      final scoreText = tester.widget<Text>(find.text('65%'));
      expect(scoreText.style?.color, const Color(0xFFFFC107));
    });

    testWidgets(
        'ARRANGE-ACT-ASSERT: a report with quizPercent below 60 renders its score in orange',
        (tester) async {
      // ARRANGE
      final report = buildReport(
        unitTitle: 'Unit 3', quizPercent: 40, quizCorrect: 4, quizTotal: 10,
        activitiesPercent: 20);

      // ACT
      await pumpApp(
        tester,
        ChildReportDetailScreen(
          child: const {'names': 'Laura'},
          reports: [report],
          formatDate: (d) => d.toString(),
        ),
      );
      await tester.pumpAndSettle();

      // ASSERT
      final scoreText = tester.widget<Text>(find.text('40%'));
      expect(scoreText.style?.color, const Color(0xFFFF7043));
    });

    testWidgets('ARRANGE-ACT-ASSERT: an empty reports list shows the empty state, not a crash',
        (tester) async {
      // ARRANGE & ACT
      await pumpApp(
        tester,
        ChildReportDetailScreen(
          child: const {'names': 'Laura'},
          reports: const [],
          formatDate: (d) => d.toString(),
        ),
      );
      await tester.pumpAndSettle();

      // ASSERT
      expect(find.text('Quiz Score'), findsNothing);
    });
  });
}
