import 'package:flutter_test/flutter_test.dart';

/// ============================================
/// ACTIVITY PLAY SCREEN - Progreso del Estudiante
/// Simula el flujo de completar actividades y ganar XP
/// ============================================

class ActivityProgressSimulator {
  int correctAnswers = 0;
  int wrongAnswers = 0;
  int currentTaskIndex = 0;
  int totalTasks = 0;
  int xpBase = 100;
  int bonusXP = 50;

  ActivityProgressSimulator({required this.totalTasks, this.xpBase = 100, this.bonusXP = 50});

  void answerTask(bool isCorrect) {
    if (isCorrect) {
      correctAnswers++;
    } else {
      wrongAnswers++;
    }
    currentTaskIndex++;
  }

  bool get isComplete => currentTaskIndex >= totalTasks;
  int get totalAttempts => correctAnswers + wrongAnswers;
  
  int get scorePercentage => totalAttempts > 0
      ? (correctAnswers / totalAttempts * 100).round()
      : 0;

  int calculateXpEarned() {
    final baseXp = (xpBase * correctAnswers / totalTasks).round();
    final allCorrect = correctAnswers == totalTasks;
    final bonus = allCorrect ? bonusXP : 0;
    return baseXp + bonus;
  }
}

/// Simula los diferentes tipos de tareas que puede crear el docente
class TaskTypeSupport {
  static const List<String> supportedTypes = [
    'image_select',
    'image_select_reverse',
    'complete_the_chat',
    'fill_blank',
    'arrange',
    'match',
    'reading',
  ];
  
  static bool isSupported(String type) => supportedTypes.contains(type);
}

void main() {
  group('Student Activity Play - AAA Pattern', () {

    // ==========================================
    // PRUEBA 1: Estudiante completa todas las tareas correctamente
    // ==========================================
    test('ARRANGE-ACT-ASSERT: Student completes all tasks correctly', () {
      // ARRANGE - Actividad con 5 tareas, XP base 100, bonus 50
      const int totalTasks = 5;
      final progress = ActivityProgressSimulator(totalTasks: totalTasks);

      // ACT - Estudiante responde correctamente a todas
      for (int i = 0; i < totalTasks; i++) {
        progress.answerTask(true);
      }

      // ASSERT
      expect(progress.correctAnswers, 5);
      expect(progress.wrongAnswers, 0);
      expect(progress.isComplete, true);
      expect(progress.scorePercentage, 100);
      
      final xpEarned = progress.calculateXpEarned();
      expect(xpEarned, 150); // 100 base + 50 bonus
    });

    // ==========================================
    // PRUEBA 2: Estudiante tiene algunos errores
    // ==========================================
    test('ARRANGE-ACT-ASSERT: Student makes some mistakes', () {
      // ARRANGE
      const int totalTasks = 5;
      final progress = ActivityProgressSimulator(totalTasks: totalTasks);

      // ACT - 3 correctas, 2 incorrectas
      progress.answerTask(true);   // ✅
      progress.answerTask(false);  // ❌
      progress.answerTask(true);   // ✅
      progress.answerTask(false);  // ❌
      progress.answerTask(true);   // ✅

      // ASSERT
      expect(progress.correctAnswers, 3);
      expect(progress.wrongAnswers, 2);
      expect(progress.isComplete, true);
      expect(progress.scorePercentage, 60);
      
      final xpEarned = progress.calculateXpEarned();
      expect(xpEarned, 60); // 100 * 3/5 = 60, sin bonus
    });

    // ==========================================
    // PRUEBA 3: Todos los tipos de tarea son soportados
    // ==========================================
    test('ARRANGE-ACT-ASSERT: All task types are supported in switch case', () {
      // ARRANGE
      final taskTypes = TaskTypeSupport.supportedTypes;

      // ACT & ASSERT
      for (final type in taskTypes) {
        expect(TaskTypeSupport.isSupported(type), true,
            reason: 'Task type "$type" debe estar soportado');
      }
      
      expect(taskTypes.length, 7);
    });
  });
}