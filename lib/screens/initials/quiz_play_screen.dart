import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/initials/activity_complete_screen.dart';
import 'package:loringo_app/screens/initials/screen_one.dart';
import 'package:loringo_app/screens/initials/screen_five.dart';
import 'package:loringo_app/screens/initials/screen_four.dart';
import 'package:loringo_app/screens/initials/screen_six.dart';
import 'package:loringo_app/screens/initials/screen_three.dart';
import 'package:loringo_app/screens/initials/screen_two.dart';
import 'package:loringo_app/screens/initials/screen_seven.dart';
import 'package:loringo_app/services/database/database.dart';

class QuizPlayScreen extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String lessonId;
  final String quizId;
  final String quizTitle;
  final String collectionName;
  final String? studentId;
  final bool isPreview;

  const QuizPlayScreen({
    super.key,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.quizId,
    required this.quizTitle,
    this.collectionName = 'content',
    this.studentId,
    this.isPreview = false,
  });

  @override
  State<QuizPlayScreen> createState() => _QuizPlayScreenState();
}

class _QuizPlayScreenState extends State<QuizPlayScreen> {
  List<Map<String, dynamic>> quizTasks = [];
  int currentTaskIndex = 0;
  int correctAnswers = 0;
  int totalTasks = 0;
  bool isLoading = true;
  String loadingMessage = 'Loading quiz...';
  int _xpReward = 0;
  String _quizType = 'lesson';
  String _unitTitle = '';

  @override
  void initState() {
    super.initState();
    _loadQuizTasks();
  }

  Future<void> _loadQuizTasks() async {
    try {
      final quizDoc = await FirebaseFirestore.instance
          .collection('quizzes')
          .doc(widget.quizId)
          .get();

      if (!quizDoc.exists) {
        _showErrorDialog('Quiz not found');
        return;
      }

      final quizData = quizDoc.data() as Map<String, dynamic>;

      print('=== QUIZ DATA ===');
      print('Quiz ID: ${widget.quizId}');
      print('Type: ${quizData['type']}');
      print('Question IDs: ${quizData['questionIds']}');
      print('Content ID: ${widget.contentId}');
      print('Unit ID: ${widget.unitId}');
      print('================');

      _xpReward = (quizData['xpReward'] as num? ?? 0).toInt();
      _quizType = quizData['type'] as String? ?? 'lesson';
      
      final bool isUnitQuiz = _quizType == 'unit';

      if (isUnitQuiz) {
        final unitDoc = await FirebaseFirestore.instance
            .collection('content')
            .doc(widget.contentId)
            .collection('units')
            .doc(widget.unitId)
            .get();
        _unitTitle = (unitDoc.data() as Map<String, dynamic>?)?['title'] as String? ?? widget.quizTitle;
      }

      List<Map<String, dynamic>> loadedTasks = [];

      if (isUnitQuiz) {
        // ✅ Unit quiz: Load from questions subcollection
        final questionsSnapshot = await FirebaseFirestore.instance
            .collection('quizzes')
            .doc(widget.quizId)
            .collection('questions')
            .orderBy('order')
            .get();

        for (final qDoc in questionsSnapshot.docs) {
          final qData = qDoc.data() as Map<String, dynamic>;
          loadedTasks.add({
            'isUnitQuiz': true,
            'questionData': qData,
          });
        }
        
        setState(() {
          quizTasks = loadedTasks;
          totalTasks = loadedTasks.length;
          isLoading = false;
        });
      } else {
        // ✅ Lesson quiz: Load from questionIds array (reuses activity tasks)
        final List<String> questionIds = List<String>.from(
          quizData['questionIds'] ?? [],
        );

        if (questionIds.isEmpty) {
          _showErrorDialog('This quiz has no questions');
          return;
        }

        // First, get all lessons once
        final lessonsSnapshot = await FirebaseFirestore.instance
            .collection('content')
            .doc(widget.contentId)
            .collection('units')
            .doc(widget.unitId)
            .collection('lessons')
            .get();

        // Create a map to cache activity -> lesson relationships
        final Map<String, String> activityToLessonMap = {};

        // Build a map of all activities across all lessons
        for (final lessonDoc in lessonsSnapshot.docs) {
          final lessonId = lessonDoc.id;
          final activitiesSnapshot = await FirebaseFirestore.instance
              .collection('content')
              .doc(widget.contentId)
              .collection('units')
              .doc(widget.unitId)
              .collection('lessons')
              .doc(lessonId)
              .collection('activities')
              .get();
          
          for (final activityDoc in activitiesSnapshot.docs) {
            activityToLessonMap[activityDoc.id] = lessonId;
          }
        }

        // Now load each task
        for (int i = 0; i < questionIds.length; i++) {
          final questionId = questionIds[i];
          
          setState(() {
            loadingMessage = 'Loading question ${i + 1} of ${questionIds.length}...';
          });

          // Format: "activityId_taskId"
          final parts = questionId.split('_task_');
          if (parts.length != 2) {
            print('Invalid question ID format: $questionId');
            continue;
          }

          final activityId = parts[0];
          final taskId = parts[1];

          try {
            // Find which lesson contains this activity
            final foundLessonId = activityToLessonMap[activityId];
            
            if (foundLessonId == null) {
              print('Activity $activityId not found in any lesson');
              continue;
            }

            final taskDoc = await FirebaseFirestore.instance
                .collection('content')
                .doc(widget.contentId)
                .collection('units')
                .doc(widget.unitId)
                .collection('lessons')
                .doc(foundLessonId)
                .collection('activities')
                .doc(activityId)
                .collection('tasks')
                .doc(taskId)
                .get();

            if (taskDoc.exists) {
              final taskData = taskDoc.data() as Map<String, dynamic>;
              loadedTasks.add({
                'isUnitQuiz': false,
                'activityId': activityId,
                'lessonId': foundLessonId,
                'taskId': taskId,
                'taskData': taskData,
              });
            } else {
              print('Task $taskId not found in activity $activityId');
            }
          } catch (e) {
            print('Error loading task $questionId: $e');
          }
        }

        setState(() {
          quizTasks = loadedTasks;
          totalTasks = loadedTasks.length;
          isLoading = false;
        });

        if (quizTasks.isEmpty) {
          _showErrorDialog('No valid quiz questions found');
        }
      }
    } catch (e) {
      print('Error loading quiz: $e');
      setState(() => isLoading = false);
      _showErrorDialog('Error loading quiz: $e');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _nextTask({bool wasCorrect = false}) {
    if (wasCorrect) {
      correctAnswers++;
    }

    if (currentTaskIndex < quizTasks.length - 1) {
      setState(() {
        currentTaskIndex++;
      });
    } else {
      _showQuizResults();
    }
  }

  void _nextReadingTask(bool pass, int subCorrect, int subWrong) {
    correctAnswers += subCorrect;
    
    if (currentTaskIndex < quizTasks.length - 1) {
      setState(() {
        currentTaskIndex++;
      });
    } else {
      _showQuizResults();
    }
  }

  void _showQuizResults() async {
    final percentage = totalTasks > 0
        ? (correctAnswers / totalTasks * 100).round()
        : 0;
    int stars = 1;
    if (percentage >= 90) {
      stars = 3;
    } else if (percentage >= 70) {
      stars = 2;
    }

    int xpEarned = 0;
    final db = Database();
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (widget.isPreview) {
      // Teacher preview — never save progress or award XP
    } else if (widget.studentId != null) {
      try {
        final prevDoc = await FirebaseFirestore.instance
            .collection('students')
            .doc(widget.studentId!)
            .collection('progress')
            .doc(widget.quizId)
            .get();

        final bool wasCompleted = prevDoc.exists &&
            (prevDoc.data()?['isCompleted'] as bool? ?? false);
        final int prevScore =
            wasCompleted ? (prevDoc.data()?['score'] as num? ?? 0).toInt() : -1;

        // ✅ Fixed: Use 'unit' instead of 'unit_test'
        if (_quizType == 'unit') {
          if (!wasCompleted) {
            xpEarned = _xpReward;
          } else if (correctAnswers > prevScore) {
            xpEarned = 5;
          }
        } else {
          if (!wasCompleted) {
            xpEarned = (_xpReward * (percentage / 100)).round();
          }
        }

        await db.saveQuizCompletion(
          studentId: widget.studentId!,
          quizId: widget.quizId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          score: correctAnswers,
          totalQuestions: totalTasks,
          stars: stars,
          xpEarned: xpEarned,
          updateBestOnly: wasCompleted,
          unitTitle: _unitTitle,
          generateReport: _quizType == 'unit',
          reportType: _quizType == 'unit' ? 'unit' : 'lesson',
        );
      } catch (e) {
        print('Error saving quiz progress: $e');
      }
    } else if (userId != null) {
      xpEarned = (_xpReward * (percentage / 100)).round();
      try {
        final progressRef = FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('progress')
            .doc('quizzes');

        await progressRef.set({
          widget.quizId: {
            'completedAt': FieldValue.serverTimestamp(),
            'score': correctAnswers,
            'total': totalTasks,
            'percentage': percentage,
            'stars': stars,
          },
        }, SetOptions(merge: true));

        if (stars >= 1) await _unlockNextUnit();
      } catch (e) {
        print('Error saving quiz progress: $e');
      }
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityCompleteScreen(
          screenTitle: 'Quiz Complete!',
          activityTitle: widget.quizTitle,
          scorePercent: percentage,
          correctAnswers: correctAnswers,
          wrongAnswers: totalTasks - correctAnswers,
          xpEarned: xpEarned,
        ),
      ),
    );
  }

  Future<void> _unlockNextUnit() async {
    try {
      final unitsSnapshot = await FirebaseFirestore.instance
          .collection(widget.collectionName)
          .doc(widget.contentId)
          .collection('units')
          .orderBy('order')
          .get();

      int currentUnitIndex = -1;
      for (int i = 0; i < unitsSnapshot.docs.length; i++) {
        if (unitsSnapshot.docs[i].id == widget.unitId) {
          currentUnitIndex = i;
          break;
        }
      }

      if (currentUnitIndex >= 0 &&
          currentUnitIndex < unitsSnapshot.docs.length - 1) {
        final nextUnitDoc = unitsSnapshot.docs[currentUnitIndex + 1];
        await nextUnitDoc.reference.update({'locked': false});
        print('Unlocked next unit: ${nextUnitDoc.id}');
      }
    } catch (e) {
      print('Error unlocking next unit: $e');
    }
  }

  Widget _buildTaskScreen(Map<String, dynamic> quizTask) {
    final isUnitQuiz = quizTask['isUnitQuiz'] == true;
    
    if (isUnitQuiz) {
      // Unit quiz: Multiple choice question
      final questionData = quizTask['questionData'] as Map<String, dynamic>;
      final question = questionData['question'] as String? ?? '';
      final options = List<String>.from(questionData['options'] ?? []);
      final correctIndex = questionData['correctIndex'] as int? ?? 0;
      
      return _UnitQuizQuestionCard(
        key: ValueKey('unit_$currentTaskIndex'),
        question: question,
        options: options,
        correctIndex: correctIndex,
        onAnswer: (isCorrect) => _nextTask(wasCorrect: isCorrect),
        currentTaskNumber: currentTaskIndex,
        totalTasks: quizTasks.length,
        quizTitle: widget.quizTitle,
      );
    } else {
      // Lesson quiz: Use existing task screens
      final activityId = quizTask['activityId'];
      final lessonId = quizTask['lessonId'];
      final taskId = quizTask['taskId'];
      final taskData = quizTask['taskData'] as Map<String, dynamic>;
      final taskType = taskData['type'] ?? '';

      switch (taskType) {
        case 'image_select':
          return ScreenOne(
            key: ValueKey(taskId),
            contentId: widget.contentId,
            unitId: widget.unitId,
            lessonId: lessonId,
            activityId: activityId,
            taskId: taskId,
            onTaskComplete: (isCorrect) => _nextTask(wasCorrect: isCorrect),
            currentTaskNumber: currentTaskIndex,
            totalTasks: quizTasks.length,
            collectionName: 'content', // ✅ FIXED: always 'content'
          );
        case 'complete_the_chat':
          return ScreenTwo(
            key: ValueKey(taskId),
            contentId: widget.contentId,
            unitId: widget.unitId,
            lessonId: lessonId,
            activityId: activityId,
            taskId: taskId,
            onTaskComplete: (isCorrect) => _nextTask(wasCorrect: isCorrect),
            currentTaskNumber: currentTaskIndex,
            totalTasks: quizTasks.length,
            collectionName: 'content', // ✅ FIXED
          );
        case 'arrange':
          return ScreenThree(
            key: ValueKey(taskId),
            contentId: widget.contentId,
            unitId: widget.unitId,
            lessonId: lessonId,
            activityId: activityId,
            taskId: taskId,
            onTaskComplete: (isCorrect) => _nextTask(wasCorrect: isCorrect),
            currentTaskNumber: currentTaskIndex,
            totalTasks: quizTasks.length,
            collectionName: 'content', // ✅ FIXED
          );
        case 'fill_blank':
          return ScreenFour(
            key: ValueKey(taskId),
            contentId: widget.contentId,
            unitId: widget.unitId,
            lessonId: lessonId,
            activityId: activityId,
            taskId: taskId,
            onTaskComplete: (isCorrect) => _nextTask(wasCorrect: isCorrect),
            currentTaskNumber: currentTaskIndex,
            totalTasks: quizTasks.length,
            collectionName: 'content', // ✅ FIXED
          );
        case 'image_select_reverse':
          return ScreenFive(
            key: ValueKey(taskId),
            contentId: widget.contentId,
            unitId: widget.unitId,
            lessonId: lessonId,
            activityId: activityId,
            taskId: taskId,
            onTaskComplete: (isCorrect) => _nextTask(wasCorrect: isCorrect),
            currentTaskNumber: currentTaskIndex,
            totalTasks: quizTasks.length,
            collectionName: 'content', // ✅ FIXED
          );
        case 'match':
          return ScreenSix(
            key: ValueKey(taskId),
            contentId: widget.contentId,
            unitId: widget.unitId,
            lessonId: lessonId,
            activityId: activityId,
            taskId: taskId,
            onTaskComplete: (isCorrect) => _nextTask(wasCorrect: isCorrect),
            currentTaskNumber: currentTaskIndex,
            totalTasks: quizTasks.length,
            collectionName: 'content', // ✅ FIXED
          );
        case 'reading':
          return ScreenSeven(
            key: ValueKey(taskId),
            contentId: widget.contentId,
            unitId: widget.unitId,
            lessonId: lessonId,
            activityId: activityId,
            taskId: taskId,
            onTaskComplete: _nextReadingTask,
            currentTaskNumber: currentTaskIndex,
            totalTasks: quizTasks.length,
            collectionName: 'content', // ✅ FIXED
          );
        default:
          return Scaffold(
            appBar: AppBar(
              title: Text(widget.quizTitle),
              backgroundColor: const Color(0xFF4CAF50),
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 100, color: Colors.grey),
                  const SizedBox(height: 24),
                  Text(
                    'Task type "$taskType" not supported',
                    style: const TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => _nextTask(wasCorrect: false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                    ),
                    child: const Text(
                      'Skip',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.quizTitle),
          backgroundColor: const Color(0xFF4CAF50),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                loadingMessage,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (quizTasks.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.quizTitle),
          backgroundColor: const Color(0xFF4CAF50),
        ),
        body: const Center(child: Text('No quiz questions available')),
      );
    }

    return _buildTaskScreen(quizTasks[currentTaskIndex]);
  }
}

// Unit Quiz Question Card Widget
class _UnitQuizQuestionCard extends StatefulWidget {
  final String question;
  final List<String> options;
  final int correctIndex;
  final Function(bool) onAnswer;
  final int currentTaskNumber;
  final int totalTasks;
  final String quizTitle;

  const _UnitQuizQuestionCard({
    super.key,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.onAnswer,
    required this.currentTaskNumber,
    required this.totalTasks,
    required this.quizTitle,
  });

  @override
  State<_UnitQuizQuestionCard> createState() => _UnitQuizQuestionCardState();
}

class _UnitQuizQuestionCardState extends State<_UnitQuizQuestionCard> {
  int? selectedOption;
  bool isAnswered = false;

  void _submitAnswer() {
    if (selectedOption == null) return;
    
    final isCorrect = selectedOption == widget.correctIndex;
    setState(() => isAnswered = true);
    
    Future.delayed(const Duration(milliseconds: 500), () {
      widget.onAnswer(isCorrect);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.quizTitle),
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Question ${widget.currentTaskNumber + 1} of ${widget.totalTasks}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (widget.currentTaskNumber + 1) / widget.totalTasks,
              backgroundColor: Colors.grey.shade200,
              color: const Color(0xFF7C3AED),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                widget.question,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: widget.options.length,
                itemBuilder: (context, index) {
                  final letter = String.fromCharCode(65 + index);
                  final isSelected = selectedOption == index;
                  final isCorrect = index == widget.correctIndex;
                  
                  Color? backgroundColor;
                  if (isAnswered) {
                    if (isCorrect) {
                      backgroundColor = Colors.green.shade50;
                    } else if (isSelected && !isCorrect) {
                      backgroundColor = Colors.red.shade50;
                    }
                  }
                  
                  return GestureDetector(
                    onTap: isAnswered ? null : () => setState(() => selectedOption = index),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: backgroundColor ?? (isSelected ? const Color(0xFF7C3AED).withOpacity(0.08) : Colors.grey.shade50),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF7C3AED) : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected ? const Color(0xFF7C3AED) : Colors.white,
                              border: Border.all(color: isSelected ? const Color(0xFF7C3AED) : Colors.grey.shade400),
                            ),
                            child: Center(
                              child: isSelected
                                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                                  : Text(letter, style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.options[index],
                              style: TextStyle(
                                fontSize: 14,
                                color: isSelected ? const Color(0xFF7C3AED) : Colors.black87,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isAnswered && isCorrect)
                            const Icon(Icons.check_circle, color: Colors.green, size: 24),
                          if (isAnswered && isSelected && !isCorrect)
                            const Icon(Icons.cancel, color: Colors.red, size: 24),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: isAnswered ? null : (selectedOption == null ? null : _submitAnswer),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  isAnswered ? 'Next Question...' : 'Submit Answer',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}