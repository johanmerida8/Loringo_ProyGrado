import 'package:flutter_test/flutter_test.dart';

/// ============================================
/// LEAGUE SYSTEM - Gamificación
/// Los estudiantes ganan XP al completar actividades y quizzes
/// Acumulan XP para subir de liga (Starter → Diamond)
/// ============================================

class LeagueSystem {
  static const List<Map<String, dynamic>> tiers = [
    {'name': 'Starter', 'min': 0, 'max': 200},
    {'name': 'Bronze', 'min': 200, 'max': 500},
    {'name': 'Silver', 'min': 500, 'max': 1000},
    {'name': 'Gold', 'min': 1000, 'max': 2000},
    {'name': 'Platinum', 'min': 2000, 'max': 4000},
    {'name': 'Diamond', 'min': 4000, 'max': 999999},
  ];

  static String getLeague(int xp) {
    for (final tier in tiers) {
      if (xp >= tier['min'] && xp < tier['max']) {
        return tier['name'];
      }
    }
    return 'Diamond';
  }

  static int getXpToNextLeague(int xp) {
    final currentLeague = getLeague(xp);
    for (final tier in tiers) {
      if (tier['name'] == currentLeague) {
        final max = tier['max'] as int;
        if (max == 999999) return 0;
        return max - xp;
      }
    }
    return 0;
  }

  static double getProgressToNextLeague(int xp) {
    final currentLeague = getLeague(xp);
    for (final tier in tiers) {
      if (tier['name'] == currentLeague) {
        final min = tier['min'] as int;
        final max = tier['max'] as int;
        if (max == 999999) return 1.0;
        return ((xp - min) / (max - min)).clamp(0.0, 1.0);
      }
    }
    return 0.0;
  }

  /// Calcula XP ganado al completar una actividad
  static int calculateActivityXp(int correctAnswers, int totalTasks, int xpBase, int bonusXP) {
    final baseXp = (xpBase * correctAnswers / totalTasks).round();
    final allCorrect = correctAnswers == totalTasks;
    final bonus = allCorrect ? bonusXP : 0;
    return baseXp + bonus;
  }

  /// Calcula XP ganado al completar un Lesson Quiz (práctica)
  static int calculateLessonQuizXp(int correctAnswers, int totalQuestions, int xpReward, bool wasCompletedBefore) {
    if (wasCompletedBefore) return 0; // Solo primera vez da XP
    final percentage = (correctAnswers / totalQuestions * 100).round();
    return (xpReward * percentage / 100).round();
  }

  /// Calcula XP ganado al completar un Unit Quiz (examen)
  static int calculateUnitQuizXp(int correctAnswers, int totalQuestions, int maxXp, bool passed) {
    if (!passed) return 0; // Solo si aprueba
    return (correctAnswers * maxXp / totalQuestions).round();
  }
}

void main() {
  group('Student League System - Gamification (AAA Pattern)', () {

    // ==========================================
    // PRUEBA 1: Estudiante gana XP y sube de liga
    // ==========================================
    test('ARRANGE-ACT-ASSERT: Student gains XP and moves up leagues', () {
      // ARRANGE - Estudiante comienza en Starter con 0 XP
      int currentXP = 0;
      
      // ACT - Completa actividades y gana XP
      expect(LeagueSystem.getLeague(currentXP), 'Starter');
      
      // Gana 100 XP de una actividad
      currentXP += 100;
      expect(LeagueSystem.getLeague(currentXP), 'Starter');
      
      // Gana 150 XP más (total 250) → Sube a Bronze
      currentXP += 150;
      expect(LeagueSystem.getLeague(currentXP), 'Bronze');
      
      // Gana 300 XP más (total 550) → Sube a Silver
      currentXP += 300;
      expect(LeagueSystem.getLeague(currentXP), 'Silver');
      
      // Gana 500 XP más (total 1050) → Sube a Gold
      currentXP += 500;
      expect(LeagueSystem.getLeague(currentXP), 'Gold');
      
      // Gana 1000 XP más (total 2050) → Sube a Platinum
      currentXP += 1000;
      expect(LeagueSystem.getLeague(currentXP), 'Platinum');
      
      // Gana 2000 XP más (total 4050) → Sube a Diamond
      currentXP += 2000;
      expect(LeagueSystem.getLeague(currentXP), 'Diamond');
    });

    // ==========================================
    // PRUEBA 2: XP necesario para siguiente liga
    // ==========================================
    test('ARRANGE-ACT-ASSERT: XP needed to reach next league', () {
      // ARRANGE
      const int starterXP = 100;
      const int bronzeXP = 350;
      const int silverXP = 750;
      const int goldXP = 1500;
      const int platinumXP = 3000;
      const int diamondXP = 5000;

      // ACT & ASSERT
      expect(LeagueSystem.getXpToNextLeague(starterXP), 100);   // 200 - 100 = 100
      expect(LeagueSystem.getXpToNextLeague(bronzeXP), 150);    // 500 - 350 = 150
      expect(LeagueSystem.getXpToNextLeague(silverXP), 250);    // 1000 - 750 = 250
      expect(LeagueSystem.getXpToNextLeague(goldXP), 500);      // 2000 - 1500 = 500
      expect(LeagueSystem.getXpToNextLeague(platinumXP), 1000); // 4000 - 3000 = 1000
      expect(LeagueSystem.getXpToNextLeague(diamondXP), 0);     // Max league
    });

    // ==========================================
    // PRUEBA 3: Progreso hacia siguiente liga
    // ==========================================
    test('ARRANGE-ACT-ASSERT: Progress percentage to next league', () {
      // ARRANGE
      const int starterAt100 = 100;    // 100/200 = 50%
      const int bronzeAt350 = 350;     // (350-200)/300 = 50%
      const int silverAt750 = 750;     // (750-500)/500 = 50%

      // ACT & ASSERT
      expect(LeagueSystem.getProgressToNextLeague(starterAt100), 0.5);
      expect(LeagueSystem.getProgressToNextLeague(bronzeAt350), 0.5);
      expect(LeagueSystem.getProgressToNextLeague(silverAt750), 0.5);
    });

    // ==========================================
    // PRUEBA 4: XP de Actividad
    // ==========================================
    test('ARRANGE-ACT-ASSERT: XP earned from completing an activity', () {
      // ARRANGE - Actividad con 5 tareas, XP base 100, bonus 50
      const int totalTasks = 5;
      const int xpBase = 100;
      const int bonusXP = 50;

      // ACT - Diferentes resultados
      final xpAllCorrect = LeagueSystem.calculateActivityXp(5, totalTasks, xpBase, bonusXP);
      final xp3Correct = LeagueSystem.calculateActivityXp(3, totalTasks, xpBase, bonusXP);
      final xp0Correct = LeagueSystem.calculateActivityXp(0, totalTasks, xpBase, bonusXP);

      // ASSERT
      expect(xpAllCorrect, 150); // 100 + 50 bonus
      expect(xp3Correct, 60);    // 100 * 3/5 = 60
      expect(xp0Correct, 0);
    });

    // ==========================================
    // PRUEBA 5: XP de Lesson Quiz (práctica)
    // ==========================================
    test('ARRANGE-ACT-ASSERT: XP from Lesson Quiz (practice, first time only)', () {
      // ARRANGE - Quiz con 10 preguntas, XP reward 10
      const int totalQuestions = 10;
      const int xpReward = 10;

      // ACT - Primera vez vs repetición
      final xpFirstTime = LeagueSystem.calculateLessonQuizXp(8, totalQuestions, xpReward, false);
      final xpRepeat = LeagueSystem.calculateLessonQuizXp(8, totalQuestions, xpReward, true);
      final xpAllCorrect = LeagueSystem.calculateLessonQuizXp(10, totalQuestions, xpReward, false);

      // ASSERT
      expect(xpFirstTime, 8);      // 10 * 80% = 8 XP
      expect(xpRepeat, 0);         // Repetir no da XP
      expect(xpAllCorrect, 10);    // 10 * 100% = 10 XP
    });

    // ==========================================
    // PRUEBA 6: XP de Unit Quiz (examen)
    // ==========================================
    test('ARRANGE-ACT-ASSERT: XP from Unit Quiz (graded exam)', () {
      // ARRANGE - Examen con 10 preguntas, max XP 100
      const int totalQuestions = 10;
      const int maxXp = 100;

      // ACT
      final xpPassed = LeagueSystem.calculateUnitQuizXp(8, totalQuestions, maxXp, true);
      final xpFailed = LeagueSystem.calculateUnitQuizXp(5, totalQuestions, maxXp, false);
      final xpPerfect = LeagueSystem.calculateUnitQuizXp(10, totalQuestions, maxXp, true);

      // ASSERT
      expect(xpPassed, 80);   // 8/10 * 100 = 80 XP
      expect(xpFailed, 0);    // No aprobó = 0 XP
      expect(xpPerfect, 100); // Perfecto = 100 XP
    });
  });
}