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
import 'package:loringo_app/screens/initials/screen_ten.dart';
import 'package:loringo_app/screens/initials/screen_eleven.dart';
import 'package:loringo_app/screens/initials/screen_twelve.dart';
import 'package:loringo_app/screens/initials/screen_three.dart';
import 'package:loringo_app/screens/initials/screen_two.dart';
import 'package:loringo_app/screens/initials/screen_seven.dart';
import 'package:loringo_app/screens/initials/widget/practice_round_intro_screen.dart';
import 'package:loringo_app/services/database/database.dart';

// NOTE — slow_reveal discontinued: the task type formerly mapped to
// screen_thirteen has been fully removed from the app. screen_thirteen.dart
// now implements 'compare' instead (its content was replaced, not just its
// wiring here). A brand-new screen_fourteen.dart implements 'flashcard'.
// See the 'compare' and 'flashcard' cases in _buildTaskScreen below.

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

  // ── Review round state ──────────────────────────────────────────────────
  // Any task answered wrong on its first attempt (during the main pass)
  // gets queued here by doc ID. Once the main pass finishes, if this list
  // isn't empty, we switch into a second pass over just these tasks —
  // retry-until-correct, no scoring impact — instead of going straight to
  // the completion screen. First-attempt score from the main pass is what
  // ultimately gets saved; the review round is purely for reinforcement.
  final List<String> wrongTaskIds = [];
  bool inReviewRound = false;
  List<DocumentSnapshot> reviewTasks = [];
  int reviewIndex = 0;

  // True while the one-time parrot intro screen is being shown, right
  // when the review round starts and before its first task appears.
  bool showingPracticeIntro = false;

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

  /// Called by every one of the 13 single-answer task screens via
  /// onTaskComplete. Splits behavior depending on whether we're in the
  /// main pass or the review round — see the two private handlers below.
  void nextTask(bool isCorrect) {
    if (inReviewRound) {
      _handleReviewAnswer(isCorrect);
    } else {
      _handleMainPassAnswer(isCorrect);
    }
  }

  void _handleMainPassAnswer(bool isCorrect) {
    setState(() {
      if (isCorrect) {
        correctAnswers++;
      } else {
        wrongAnswers++;
        wrongTaskIds.add(tasks[currentTaskIndex].id);
      }
    });
    _advanceMainPass();
  }

  void _handleReviewAnswer(bool isCorrect) {
    if (isCorrect) {
      _advanceReviewRound();
    } else {
      // Wrong during review: stay on the same task. Every one of the 13
      // task screens already shows its own wrong-answer feedback (red
      // state, fail sound/animation) before calling onTaskComplete, so
      // there's nothing extra to display here — just don't advance.
      // The task screen itself is responsible for resetting its local
      // input state on redisplay (same widget, same key, still mounted).
      setState(() {}); // no-op state touch to keep things consistent if needed
    }
  }

  /// Shared by any multi-sub-question task type (currently 'reading' and
  /// 'flashcard') where a single task document contains several
  /// independently-scored sub-answers. [pass] means "the student
  /// completed the whole task" (not necessarily a perfect score);
  /// [subCorrect]/[subWrong] are added directly to the running
  /// correctAnswers/wrongAnswers tally so partial credit is reflected in
  /// the final activity score exactly as if each sub-answer had been its
  /// own task.
  void _nextMultiPartTask(bool pass, int subCorrect, int subWrong) {
    if (inReviewRound) {
      // Multi-part tasks are only re-attempted as a whole during review;
      // sub-scores don't affect the locked-in main-pass score at that
      // point. Advance once the whole task passes again.
      if (pass) _advanceReviewRound();
      return;
    }
    setState(() {
      correctAnswers += subCorrect;
      wrongAnswers += subWrong;
      if (!pass) wrongTaskIds.add(tasks[currentTaskIndex].id);
    });
    _advanceMainPass();
  }

  void _advanceMainPass() {
    if (currentTaskIndex < tasks.length - 1) {
      setState(() => currentTaskIndex++);
      return;
    }

    // Main pass just finished. If anything was answered wrong, start the
    // review round instead of completing immediately.
    if (wrongTaskIds.isNotEmpty) {
      final wrongSet = wrongTaskIds.toSet();
      setState(() {
        reviewTasks = tasks.where((t) => wrongSet.contains(t.id)).toList();
        inReviewRound = true;
        reviewIndex = 0;
        // Show the parrot intro once, before the first repeated task —
        // the review round's tasks themselves aren't displayed until the
        // student taps through this screen.
        showingPracticeIntro = true;
      });
      return;
    }

    _showCompletionDialog();
  }

  void _advanceReviewRound() {
    if (reviewIndex < reviewTasks.length - 1) {
      setState(() => reviewIndex++);
      return;
    }
    _showCompletionDialog();
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
          screenTitle: 'Activity Complete!',
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

    // During the review round, task numbering shown to the student
    // reflects the review round itself (e.g. "Review 1 of 3"), not the
    // original task's position in the full activity — that number is no
    // longer meaningful once we're only replaying a subset.
    final displayNumber = inReviewRound ? reviewIndex : currentTaskIndex;
    final displayTotal = inReviewRound ? reviewTasks.length : tasks.length;

    // ── Key ───────────────────────────────────────────────────────────
    // A task can appear twice across the lifetime of this screen: once
    // in the main pass, once again in the review round if it was
    // answered wrong. Using the same ValueKey(taskDoc.id) both times
    // would make Flutter treat it as "the same widget, just rebuilt" and
    // reuse the existing State object — so leftover selection state from
    // the wrong answer (selectedOption, selectedIndex, selected words,
    // etc. in whichever task screen) would still be sitting there when
    // the student sees it again, pre-marking their previous wrong choice
    // instead of presenting a clean slate.
    //
    // Suffixing the key with the round forces Flutter to see a different
    // widget identity between passes, so it destroys the old State and
    // creates a fresh one — initState() runs again, every local field
    // resets to its declared default, exactly as if the screen were
    // opened for the first time.
    final taskKey = ValueKey(
      inReviewRound ? '${taskDoc.id}_review' : taskDoc.id,
    );

    switch (taskType) {
      case 'image_select':
        return ScreenOne(
          key: taskKey,
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: widget.lessonId, activityId: widget.activityId,
          taskId: taskDoc.id, onTaskComplete: nextTask,
          currentTaskNumber: displayNumber, totalTasks: displayTotal,
          collectionName: widget.collectionName,
          isPracticeRound: inReviewRound,
        );

      case 'complete_the_chat':
        return ScreenTwo(
          key: taskKey,
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: widget.lessonId, activityId: widget.activityId,
          taskId: taskDoc.id, onTaskComplete: nextTask,
          currentTaskNumber: displayNumber, totalTasks: displayTotal,
          collectionName: widget.collectionName,
          isPracticeRound: inReviewRound,
        );

      case 'arrange':
        return ScreenThree(
          key: taskKey,
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: widget.lessonId, activityId: widget.activityId,
          taskId: taskDoc.id, onTaskComplete: nextTask,
          currentTaskNumber: displayNumber, totalTasks: displayTotal,
          collectionName: widget.collectionName,
          isPracticeRound: inReviewRound,
        );

      case 'fill_blank':
        return ScreenFour(
          key: taskKey,
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: widget.lessonId, activityId: widget.activityId,
          taskId: taskDoc.id, onTaskComplete: nextTask,
          currentTaskNumber: displayNumber, totalTasks: displayTotal,
          collectionName: widget.collectionName,
          isPracticeRound: inReviewRound,
        );

      case 'image_select_reverse':
        return ScreenFive(
          key: taskKey,
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: widget.lessonId, activityId: widget.activityId,
          taskId: taskDoc.id, onTaskComplete: nextTask,
          currentTaskNumber: displayNumber, totalTasks: displayTotal,
          collectionName: widget.collectionName,
          isPracticeRound: inReviewRound,
        );

      case 'match':
        return ScreenSix(
          key: taskKey,
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: widget.lessonId, activityId: widget.activityId,
          taskId: taskDoc.id, onTaskComplete: nextTask,
          currentTaskNumber: displayNumber, totalTasks: displayTotal,
          collectionName: widget.collectionName,
          isPracticeRound: inReviewRound,
        );

      case 'reading':
        return ScreenSeven(
          key: taskKey,
          contentId: widget.contentId, unitId: widget.unitId,
          lessonId: widget.lessonId, activityId: widget.activityId,
          taskId: taskDoc.id,
          onTaskComplete: _nextMultiPartTask,
          currentTaskNumber: displayNumber, totalTasks: displayTotal,
          collectionName: widget.collectionName,
          isPracticeRound: inReviewRound,
        );

      case 'sentence_builder':
        return ScreenEight(
          key: taskKey,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: widget.activityId,
          taskId: taskDoc.id,
          onTaskComplete: nextTask,
          currentTaskNumber: displayNumber,
          totalTasks: displayTotal,
          collectionName: widget.collectionName,
          isPracticeRound: inReviewRound,
        );

      case 'repeat_after_me':
        return ScreenNine(
          key: taskKey,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: widget.activityId,
          taskId: taskDoc.id,
          onTaskComplete: nextTask,
          currentTaskNumber: displayNumber,
          totalTasks: displayTotal,
          collectionName: widget.collectionName,
          isPracticeRound: inReviewRound,
        );

      case 'listen_and_speak':
        return ScreenTen(
          key: taskKey,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: widget.activityId,
          taskId: taskDoc.id,
          onTaskComplete: nextTask,
          currentTaskNumber: displayNumber,
          totalTasks: displayTotal,
          collectionName: widget.collectionName,
          isPracticeRound: inReviewRound,
        );

      case 'sound_match':
        return ScreenEleven(
          key: taskKey,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: widget.activityId,
          taskId: taskDoc.id,
          onTaskComplete: nextTask,
          currentTaskNumber: displayNumber,
          totalTasks: displayTotal,
          collectionName: widget.collectionName,
          isPracticeRound: inReviewRound,
        );

      case 'odd_one_out':
        return ScreenTwelve(
          key: taskKey,
          contentId: widget.contentId,
          unitId: widget.unitId,
          lessonId: widget.lessonId,
          activityId: widget.activityId,
          taskId: taskDoc.id,
          onTaskComplete: nextTask,
          currentTaskNumber: displayNumber,
          totalTasks: displayTotal,
          collectionName: widget.collectionName,
          isPracticeRound: inReviewRound,
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

    if (showingPracticeIntro) {
      return PracticeRoundIntroScreen(
        taskCount: reviewTasks.length,
        onContinue: () => setState(() => showingPracticeIntro = false),
      );
    }

    final activeTaskDoc =
        inReviewRound ? reviewTasks[reviewIndex] : tasks[currentTaskIndex];

    // Wrapped in Material: the outer Stack here sits outside any of the
    // individual task screens' own Scaffold/Material ancestry (each task
    // screen provides its own Scaffold internally, but this Stack is a
    // sibling wrapper around it). Without a Material ancestor at this
    // level, Text widgets painted directly in this Stack (the review
    // banner) fall back to an ambient default TextStyle that can render
    // with a stray underline — exactly the artifact seen under "Practice
    // Round". Wrapping in a transparent Material fixes the ambient style;
    // the explicit TextDecoration.none on the banner's own Text is a
    // second line of defense.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          _buildTaskScreen(activeTaskDoc),
          if (inReviewRound) const _ReviewRoundBanner(),
        ],
      ),
    );
  }
}

/// Small persistent banner shown during the review round so the student
/// understands why they're seeing tasks again — without this, replaying
/// a task with no explanation could read as a bug rather than intentional
/// reinforcement practice.
class _ReviewRoundBanner extends StatelessWidget {
  const _ReviewRoundBanner();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.shade600,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.replay_rounded, size: 14, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'Practice Round',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}