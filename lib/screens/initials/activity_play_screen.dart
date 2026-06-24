import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/initials/activity_complete_screen.dart';
import 'package:loringo_app/screens/initials/screen_eight.dart';
import 'package:loringo_app/screens/initials/screen_nine.dart';
import 'package:loringo_app/screens/initials/screen_one.dart';
import 'package:loringo_app/screens/initials/screen_five.dart';
import 'package:loringo_app/screens/initials/screen_four.dart';
import 'package:loringo_app/screens/initials/screen_six.dart';
import 'package:loringo_app/screens/initials/screen_three.dart';
import 'package:loringo_app/screens/initials/screen_two.dart';
import 'package:loringo_app/screens/initials/screen_seven.dart';
import 'package:loringo_app/services/database/database.dart';

class ActivityPlayScreen extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final String activityTitle;
  final String? studentId;
  final int? xpBase;
  final int? bonusXP;
  final String collectionName;
  final bool isPreview;

  const ActivityPlayScreen({
    super.key,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.activityId,
    required this.activityTitle,
    this.studentId,
    this.xpBase,
    this.bonusXP,
    this.collectionName = 'content',
    this.isPreview = false,
  });

  @override
  State<ActivityPlayScreen> createState() => _ActivityPlayScreenState();
}

class _ActivityPlayScreenState extends State<ActivityPlayScreen> {
  List<DocumentSnapshot> tasks = [];
  int currentTaskIndex = 0;
  bool isLoading = true;
  int correctAnswers = 0;
  int wrongAnswers = 0;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(widget.collectionName)
          .doc(widget.contentId)
          .collection('units')
          .doc(widget.unitId)
          .collection('lessons')
          .doc(widget.lessonId)
          .collection('activities')
          .doc(widget.activityId)
          .collection('tasks')
          .orderBy('order')
          .get();

      setState(() {
        tasks = snapshot.docs;
        isLoading = false;
      });

      if (tasks.isEmpty) _showNoTasksDialog();
    } catch (e) {
      setState(() => isLoading = false);
      _showErrorDialog('Error loading tasks: $e');
    }
  }

  void _showNoTasksDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No Tasks'),
        content: const Text('This activity has no tasks yet.'),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('OK')),
        ],
      ),
    );
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
              child: const Text('OK')),
        ],
      ),
    );
  }

  void nextTask(bool isCorrect) {
    setState(() {
      if (isCorrect) correctAnswers++;
      else wrongAnswers++;
    });
    _advance();
  }

  void _nextReadingTask(bool pass, int subCorrect, int subWrong) {
    setState(() {
      correctAnswers += subCorrect;
      wrongAnswers   += subWrong;
    });
    _advance();
  }

  void _advance() {
    if (currentTaskIndex < tasks.length - 1) {
      setState(() => currentTaskIndex++);
    } else {
      _showCompletionDialog();
    }
  }

  void _showCompletionDialog() async {
    final db = Database();
    final totalQuestions = correctAnswers + wrongAnswers;
    final score = totalQuestions > 0
        ? ((correctAnswers / totalQuestions) * 100).round()
        : 0;

    int xpEarned = 0;
    try {
      if (!widget.isPreview && widget.studentId != null) {
        xpEarned = await db.saveActivityCompletion(
          studentId: widget.studentId!,
          activityId: widget.activityId,
          contentId: widget.contentId,
          unitId: widget.unitId,
          score: score,
          correctAnswers: correctAnswers,
          wrongAnswers: wrongAnswers,
          xpBase: widget.xpBase ?? 100,
          bonusXP: widget.bonusXP ?? 0,
        );
      }
    } catch (e) {
      debugPrint('Error saving activity progress: $e');
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityCompleteScreen(
          screenTitle: 'Activity Complete!', // ✅ Added missing parameter
          activityTitle: widget.activityTitle,
          scorePercent: score,
          correctAnswers: correctAnswers,
          wrongAnswers: wrongAnswers,
          xpEarned: xpEarned,
          isGraded: false,
        ),
      ),
    );
  }

  Widget _buildTaskScreen(DocumentSnapshot taskDoc) {
    final taskData = taskDoc.data() as Map<String, dynamic>;
    final taskType = taskData['type'] ?? '';

    switch (taskType) {
      case 'image_select':
        return ScreenOne(
          key: ValueKey(taskDoc.id),
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: widget.lessonId, activityId: widget.activityId,
          taskId: taskDoc.id, onTaskComplete: nextTask,
          currentTaskNumber: currentTaskIndex, totalTasks: tasks.length,
          collectionName: widget.collectionName,
        );

      case 'complete_the_chat':
        return ScreenTwo(
          key: ValueKey(taskDoc.id),
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: widget.lessonId, activityId: widget.activityId,
          taskId: taskDoc.id, onTaskComplete: nextTask,
          currentTaskNumber: currentTaskIndex, totalTasks: tasks.length,
          collectionName: widget.collectionName,
        );

      case 'arrange':
        return ScreenThree(
          key: ValueKey(taskDoc.id),
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: widget.lessonId, activityId: widget.activityId,
          taskId: taskDoc.id, onTaskComplete: nextTask,
          currentTaskNumber: currentTaskIndex, totalTasks: tasks.length,
          collectionName: widget.collectionName,
        );

      case 'fill_blank':
        return ScreenFour(
          key: ValueKey(taskDoc.id),
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: widget.lessonId, activityId: widget.activityId,
          taskId: taskDoc.id, onTaskComplete: nextTask,
          currentTaskNumber: currentTaskIndex, totalTasks: tasks.length,
          collectionName: widget.collectionName,
        );

      case 'image_select_reverse':
        return ScreenFive(
          key: ValueKey(taskDoc.id),
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: widget.lessonId, activityId: widget.activityId,
          taskId: taskDoc.id, onTaskComplete: nextTask,
          currentTaskNumber: currentTaskIndex, totalTasks: tasks.length,
          collectionName: widget.collectionName,
        );

      case 'match':
        return ScreenSix(
          key: ValueKey(taskDoc.id),
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: widget.lessonId, activityId: widget.activityId,
          taskId: taskDoc.id, onTaskComplete: nextTask,
          currentTaskNumber: currentTaskIndex, totalTasks: tasks.length,
          collectionName: widget.collectionName,
        );

      case 'reading':
        return ScreenSeven(
          key: ValueKey(taskDoc.id),
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: widget.lessonId, activityId: widget.activityId,
          taskId: taskDoc.id,
          onTaskComplete: _nextReadingTask,
          currentTaskNumber: currentTaskIndex, totalTasks: tasks.length,
          collectionName: widget.collectionName,
        );
      
      case 'sentence_builder':
        return ScreenEight(
          key: ValueKey(taskDoc.id),
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: widget.activityId,
          taskId: taskDoc.id,
          onTaskComplete: nextTask,
          currentTaskNumber: currentTaskIndex,
          totalTasks: tasks.length,
          collectionName: widget.collectionName,
        );
      
      case 'repeat_after_me':
        return ScreenNine(
          key: ValueKey(taskDoc.id),
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: widget.activityId,
          taskId: taskDoc.id,
          onTaskComplete: nextTask,
          currentTaskNumber: currentTaskIndex,
          totalTasks: tasks.length,
          collectionName: widget.collectionName,
        );

      default:
        return Scaffold(
          appBar: AppBar(
              title: Text(widget.activityTitle),
              backgroundColor: const Color(0xFF4CAF50)),
          body: Center(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              const Icon(Icons.error_outline, size: 100, color: Colors.grey),
              const SizedBox(height: 24),
              Text('Task type "$taskType" not yet implemented',
                  style: const TextStyle(fontSize: 18, color: Colors.grey)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => nextTask(false),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50)),
                child: const Text('Skip Task',
                    style: TextStyle(color: Colors.white)),
              ),
            ]),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (tasks.isEmpty) {
      return const Scaffold(body: Center(child: Text('No tasks available')));
    }
    return _buildTaskScreen(tasks[currentTaskIndex]);
  }
}