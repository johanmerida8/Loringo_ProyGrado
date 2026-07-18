// screen_eleven.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:loringo_app/screens/initials/widget/responsive_activity_shell.dart';
import 'package:loringo_app/screens/initials/widget/retryable_task.dart';
import 'package:loringo_app/screens/initials/widget/task_exit_guard.dart';
import 'package:loringo_app/screens/initials/widget/task_result_sheet.dart';
import 'package:loringo_app/services/audio/task_feedback.dart';
import 'package:loringo_app/screens/initials/widget/exit_task_dialog.dart';

/// SOUND MATCH
/// The student hears a word spoken aloud and taps the matching image.
/// Unlike ScreenOne (image_select), no text label is shown anywhere on
/// screen — the prompt is audio-only, so the student can't read their way
/// to the answer. The word replays on load and again any time the speaker
/// icon is tapped.
class ScreenEleven extends StatefulWidget {
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

  const ScreenEleven({
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
  State<ScreenEleven> createState() => _ScreenElevenState();
}

class _ScreenElevenState extends State<ScreenEleven> with RetryableTask {
  final FlutterTts flutterTts = FlutterTts();

  String audioText = '';
  List<Map<String, dynamic>> options = [];
  int selectedIndex = -1;

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
        if (taskData != null && taskData['type'] == 'sound_match') {
          final data = taskData['data'] as Map<String, dynamic>? ?? {};

          setState(() {
            audioText = data['audioText'] ?? '';
            options = List<Map<String, dynamic>>.from(data['options'] ?? []);
          });

          // Play the prompt as soon as the task is ready — the student
          // shouldn't have to tap the speaker just to hear it once.
          if (audioText.isNotEmpty) _speak(audioText);
        }
      }
    } catch (e) {
      debugPrint('Error fetching task: $e');
    }
  }

  void _speak(String text) async {
    await flutterTts.setLanguage('en-GB');
    await flutterTts.speak(text);
  }

  void _handleSelection(int index) {
    setState(() {
      selectedIndex = index;
    });
  }

  Future<void> _handleClose() async {
    final shouldExit = await confirmExitTask(context);
    if (shouldExit && context.mounted) Navigator.pop(context);
  }

  void _checkAnswer() {
    final option = options[selectedIndex];
    final bool isCorrect = option['isCorrect'] == true;

    TaskFeedback.fire(isCorrect);

    if (!isCorrect &&
        offerRetry(
          context: context,
          onRetry: () => setState(() => selectedIndex = -1),
        )) {
      return;
    }

    TaskResultSheet.show(
      context,
      isCorrect: isCorrect,
      isPracticeRound: widget.isPracticeRound,
      onContinue: () {
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
                        const SizedBox(height: 8),
                        // ── Speaker prompt ────────────────────────────────
                        // No text label here on purpose — this is a
                        // listening exercise. The big tappable speaker icon
                        // both signals "listen" and lets the student replay
                        // the word as many times as they need.
                        GestureDetector(
                          onTap: () => _speak(audioText),
                          child: Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: greenPrimary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: greenPrimary.withOpacity(0.35),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.volume_up,
                              color: Colors.white,
                              size: 44,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Listen and tap the picture',
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
                                    final isSelected = selectedIndex == index;
                                    return GestureDetector(
                                      onTap: () => _handleSelection(index),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 300),
                                        decoration: BoxDecoration(
                                          color: isSelected ? greenPrimary : Colors.white,
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(
                                            color: isSelected ? greenPrimary : greyAccent,
                                            width: 4,
                                          ),
                                          boxShadow: const [
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
                              onPressed: selectedIndex == -1 ? null : _checkAnswer,
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