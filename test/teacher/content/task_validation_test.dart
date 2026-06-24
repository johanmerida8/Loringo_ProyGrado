// test/teacher/create_task_validation_test.dart
import 'package:flutter_test/flutter_test.dart';

// ============================================
// SIMULACIÓN DE LA LÓGICA DE CREACIÓN DE TAREAS
// ============================================

class TaskValidationLogic {
  // Validaciones comunes para TODOS los tipos de tareas
  static String? validateTitle(String title) {
    if (title.isEmpty) return 'Task title is required';
    if (title.length < 3) return 'Title must be at least 3 characters';
    return null;
  }
  
  static String? validateOrder(String order) {
    final orderInt = int.tryParse(order);
    if (orderInt == null) return 'Order must be a number';
    if (orderInt < 1) return 'Order must be at least 1';
    return null;
  }
  
  // Validación específica para tarea tipo "match"
  static String? validateMatchPairs(List<Map<String, dynamic>> pairs, String mode) {
    if (pairs.length < 3) return 'At least 3 pairs required';
    if (pairs.length > 5) return 'Maximum 5 pairs allowed';
    
    for (int i = 0; i < pairs.length; i++) {
      final pair = pairs[i];
      if ((pair['english'] as String).isEmpty) return 'Pair ${i + 1}: English word required';
      
      if (mode == 'text') {
        if ((pair['translated'] as String).isEmpty) return 'Pair ${i + 1}: Translation required';
      } else {
        if ((pair['image'] as String).isEmpty) return 'Pair ${i + 1}: Image required';
      }
    }
    return null;
  }
  
  // Validación para tarea tipo "reading comprehension"
  static String? validateReadingQuestions(List<Map<String, dynamic>> questions) {
    if (questions.isEmpty) return 'At least one question required';
    
    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      if ((q['text'] as String).isEmpty) return 'Question ${i + 1}: Text required';
      
      final options = q['options'] as List;
      if (options.length < 3) return 'Question ${i + 1}: At least 3 options required';
      
      bool hasCorrect = false;
      for (var opt in options) {
        if (opt['isCorrect'] == true) hasCorrect = true;
      }
      if (!hasCorrect) return 'Question ${i + 1}: Mark at least one correct answer';
    }
    return null;
  }
  
  // Validación para tarea tipo "arrange sentence"
  static String? validateArrangeSentence(String sentence) {
    final words = sentence.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length < 3) return 'Sentence must have at least 3 words';
    return null;
  }
  
  // Validación para tarea tipo "fill blank"
  static String? validateFillBlank(int blanks, List<Map<String, dynamic>> options) {
    if (blanks == 0) return 'Add at least one blank';
    
    // Verificar que cada blank tiene una respuesta correcta
    for (int b = 0; b < blanks; b++) {
      bool hasCorrect = options.any((o) => o['isCorrect'] == true && o['blankIndex'] == b);
      if (!hasCorrect) return 'Blank ${b + 1}: No correct answer assigned';
    }
    
    // Verificar que hay al menos un distractor
    bool hasDistractor = options.any((o) => o['isCorrect'] == false && (o['text'] as String).isNotEmpty);
    if (!hasDistractor) return 'Add at least one distractor';
    
    return null;
  }
}

void main() {
  group('Teacher - Task Creation Validation (AAA Pattern)', () {
    
    test('ARRANGE-ACT-ASSERT: Complete task validation workflow', () {
      // ==========================================
      // ARRANGE - Preparar datos de prueba
      // ==========================================
      
      // Datos para tarea tipo "match"
      const String taskTitle = 'Match Colors';
      const String taskOrder = '3';
      final List<Map<String, dynamic>> matchPairs = [
        {'english': 'Red', 'translated': 'Rojo', 'image': ''},
        {'english': 'Blue', 'translated': 'Azul', 'image': ''},
        {'english': 'Green', 'translated': 'Verde', 'image': ''},
      ];
      const String matchMode = 'text';
      
      // Datos para tarea tipo "reading"
      final List<Map<String, dynamic>> readingQuestions = [
        {
          'text': 'What is the main idea?',
          'options': [
            {'text': 'Option A', 'isCorrect': true},
            {'text': 'Option B', 'isCorrect': false},
            {'text': 'Option C', 'isCorrect': false},
          ]
        }
      ];
      
      // Datos para tarea tipo "arrange"
      const String arrangeSentence = 'The sky is blue';
      
      // Datos para tarea tipo "fill blank"
      const int fillBlankCount = 2;
      final List<Map<String, dynamic>> fillBlankOptions = [
        {'text': 'red', 'isCorrect': true, 'blankIndex': 0},
        {'text': 'blue', 'isCorrect': true, 'blankIndex': 1},
        {'text': 'green', 'isCorrect': false, 'blankIndex': null},
      ];
      
      // ==========================================
      // ACT - Ejecutar todas las validaciones
      // ==========================================
      
      // 1. Validar título y orden (común a todas las tareas)
      final titleError = TaskValidationLogic.validateTitle(taskTitle);
      final orderError = TaskValidationLogic.validateOrder(taskOrder);
      
      // 2. Validar tarea tipo MATCH
      final matchError = TaskValidationLogic.validateMatchPairs(matchPairs, matchMode);
      
      // 3. Validar tarea tipo READING
      final readingError = TaskValidationLogic.validateReadingQuestions(readingQuestions);
      
      // 4. Validar tarea tipo ARRANGE
      final arrangeError = TaskValidationLogic.validateArrangeSentence(arrangeSentence);
      
      // 5. Validar tarea tipo FILL BLANK
      final fillBlankError = TaskValidationLogic.validateFillBlank(fillBlankCount, fillBlankOptions);
      
      // ==========================================
      // ASSERT - Verificar todos los resultados
      // ==========================================
      
      // 1. Título y orden válidos
      expect(titleError, null);
      expect(orderError, null);
      
      // 2. Match: 3 pares válidos
      expect(matchError, null);
      
      // 3. Reading: 1 pregunta con 3 opciones, una correcta
      expect(readingError, null);
      
      // 4. Arrange: frase con 4 palabras (>3)
      expect(arrangeError, null);
      
      // 5. Fill Blank: 2 blanks, respuestas correctas y distractor
      expect(fillBlankError, null);
      
      // Verificar que TODAS las validaciones pasaron
      expect(titleError == null && orderError == null && matchError == null && readingError == null && arrangeError == null && fillBlankError == null, true);
    });
    
    // Test adicional: Validación de errores
    test('ARRANGE-ACT-ASSERT: Task validation rejects invalid data', () {
      // ARRANGE - Datos inválidos
      const String invalidTitle = 'Ab'; // menos de 3 caracteres
      const String invalidOrder = 'abc'; // no es número
      
      // ACT
      final titleError = TaskValidationLogic.validateTitle(invalidTitle);
      final orderError = TaskValidationLogic.validateOrder(invalidOrder);
      
      // ASSERT
      expect(titleError, 'Title must be at least 3 characters');
      expect(orderError, 'Order must be a number');
    });
  });
}