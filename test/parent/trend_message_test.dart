// test/parent/trend_message_test.dart
import 'package:flutter_test/flutter_test.dart';

/// ============================================
/// TREND MESSAGE - Comparación entre unidades
/// Muestra mensaje según mejora o empeoramiento
/// ============================================

class TrendMessageGenerator {
  static String getTrendMessage(List<int> previousScores, int currentScore) {
    if (previousScores.isEmpty) {
      return 'First unit completed! Complete more units to see your progress trend.';
    }
    
    final lastScore = previousScores.last;
    final difference = currentScore - lastScore;
    
    if (difference >= 10) {
      return 'Excellent improvement! +$difference% compared to previous unit.';
    }
    if (difference >= 5) {
      return 'Good progress! +$difference% improvement. Keep it up!';
    }
    if (difference > 0) {
      return 'Slight improvement of +$difference%. Consistency is key!';
    }
    if (difference == 0) {
      return 'Maintained the same score. Try some extra practice!';
    }
    return 'Score decreased by ${difference.abs()}%. Review the material again!';
  }

  static String getPerformanceLabel(int percent) {
    if (percent >= 90) return 'Excellent';
    if (percent >= 70) return 'Good';
    if (percent >= 50) return 'Fair';
    return 'Needs Improvement';
  }
}

void main() {
  group('Trend Message Logic - AAA Pattern', () {

    // ==========================================
    // PRUEBA 1: Primera unidad (sin historial)
    // ==========================================
    test('ARRANGE-ACT-ASSERT: First unit - no previous scores', () {
      // ARRANGE
      const List<int> previousScores = [];
      const int currentScore = 85;

      // ACT
      final message = TrendMessageGenerator.getTrendMessage(previousScores, currentScore);

      // ASSERT
      expect(message, 'First unit completed! Complete more units to see your progress trend.');
    });

    // ==========================================
    // PRUEBA 2: Mejora excelente (≥10%)
    // ==========================================
    test('ARRANGE-ACT-ASSERT: Excellent improvement of 10% or more', () {
      // ARRANGE - Pasó de 70% a 85% (+15%)
      const List<int> previousScores = [70];
      const int currentScore = 85;

      // ACT
      final message = TrendMessageGenerator.getTrendMessage(previousScores, currentScore);

      // ASSERT
      expect(message, 'Excellent improvement! +15% compared to previous unit.');
    });

    // ==========================================
    // PRUEBA 3: Buena mejora (5-9%)
    // ==========================================
    test('ARRANGE-ACT-ASSERT: Good improvement of 5-9%', () {
      // ARRANGE - Pasó de 75% a 82% (+7%)
      const List<int> previousScores = [75];
      const int currentScore = 82;

      // ACT
      final message = TrendMessageGenerator.getTrendMessage(previousScores, currentScore);

      // ASSERT
      expect(message, 'Good progress! +7% improvement. Keep it up!');
    });

    // ==========================================
    // PRUEBA 4: Mejora ligera (1-4%)
    // ==========================================
    test('ARRANGE-ACT-ASSERT: Slight improvement of 1-4%', () {
      // ARRANGE - Pasó de 80% a 83% (+3%)
      const List<int> previousScores = [80];
      const int currentScore = 83;

      // ACT
      final message = TrendMessageGenerator.getTrendMessage(previousScores, currentScore);

      // ASSERT
      expect(message, 'Slight improvement of +3%. Consistency is key!');
    });

    // ==========================================
    // PRUEBA 5: Mismo puntaje (0%)
    // ==========================================
    test('ARRANGE-ACT-ASSERT: Same score as previous unit', () {
      // ARRANGE - Se mantuvo en 75%
      const List<int> previousScores = [75];
      const int currentScore = 75;

      // ACT
      final message = TrendMessageGenerator.getTrendMessage(previousScores, currentScore);

      // ASSERT
      expect(message, 'Maintained the same score. Try some extra practice!');
    });

    // ==========================================
    // PRUEBA 6: Disminución de puntaje
    // ==========================================
    test('ARRANGE-ACT-ASSERT: Score decreased from previous unit', () {
      // ARRANGE - Bajó de 85% a 70% (-15%)
      const List<int> previousScores = [85];
      const int currentScore = 70;

      // ACT
      final message = TrendMessageGenerator.getTrendMessage(previousScores, currentScore);

      // ASSERT
      expect(message, 'Score decreased by 15%. Review the material again!');
    });

    // ==========================================
    // PRUEBA 7: Etiquetas de rendimiento
    // ==========================================
    test('ARRANGE-ACT-ASSERT: Performance labels based on score', () {
      // ARRANGE - Diferentes porcentajes
      
      // ACT & ASSERT
      expect(TrendMessageGenerator.getPerformanceLabel(95), 'Excellent');
      expect(TrendMessageGenerator.getPerformanceLabel(80), 'Good');
      expect(TrendMessageGenerator.getPerformanceLabel(60), 'Fair');
      expect(TrendMessageGenerator.getPerformanceLabel(40), 'Needs Improvement');
    });
  });
}