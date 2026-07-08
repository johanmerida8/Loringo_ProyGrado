import 'package:cloud_firestore/cloud_firestore.dart';
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

/// Play screen for LESSON quizzes only.
/// Lesson quizzes reuse existing activity tasks — they are NOT graded,
/// do NOT generate reports, and do NOT send notifications to parents.
/// XP is awarded on completion (not on passing a threshold).
class LessonQuizPlayScreen extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String lessonId;
  final String quizId;
  final String quizTitle;
  final String collectionName;
  final String? studentId;
  final bool isPreview;

  const LessonQuizPlayScreen({
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
  State<LessonQuizPlayScreen> createState() => _LessonQuizPlayScreenState();
}

class _LessonQuizPlayScreenState extends State<LessonQuizPlayScreen> {
  final Database _db = Database();
  
  List<Map<String, dynamic>> quizTasks = [];
  int currentTaskIndex = 0;
  int correctAnswers   = 0;
  int totalTasks       = 0;
  bool isLoading       = true;
  String loadingMessage = 'Loading quiz...';
  int _xpReward = 0;

  @override
  void initState() {
    super.initState();
    _loadQuizTasks();
  }

  Future<void> _loadQuizTasks() async {
    try {
      final quizDoc = await _db.getPersonalizedUnitQuiz(widget.quizId);
      
      if (!quizDoc.exists) {
        _showErrorDialog('Quiz not found');
        return;
      }

      final quizData = quizDoc.data() as Map<String, dynamic>;
      _xpReward = (quizData['xpReward'] as num? ?? 0).toInt();

      final List<String> questionIds =
          List<String>.from(quizData['questionIds'] ?? []);

      if (questionIds.isEmpty) {
        _showErrorDialog('This quiz has no questions');
        return;
      }

      final String defaultGroupId = '';
      
      final lessonsSnapshot = await _db.getPersonalizedLessons(
        defaultGroupId, 
        widget.contentId, 
        widget.unitId,
      );
      
      final Map<String, String> activityToLessonMap = {};
      for (final lessonDoc in lessonsSnapshot.docs) {
        final activitiesSnapshot = await _db.getPersonalizedActivities(
          defaultGroupId,
          widget.contentId,
          widget.unitId,
          lessonDoc.id,
        );
        for (final activityDoc in activitiesSnapshot.docs) {
          activityToLessonMap[activityDoc.id] = lessonDoc.id;
        }
      }

      final List<Map<String, dynamic>> loadedTasks = [];
      for (int i = 0; i < questionIds.length; i++) {
        setState(() => loadingMessage =
            'Loading question ${i + 1} of ${questionIds.length}...');

        const activityPrefix = 'activity_';
        if (!questionIds[i].startsWith(activityPrefix)) {
          continue;
        }

        final withoutPrefix = questionIds[i].substring(activityPrefix.length);
        final taskSeparatorIndex = withoutPrefix.indexOf('_task_');
        if (taskSeparatorIndex == -1) {
          continue;
        }

        final numericActivityId = withoutPrefix.substring(0, taskSeparatorIndex);
        final taskId = withoutPrefix.substring(taskSeparatorIndex + 6);
        final activityId = 'activity_$numericActivityId';

        final foundLessonId = activityToLessonMap[activityId];
        if (foundLessonId == null) {
          continue;
        }

        final tasksSnapshot = await _db.getPersonalizedTasks(
          defaultGroupId,
          widget.contentId,
          widget.unitId,
          foundLessonId,
          activityId,
        );
        
        QueryDocumentSnapshot? taskDoc;
        for (final doc in tasksSnapshot.docs) {
          if (doc.id == taskId) {
            taskDoc = doc;
            break;
          }
        }
        if (taskDoc == null) {
          continue;
        }

        loadedTasks.add({
          'activityId': activityId,
          'lessonId':   foundLessonId,
          'taskId':     taskId,
          'taskData':   taskDoc.data() as Map<String, dynamic>,
        });
      }

      setState(() {
        quizTasks  = loadedTasks;
        totalTasks = loadedTasks.length;
        isLoading  = false;
      });

      if (quizTasks.isEmpty) _showErrorDialog('No valid quiz questions found');
    } catch (e) {
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
    if (wasCorrect) correctAnswers++;
    if (currentTaskIndex < quizTasks.length - 1) {
      setState(() => currentTaskIndex++);
    } else {
      _showResults();
    }
  }

  void _nextReadingTask(bool pass, int subCorrect, int subWrong) {
    correctAnswers += subCorrect;
    if (currentTaskIndex < quizTasks.length - 1) {
      setState(() => currentTaskIndex++);
    } else {
      _showResults();
    }
  }

  Future<void> _showResults() async {
    final percentage = totalTasks > 0
        ? (correctAnswers / totalTasks * 100).round()
        : 0;
    final stars = percentage >= 90 ? 3 : percentage >= 70 ? 2 : 1;

    int xpEarned = 0;

    if (!widget.isPreview && widget.studentId != null) {
      try {
        final progressDoc = await _db.studentProgress(widget.studentId!)
            .doc(widget.quizId)
            .get();

        final wasCompleted = progressDoc.exists && 
            (progressDoc.data() as Map<String, dynamic>?)?['isCompleted'] == true;

        if (!wasCompleted) {
          xpEarned = (_xpReward * (percentage / 100)).round();
        }

        await _db.saveQuizCompletion(
          studentId:      widget.studentId!,
          quizId:         widget.quizId,
          contentId:      widget.contentId,
          unitId:         widget.unitId,
          score:          correctAnswers,
          totalQuestions: totalTasks,
          stars:          stars,
          xpEarned:       xpEarned,
          updateBestOnly: wasCompleted,
          unitTitle:      '',
          generateReport: false,
          reportType:     'lesson',
          // Lesson quizzes no tienen passingScore configurado por el
          // docente (no son graded) — se usa 70% como umbral solo para
          // que el campo 'passed' quede coherente en Firestore. No
          // bloquea ni desbloquea nada, a diferencia del unit quiz.
          passed:         percentage >= 70,
        );
      } catch (e) {
        debugPrint('Error saving lesson quiz progress: $e');
      }
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityCompleteScreen(
          screenTitle:    'Quiz Complete!',
          activityTitle:  widget.quizTitle,
          scorePercent:   percentage,
          correctAnswers: correctAnswers,
          wrongAnswers:   totalTasks - correctAnswers,
          xpEarned:       xpEarned,
          isGraded: false,
        ),
      ),
    );
  }

  Widget _buildTaskScreen(Map<String, dynamic> quizTask) {
    final activityId = quizTask['activityId'] as String;
    final lessonId   = quizTask['lessonId']   as String;
    final taskId     = quizTask['taskId']     as String;
    final taskData   = quizTask['taskData']   as Map<String, dynamic>;
    final taskType   = taskData['type']       as String? ?? '';

    switch (taskType) {
      case 'image_select':
        return ScreenOne(
          key: ValueKey(taskId),
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: lessonId, activityId: activityId, taskId: taskId,
          onTaskComplete: (ok) => _nextTask(wasCorrect: ok),
          currentTaskNumber: currentTaskIndex, totalTasks: quizTasks.length,
          collectionName: widget.collectionName,
        );
      case 'complete_the_chat':
        return ScreenTwo(
          key: ValueKey(taskId),
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: lessonId, activityId: activityId, taskId: taskId,
          onTaskComplete: (ok) => _nextTask(wasCorrect: ok),
          currentTaskNumber: currentTaskIndex, totalTasks: quizTasks.length,
          collectionName: widget.collectionName,
        );
      case 'arrange':
        return ScreenThree(
          key: ValueKey(taskId),
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: lessonId, activityId: activityId, taskId: taskId,
          onTaskComplete: (ok) => _nextTask(wasCorrect: ok),
          currentTaskNumber: currentTaskIndex, totalTasks: quizTasks.length,
          collectionName: widget.collectionName,
        );
      case 'fill_blank':
        return ScreenFour(
          key: ValueKey(taskId),
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: lessonId, activityId: activityId, taskId: taskId,
          onTaskComplete: (ok) => _nextTask(wasCorrect: ok),
          currentTaskNumber: currentTaskIndex, totalTasks: quizTasks.length,
          collectionName: widget.collectionName,
        );
      case 'image_select_reverse':
        return ScreenFive(
          key: ValueKey(taskId),
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: lessonId, activityId: activityId, taskId: taskId,
          onTaskComplete: (ok) => _nextTask(wasCorrect: ok),
          currentTaskNumber: currentTaskIndex, totalTasks: quizTasks.length,
          collectionName: widget.collectionName,
        );
      case 'match':
        return ScreenSix(
          key: ValueKey(taskId),
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: lessonId, activityId: activityId, taskId: taskId,
          onTaskComplete: (ok) => _nextTask(wasCorrect: ok),
          currentTaskNumber: currentTaskIndex, totalTasks: quizTasks.length,
          collectionName: widget.collectionName,
        );
      case 'reading':
        return ScreenSeven(
          key: ValueKey(taskId),
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: lessonId, activityId: activityId, taskId: taskId,
          onTaskComplete: _nextReadingTask,
          currentTaskNumber: currentTaskIndex, totalTasks: quizTasks.length,
          collectionName: widget.collectionName,
        );
      default:
        return Scaffold(
          appBar: AppBar(title: Text(widget.quizTitle), backgroundColor: const Color(0xFF4CAF50)),
          body: Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.error_outline, size: 80, color: Colors.grey),
              const SizedBox(height: 20),
              Text('Task type "$taskType" not supported',
                  style: const TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _nextTask(wasCorrect: false),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50)),
                child: const Text('Skip', style: TextStyle(color: Colors.white)),
              ),
            ]),
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
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(loadingMessage, style: const TextStyle(fontSize: 16, color: Colors.grey)),
          ]),
        ),
      );
    }

    if (quizTasks.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.quizTitle), backgroundColor: const Color(0xFF4CAF50)),
        body: const Center(child: Text('No quiz questions available')),
      );
    }

    return _buildTaskScreen(quizTasks[currentTaskIndex]);
  }
}