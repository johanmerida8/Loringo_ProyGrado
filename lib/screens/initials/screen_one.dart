// screen_one.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
// import 'package:just_audio/just_audio.dart';
import 'package:loringo_app/screens/initials/widget/responsive_activity_shell.dart';
import 'package:loringo_app/screens/initials/widget/retryable_task.dart';
import 'package:loringo_app/screens/initials/widget/task_exit_guard.dart';
import 'package:loringo_app/screens/initials/widget/task_result_sheet.dart';
// import 'package:loringo_app/services/audio/feedback_sound_service.dart';
import 'package:loringo_app/services/audio/task_feedback.dart';
// import 'package:lottie/lottie.dart';
import 'package:loringo_app/screens/initials/widget/exit_task_dialog.dart';

class ScreenOne extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final String taskId;
  final Function(bool isCorrect)? onTaskComplete;
  final int currentTaskNumber;
  final int totalTasks;
  final String collectionName;
  final bool isPracticeRound;

  const ScreenOne({
    super.key,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.activityId,
    required this.taskId,
    this.onTaskComplete,
    this.currentTaskNumber = 1,
    this.totalTasks = 1,
    this.collectionName = 'content',
    this.isPracticeRound = false,
  });

  @override
  State<ScreenOne> createState() => _ScreenOneState();
}

class _ScreenOneState extends State<ScreenOne> with RetryableTask {
  // final player = AudioPlayer();

  String word = '';
  List<Map<String, dynamic>> options = [];
  String selectedOption = '';

  static const Color greenPrimary = Color(0xFF4CAF50);
  static const Color greyAccent = Color(0xFF81C784);

  @override
  void initState() {
    super.initState();
    _fetchTask();
  }

  Future<void> _fetchTask() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(widget.collectionName)
          .doc(widget.contentId)
          .collection('units')
          .doc(widget.unitId)
          .collection('lessons')
          .doc(widget.lessonId)
          .collection('activities')
          .doc(widget.activityId)
          .collection('tasks')
          .doc(widget.taskId)
          .get();

      if (doc.exists) {
        final taskData = doc.data();
        if (taskData != null && taskData['type'] == 'image_select') {
          final data = taskData['data'] as Map<String, dynamic>? ?? {};
          
          setState(() {
            word = data['word'] ?? taskData['question'] ?? '';
            options = List<Map<String, dynamic>>.from(data['options'] ?? []);
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching task: $e');
    }
  }

  void _handleSelection(String text) {
    setState(() {
      selectedOption = text;
    });
  }

  Future<void> _handleClose() async {
    final shouldExit = await confirmExitTask(context);
    if (shouldExit && context.mounted) Navigator.pop(context);
  }

  void _checkAnswer() {
    final option = options.firstWhere(
      (option) => option['text'] == selectedOption,
      orElse: () => {},
    );
    final bool isCorrect = option['isCorrect'] == true;

    TaskFeedback.fire(isCorrect);

    // Soft wrong answer with attempts left -> offerRetry shows the
    // retry-prompt sheet and clears the selection itself; nothing was
    // scored yet, so don't fall through to TaskResultSheet.
    if (!isCorrect &&
        offerRetry(
          context: context,
          onRetry: () => setState(() => selectedOption = ''),
        )) {
      return;
    }

    TaskResultSheet.show(
      context,
      isCorrect: isCorrect,
      isPracticeRound: widget.isPracticeRound,
      onContinue: () {
        // Both correct and (hard) wrong now advance — ActivityPlayScreen
        // owns the retry/review-round logic (wrong tasks get queued for a
        // practice round at the end instead of being retried in place
        // here). This screen no longer resets its own selection on a
        // wrong answer.
        widget.onTaskComplete?.call(isCorrect);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const backgroundGradient = LinearGradient(
      colors: [Color(0xFFE8F5E9), Colors.white],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    return TaskExitGuard(
      onRequestExit: _handleClose,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: backgroundGradient),
          child: SafeArea(
            child: options.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ResponsiveActivityShell(
                  child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: _handleClose,
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.black87,
                                  size: 28,
                                ),
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.all(
                                    Radius.circular(30),
                                  ),
                                  child: LinearProgressIndicator(
                                    value: widget.currentTaskNumber / widget.totalTasks,
                                    backgroundColor: Colors.blueGrey,
                                    valueColor: const AlwaysStoppedAnimation<Color>(
                                      greenPrimary,
                                    ),
                                    minHeight: 8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ── Prompt word ──────────────────────────────────────
                        // Static label icon, no audio button — reading the
                        // word aloud isn't part of this exercise's mechanic
                        // (that's what sound_match is for). The word is
                        // already shown as text, so a TTS button here would
                        // just be a redundant "read what you're already
                        // reading" control.
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.text_fields,
                                color: Colors.black87,
                                size: 28,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  word,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Select the correct image',
                          style: TextStyle(fontSize: 20, color: Colors.black54),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final metrics = ResponsiveActivityMetrics(
                                  isWide: constraints.maxWidth >= kActivityWideBreakpoint,
                                  availableWidth: constraints.maxWidth,
                                );
                                return GridView.builder(
                                  itemCount: options.length,
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: metrics.imageGridCrossAxisCount,
                                    mainAxisSpacing: 16,
                                    crossAxisSpacing: 16,
                                    childAspectRatio: metrics.imageOptionAspectRatio,
                                  ),
                                  itemBuilder: (context, index) {
                                    final option = options[index];
                                    final isSelected = selectedOption == option['text'];
                                    return GestureDetector(
                                      onTap: () => _handleSelection(option['text']),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 300),
                                        decoration: BoxDecoration(
                                          color: isSelected ? greenPrimary : Colors.white,
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: isSelected ? greenPrimary : greyAccent,
                                            width: 4,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black12,
                                              blurRadius: 10,
                                              offset: Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Center(
                                          child: Padding(
                                            padding: const EdgeInsets.all(12.0),
                                            child: option['image'].toString().endsWith('.svg') &&
                                                !option['image'].toString().contains('f_png')
                                                ? SvgPicture.network(
                                                    option['image'],
                                                    fit: BoxFit.contain,
                                                    placeholderBuilder: (context) =>
                                                        const CircularProgressIndicator(),
                                                  )
                                                : CachedNetworkImage(
                                                    imageUrl: option['image'],
                                                    placeholder: (_, __) =>
                                                        const CircularProgressIndicator(),
                                                    errorWidget: (_, __, ___) =>
                                                        const Icon(Icons.error),
                                                    fit: BoxFit.contain,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 20,
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: selectedOption.isEmpty ? null : _checkAnswer,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: greenPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 5,
                              ),
                              child: const Text(
                                'Check',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ),
          ),
        ),
      ),
    );
  }
}