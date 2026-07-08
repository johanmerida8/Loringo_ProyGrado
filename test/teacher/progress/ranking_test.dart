// test/teacher/progress/ranking_test.dart
import 'package:flutter_test/flutter_test.dart';

class StudentRanking {
  static List<Map<String, dynamic>> sortByScore(List<Map<String, dynamic>> students) {
    return List.from(students)
      ..sort((a, b) => (b['overallScore'] as int).compareTo(a['overallScore'] as int));
  }

  static Map<int, List<Map<String, dynamic>>> groupByScoreRange(List<Map<String, dynamic>> students) {
    final Map<int, List<Map<String, dynamic>>> ranges = {
      90: [],
      70: [],
      50: [],
      0: [],
    };
    
    for (final student in students) {
      final score = student['overallScore'] as int;
      if (score >= 90) {
        ranges[90]!.add(student);
      } else if (score >= 70) {
        ranges[70]!.add(student);
      } else if (score >= 50) {
        ranges[50]!.add(student);
      } else {
        ranges[0]!.add(student);
      }
    }
    return ranges;
  }

  static String getRankEmoji(int rank) {
    if (rank == 1) return '🥇';
    if (rank == 2) return '🥈';
    if (rank == 3) return '🥉';
    return '$rank';
  }

  static String getPerformanceLabel(int score) {
    if (score >= 90) return 'Excellent';
    if (score >= 70) return 'Good';
    if (score >= 50) return 'Fair';
    return 'Needs Improvement';
  }
}

void main() {
  group('Student Ranking Logic', () {
    final students = [
      {'name': 'Alice', 'overallScore': 95},
      {'name': 'Bob', 'overallScore': 82},
      {'name': 'Charlie', 'overallScore': 68},
      {'name': 'Diana', 'overallScore': 45},
    ];

    test('ARRANGE-ACT-ASSERT: Sort students by score descending', () {
      // ARRANGE - Students list already defined
      
      // ACT
      final sorted = StudentRanking.sortByScore(students);
      
      // ASSERT
      expect(sorted[0]['name'], 'Alice');
      expect(sorted[1]['name'], 'Bob');
      expect(sorted[2]['name'], 'Charlie');
      expect(sorted[3]['name'], 'Diana');
    });

    test('ARRANGE-ACT-ASSERT: Group students by score ranges', () {
      // ARRANGE - Students list already defined
      
      // ACT
      final grouped = StudentRanking.groupByScoreRange(students);
      
      // ASSERT
      expect(grouped[90]!.length, 1); // Alice (95)
      expect(grouped[70]!.length, 1); // Bob (82)
      expect(grouped[50]!.length, 1); // Charlie (68)
      expect(grouped[0]!.length, 1);  // Diana (45)
    });

    test('ARRANGE-ACT-ASSERT: Rank emoji for top 3 positions', () {
      // ARRANGE - Different rank positions
      
      // ACT & ASSERT
      expect(StudentRanking.getRankEmoji(1), '🥇');
      expect(StudentRanking.getRankEmoji(2), '🥈');
      expect(StudentRanking.getRankEmoji(3), '🥉');
      expect(StudentRanking.getRankEmoji(4), '4');
      expect(StudentRanking.getRankEmoji(10), '10');
    });

    test('ARRANGE-ACT-ASSERT: Performance labels based on score', () {
      // ARRANGE - Different score values
      
      // ACT & ASSERT
      expect(StudentRanking.getPerformanceLabel(95), 'Excellent');
      expect(StudentRanking.getPerformanceLabel(85), 'Good');
      expect(StudentRanking.getPerformanceLabel(80), 'Good');
      expect(StudentRanking.getPerformanceLabel(70), 'Good');
      expect(StudentRanking.getPerformanceLabel(68), 'Fair');
      expect(StudentRanking.getPerformanceLabel(60), 'Fair');
      expect(StudentRanking.getPerformanceLabel(50), 'Fair');
      expect(StudentRanking.getPerformanceLabel(45), 'Needs Improvement');
      expect(StudentRanking.getPerformanceLabel(30), 'Needs Improvement');
    });
  });
}