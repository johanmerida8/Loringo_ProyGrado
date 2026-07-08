// test/student/activity_progress_test.dart
import 'package:flutter_test/flutter_test.dart';

/// ============================================
/// ACTIVITY PLAY SCREEN - Lógica de Progreso
/// Simula el flujo: estudiante hace tareas → guarda progreso → calcula XP
/// ============================================

class ActivityProgressSimulator {
  int correctAnswers = 0;
  int wrongAnswers = 0;
  int currentTaskIndex = 0;
  int totalTasks = 0;

  ActivityProgressSimulator({required this.totalTasks});

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

  int calculateXpEarned(int xpBase, int bonusXP, {bool isPreview = false}) {
    if (isPreview) return 0;
    
    final baseXp = (xpBase * correctAnswers / totalTasks).round();
    final allCorrect = correctAnswers == totalTasks;
    final bonus = allCorrect ? bonusXP : 0;
    
    return baseXp + bonus;
  }
}

/// Simula los diferentes tipos de tareas que puede crear el docente
class TaskTypeSimulator {
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
  
  static String getDisplayName(String type) {
    switch (type) {
      case 'image_select': return 'Image Select';
      case 'image_select_reverse': return 'Image Select Reverse';
      case 'complete_the_chat': return 'Complete the Chat';
      case 'fill_blank': return 'Fill in the Blank';
      case 'arrange': return 'Sentence Arrange';
      case 'match': return 'Match Pairs';
      case 'reading': return 'Reading Comprehension';
      default: return 'Unknown';
    }
  }
}

void main() {
  group('Activity Play Screen - Progress Logic (AAA Pattern)', () {

    // ==========================================
    // PRUEBA 1: Estudiante completa todas las tareas correctamente
    // ==========================================
    test('ARRANGE-ACT-ASSERT: Student completes all tasks correctly', () {
      // ARRANGE - Simular actividad con 3 tareas
      const int totalTasks = 3;
      final progress = ActivityProgressSimulator(totalTasks: totalTasks);
      const int xpBase = 100;
      const int bonusXP = 50;

      // ACT - Estudiante responde correctamente a todas
      progress.answerTask(true);  // Tarea 1 ✅
      progress.answerTask(true);  // Tarea 2 ✅
      progress.answerTask(true);  // Tarea 3 ✅

      // ASSERT
      expect(progress.correctAnswers, 3);
      expect(progress.wrongAnswers, 0);
      expect(progress.isComplete, true);
      expect(progress.scorePercentage, 100);
      
      final xpEarned = progress.calculateXpEarned(xpBase, bonusXP);
      expect(xpEarned, 150); // 100 base + 50 bonus
    });

    // ==========================================
    // PRUEBA 2: Estudiante tiene algunos errores
    // ==========================================
    test('ARRANGE-ACT-ASSERT: Student makes some mistakes', () {
      // ARRANGE
      const int totalTasks = 5;
      final progress = ActivityProgressSimulator(totalTasks: totalTasks);
      const int xpBase = 100;
      const int bonusXP = 50;

      // ACT - Mezcla de aciertos y errores
      progress.answerTask(true);   // Tarea 1 ✅
      progress.answerTask(false);  // Tarea 2 ❌
      progress.answerTask(true);   // Tarea 3 ✅
      progress.answerTask(false);  // Tarea 4 ❌
      progress.answerTask(true);   // Tarea 5 ✅

      // ASSERT
      expect(progress.correctAnswers, 3);
      expect(progress.wrongAnswers, 2);
      expect(progress.isComplete, true);
      expect(progress.scorePercentage, 60); // 3/5 = 60%
      
      final xpEarned = progress.calculateXpEarned(xpBase, bonusXP);
      // Base XP: 100 * 3/5 = 60, sin bonus (no todas correctas)
      expect(xpEarned, 60);
    });

    // ==========================================
    // PRUEBA 3: Vista previa no guarda XP
    // ==========================================
    test('ARRANGE-ACT-ASSERT: Preview mode does not save XP', () {
      // ARRANGE
      const int totalTasks = 3;
      final progress = ActivityProgressSimulator(totalTasks: totalTasks);
      const int xpBase = 100;
      const int bonusXP = 50;
      const bool isPreview = true;

      // ACT - Estudiante completa todo en modo preview
      progress.answerTask(true);
      progress.answerTask(true);
      progress.answerTask(true);

      // ASSERT
      final xpEarned = progress.calculateXpEarned(xpBase, bonusXP, isPreview: isPreview);
      expect(xpEarned, 0); // Preview no otorga XP
    });

    // ==========================================
    // PRUEBA 4: Progreso parcial (no completado aún)
    // ==========================================
    test('ARRANGE-ACT-ASSERT: Partial progress not yet complete', () {
      // ARRANGE
      const int totalTasks = 4;
      final progress = ActivityProgressSimulator(totalTasks: totalTasks);

      // ACT - Solo 2 de 4 tareas completadas
      progress.answerTask(true);
      progress.answerTask(false);

      // ASSERT
      expect(progress.correctAnswers, 1);
      expect(progress.wrongAnswers, 1);
      expect(progress.currentTaskIndex, 2);
      expect(progress.isComplete, false);
      expect(progress.totalAttempts, 2);
    });

    // ==========================================
    // PRUEBA 5: Tipos de tarea soportados por el switch case
    // ==========================================
    test('ARRANGE-ACT-ASSERT: All task types are supported', () {
      // ARRANGE - Lista de tipos que el docente puede crear
      final taskTypes = TaskTypeSimulator.supportedTypes;

      // ACT & ASSERT - Verificar que todos están soportados
      for (final type in taskTypes) {
        expect(TaskTypeSimulator.isSupported(type), true,
            reason: 'Task type "$type" should be supported');
      }
      
      expect(taskTypes.length, 7);
    });

    // ==========================================
    // PRUEBA 6: Nombre mostrado para cada tipo de tarea
    // ==========================================
    test('ARRANGE-ACT-ASSERT: Display names for each task type', () {
      // ARRANGE & ACT
      final imageSelect = TaskTypeSimulator.getDisplayName('image_select');
      final reading = TaskTypeSimulator.getDisplayName('reading');
      final match = TaskTypeSimulator.getDisplayName('match');
      
      // ASSERT
      expect(imageSelect, 'Image Select');
      expect(reading, 'Reading Comprehension');
      expect(match, 'Match Pairs');
    });

    // ==========================================
    // PRUEBA 7: Cálculo de porcentaje de puntaje
    // ==========================================
    test('ARRANGE-ACT-ASSERT: Score percentage calculation', () {
      // ARRANGE - Diferentes escenarios
      const int totalTasks = 10;
      
      // ACT
      final progressEmpty = ActivityProgressSimulator(totalTasks: totalTasks);
      final progressFull = ActivityProgressSimulator(totalTasks: totalTasks);
      final progressHalf = ActivityProgressSimulator(totalTasks: totalTasks);
      
      // Simular diferentes resultados
      for (int i = 0; i < 10; i++) progressFull.answerTask(true);
      for (int i = 0; i < 5; i++) progressHalf.answerTask(true);
      for (int i = 0; i < 5; i++) progressHalf.answerTask(false);
      
      // ASSERT
      expect(progressEmpty.scorePercentage, 0);
      expect(progressFull.scorePercentage, 100);
      expect(progressHalf.scorePercentage, 50);
    });
  });
}