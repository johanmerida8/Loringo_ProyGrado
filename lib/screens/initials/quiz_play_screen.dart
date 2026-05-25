import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/initials/activity_complete_screen.dart';
import 'package:loringo_app/screens/initials/screen_one.dart';
import 'package:loringo_app/screens/initials/screen_five.dart';
import 'package:loringo_app/screens/initials/screen_four.dart';
import 'package:loringo_app/screens/initials/screen_three.dart';
import 'package:loringo_app/screens/initials/screen_two.dart';
import 'package:loringo_app/services/database/database.dart';

class QuizPlayScreen extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String lessonId;
  final String quizId;
  final String quizTitle;
  final String collectionName;
  final String? studentId;
  final bool isPreview; // When true, no progress or XP is saved

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
  String _quizType = 'lesson_quiz';
  String _unitTitle = '';

  @override
  void initState() {
    super.initState();
    _loadQuizTasks();
  }

  Future<void> _loadQuizTasks() async {
    try {
      // Load quiz document — path differs for unit vs lesson quizzes
      final bool isUnitQuiz = widget.lessonId.isEmpty;

      final quizDoc = isUnitQuiz
          ? await FirebaseFirestore.instance
              .collection(widget.collectionName)
              .doc(widget.contentId)
              .collection('units')
              .doc(widget.unitId)
              .collection('quizzes')
              .doc(widget.quizId)
              .get()
          : await FirebaseFirestore.instance
              .collection(widget.collectionName)
              .doc(widget.contentId)
              .collection('units')
              .doc(widget.unitId)
              .collection('lessons')
              .doc(widget.lessonId)
              .collection('quizzes')
              .doc(widget.quizId)
              .get();

      if (!quizDoc.exists) {
        _showErrorDialog('Quiz not found');
        return;
      }

      final quizData = quizDoc.data() as Map<String, dynamic>;
      _xpReward = (quizData['xpReward'] as num? ?? 0).toInt();
      _quizType = quizData['type'] as String? ?? 'lesson_quiz';

      // Load unit title for the report (used when it's a unit test)
      if (isUnitQuiz) {
        final unitDoc = await FirebaseFirestore.instance
            .collection(widget.collectionName)
            .doc(widget.contentId)
            .collection('units')
            .doc(widget.unitId)
            .get();
        _unitTitle =
            (unitDoc.data() as Map<String, dynamic>?)?['title'] as String? ??
                widget.quizTitle;
      }

      final List<String> questionIds = List<String>.from(
        quizData['questionIds'] ?? [],
      );

      if (questionIds.isEmpty) {
        _showErrorDialog('This quiz has no questions');
        return;
      }

      // Load each task referenced in questionIds
      List<Map<String, dynamic>> loadedTasks = [];
      for (int i = 0; i < questionIds.length; i++) {
        final questionId = questionIds[i];
        
        // Update loading message with progress
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
          DocumentSnapshot? taskDoc;
          String? foundLessonId;

          // For unit quizzes lessonId is empty — search all lessons directly.
          // For lesson quizzes, try the current lesson first (fast path).
          if (widget.lessonId.isNotEmpty) {
            taskDoc = await FirebaseFirestore.instance
                .collection(widget.collectionName)
                .doc(widget.contentId)
                .collection('units')
                .doc(widget.unitId)
                .collection('lessons')
                .doc(widget.lessonId)
                .collection('activities')
                .doc(activityId)
                .collection('tasks')
                .doc(taskId)
                .get();

            if (taskDoc.exists) foundLessonId = widget.lessonId;
          }

          // If not found yet, search all lessons (fallback for lesson quizzes
          // and primary path for unit quizzes)
          if (foundLessonId == null) {
            final lessonsSnapshot = await FirebaseFirestore.instance
                .collection(widget.collectionName)
                .doc(widget.contentId)
                .collection('units')
                .doc(widget.unitId)
                .collection('lessons')
                .get();

            for (var lessonDoc in lessonsSnapshot.docs) {
              final lessonId = lessonDoc.id;
              if (lessonId == widget.lessonId) continue; // already checked

              taskDoc = await FirebaseFirestore.instance
                  .collection(widget.collectionName)
                  .doc(widget.contentId)
                  .collection('units')
                  .doc(widget.unitId)
                  .collection('lessons')
                  .doc(lessonId)
                  .collection('activities')
                  .doc(activityId)
                  .collection('tasks')
                  .doc(taskId)
                  .get();

              if (taskDoc.exists) {
                foundLessonId = lessonId;
                break;
              }
            }
          }

          if (taskDoc != null && taskDoc.exists && foundLessonId != null) {
            final taskData = taskDoc.data() as Map<String, dynamic>;
            loadedTasks.add({
              'activityId': activityId,
              'lessonId': foundLessonId,
              'taskId': taskId,
              'taskData': taskData,
            });
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
      // Quiz completed - calculate score and show results
      _showQuizResults();
    }
  }

  void _showQuizResults() async {
    // Calculate percentage and stars
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
        // Check if this quiz was completed before
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

        if (_quizType == 'unit_test') {
          if (!wasCompleted) {
            // First completion: full xpReward (flat 20)
            xpEarned = _xpReward;
          } else if (correctAnswers > prevScore) {
            // Improved best score: 5 XP bonus
            xpEarned = 5;
          }
          // No improvement = 0 XP
        } else {
          // lesson_quiz: proportional XP only on first completion
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
          generateReport: _quizType == 'unit_test' || _quizType == 'content_test',
          reportType: _quizType == 'content_test' ? 'content' : 'unit',
        );
      } catch (e) {
        print('Error saving quiz progress: $e');
      }
    } else if (userId != null) {
        // Regular user: save to users/{id}/progress/quizzes
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

  String _getStarDisplay(int stars) {
    switch (stars) {
      case 3:
        return '⭐⭐⭐';
      case 2:
        return '⭐⭐';
      default:
        return '⭐';
    }
  }

  String _getEncouragementMessage(int stars) {
    switch (stars) {
      case 3:
        return 'Outstanding! You\'re a superstar! 🌟';
      case 2:
        return 'Great job! Keep up the good work! 👏';
      default:
        return 'Good effort! Practice makes perfect! 💪';
    }
  }

  Future<void> _unlockNextUnit() async {
    try {
      // Get all units to find the next one
      final unitsSnapshot = await FirebaseFirestore.instance
          .collection(widget.collectionName)
          .doc(widget.contentId)
          .collection('units')
          .orderBy('order')
          .get();

      // Find current unit index
      int currentUnitIndex = -1;
      for (int i = 0; i < unitsSnapshot.docs.length; i++) {
        if (unitsSnapshot.docs[i].id == widget.unitId) {
          currentUnitIndex = i;
          break;
        }
      }

      // Unlock next unit if it exists
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
    final activityId = quizTask['activityId'];
    final lessonId = quizTask['lessonId'];
    final taskId = quizTask['taskId'];
    final taskData = quizTask['taskData'] as Map<String, dynamic>;
    final taskType = taskData['type'] ?? '';

    print(
      'Quiz: Displaying task ${currentTaskIndex + 1} of ${quizTasks.length}, type: $taskType',
    );

    // Note: We need to modify the task screens to accept a callback for correctness
    // For now, we'll use the existing screens and count completion as correct
    // In a full implementation, each screen would report if the answer was correct

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
          collectionName: widget.collectionName,
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
          collectionName: widget.collectionName,
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
          collectionName: widget.collectionName,
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
          collectionName: widget.collectionName,
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
          collectionName: widget.collectionName,
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
