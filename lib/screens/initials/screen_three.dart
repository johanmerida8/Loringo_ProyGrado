// screen_three.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
// import 'package:just_audio/just_audio.dart';
import 'package:loringo_app/screens/initials/widget/responsive_activity_shell.dart';
import 'package:loringo_app/screens/initials/widget/retryable_task.dart';
import 'package:loringo_app/screens/initials/widget/task_exit_guard.dart';
import 'package:loringo_app/screens/initials/widget/task_result_sheet.dart';
// import 'package:loringo_app/services/audio/feedback_sound_service.dart';
import 'package:loringo_app/services/audio/task_feedback.dart';
// import 'package:lottie/lottie.dart';
import 'package:loringo_app/screens/initials/widget/exit_task_dialog.dart';

class ScreenThree extends StatefulWidget {
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

  const ScreenThree({
    super.key,
    required this.contentId,
    required this.unitId,
    required this.lessonId,
    required this.activityId,
    required this.taskId,
    required this.onTaskComplete,
    required this.currentTaskNumber,
    required this.totalTasks,
    this.collectionName = 'content',
    this.isPracticeRound = false,
  });

  @override
  State<ScreenThree> createState() => _ScreenThreeState();
}

class _ScreenThreeState extends State<ScreenThree> with RetryableTask {
  // final AudioPlayer player = AudioPlayer();
  final FlutterTts flutterTts = FlutterTts();
  OnDeviceTranslator? translator; // ✅ Make it nullable

  static const Color greenPrimary = Color(0xFF4CAF50);

  String _userLang = 'English';
  String subtitle = '';
  String questionEn = '';
  String taskTitle = 'Arrange the words to form a sentence'; // Default title
  List<String> answerEn = [];
  List<Map<String, String>> shuffledWords = [];
  List<Map<String, String>> selectedWords = [];

  @override
  void initState() {
    super.initState();
    _setUp();
  }

  Future<void> _setUp() async {
    // await _initTranslator();
    await _initializeTts();
    await _fetchTask();
  }

  Future<void> _initializeTts() async {
    try {
      await flutterTts.setSpeechRate(0.5);
      await flutterTts.setPitch(1.0);
      await flutterTts.setLanguage('en-GB');
    } catch (e) {
      debugPrint('Error initializing TTS: $e');
    }
  }

  @override
  void dispose() {
    translator?.close(); // ✅ Safe close
    // player.dispose();
    flutterTts.stop();
    super.dispose();
  }

  Future<void> _fetchTask() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(widget.collectionName)
          .doc(widget.contentId)
          .collection('units').doc(widget.unitId)
          .collection('lessons').doc(widget.lessonId)
          .collection('activities').doc(widget.activityId)
          .collection('tasks').doc(widget.taskId)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final taskData = data['data'] as Map<String, dynamic>? ?? data;

        // Fetch all task data
        subtitle = taskData['subtitle'] ?? '';
        questionEn = taskData['question'] ?? '';
        taskTitle = taskData['taskTitle'] ?? 'Arrange the words to form a sentence';
        answerEn = List<String>.from(taskData['answer'] ?? []);

        // Build shuffled word pool
        shuffledWords = answerEn
            .map((word) => {'en': word})
            .toList();
        shuffledWords.shuffle();

        if (translator != null && _userLang != 'English') {
        }

        setState(() {});
      }
    } catch (e) {
      debugPrint('Error fetching task data: $e');
    }
  }

  Future<void> _speak(String text) async {
    if (text.isNotEmpty) {
      try {
        await flutterTts.setLanguage('en-GB');
        await flutterTts.speak(text);
      } catch (e) {
        debugPrint('Error speaking: $e');
      }
    }
  }

  void _selectWord(Map<String, String> word) {
    setState(() {
      selectedWords.add(word);
      shuffledWords.remove(word);
      
      // Auto-speak when sentence is complete
      if (selectedWords.length == answerEn.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _speak(selectedWords.map((w) => w['en']).join(' '));
        });
      }
    });
  }

  void _removeWord(Map<String, String> word) {
    setState(() {
      shuffledWords.add(word);
      selectedWords.remove(word);
    });
  }

  Future<void> _handleClose() async {
    final shouldExit = await confirmExitTask(context);
    if (shouldExit && context.mounted) Navigator.pop(context);
  }

  /// Undoes the whole built sentence back into the word pool, re-shuffled
  /// — used as the retry callback so the student rebuilds from scratch
  /// rather than nudging a mostly-correct-looking arrangement.
  void _clearSelectionForRetry() {
    setState(() {
      shuffledWords.addAll(selectedWords);
      selectedWords.clear();
      shuffledWords.shuffle();
    });
  }

  void _checkAnswer() {
    final selected = selectedWords.map((w) => w['en']).toList();
    final isCorrect = selected.join(' ') == answerEn.join(' ');

    TaskFeedback.fire(isCorrect);

    if (!isCorrect &&
        offerRetry(context: context, onRetry: _clearSelectionForRetry)) {
      return;
    }

    TaskResultSheet.show(
      context,
      isCorrect: isCorrect,
      isPracticeRound: widget.isPracticeRound,
      onContinue: () {
        // Both correct and (hard) wrong now advance — ActivityPlayScreen
        // queues wrong tasks for a practice round at the end instead of
        // this screen retrying in place.
        widget.onTaskComplete?.call(isCorrect);
      },
    );
  }

  Widget _buildAnswerArea() {
    const int maxLines = 4;
    const double lineHeight = 56.0;
    const double sheetHeight = maxLines * lineHeight;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      height: sheetHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Stack(
        children: [
          // ── Background ruled lines ──────────────────────────────────
          Column(
            children: List.generate(maxLines, (index) {
              return Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.blueGrey.shade50,
                        width: 1,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),

          // ── Word chips with speaker button ──────────────────────────────
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.start,
                    children: selectedWords.isEmpty
                        ? [
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  'Tap words below to build the sentence',
                                  style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                                ),
                              ),
                            ),
                          ]
                        : selectedWords.map((word) {
                            return GestureDetector(
                              onTap: () => _removeWord(word),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: greenPrimary, width: 1.5),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: greenPrimary.withOpacity(0.12),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  word['en']!,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                  ),
                ),
                // ── Speaker button ──────────────────────────────────────
                if (selectedWords.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: IconButton(
                      icon: Icon(Icons.volume_up, color: greenPrimary, size: 24),
                      onPressed: () => _speak(
                        selectedWords.map((w) => w['en']).join(' ')
                      ),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────
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
            child: shuffledWords.isEmpty && selectedWords.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ResponsiveActivityShell(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Progress header ─────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.black87, size: 28),
                                onPressed: _handleClose,
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.all(Radius.circular(30)),
                                  child: LinearProgressIndicator(
                                    value: (widget.currentTaskNumber + 1) / widget.totalTasks,
                                    backgroundColor: Colors.blueGrey,
                                    valueColor: const AlwaysStoppedAnimation<Color>(greenPrimary),
                                    minHeight: 8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                  
                        // ── TASK TITLE ──────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: greenPrimary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: greenPrimary.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.abc, color: greenPrimary, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    taskTitle,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: greenPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  
                        // ── Subtitle / instruction ──────────────────────────────
                        if (subtitle.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            child: Text(
                              subtitle,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                  
                        // ── Question ────────────────────────────────────────────
                        if (questionEn.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                            child: Text(
                              questionEn,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black54,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                  
                        const SizedBox(height: 12),
                  
                        // ── Answer sheet ────────────────────────────────────────
                        _buildAnswerArea(),
                  
                        const SizedBox(height: 20),
                  
                        // ── Word pool ───────────────────────────────────────────
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: SingleChildScrollView(
                              child: Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: shuffledWords.map((word) {
                                  return GestureDetector(
                                    onTap: () => _selectWord(word),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(color: greenPrimary, width: 2),
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.grey.withOpacity(0.15),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        word['en']!,
                                        style: const TextStyle(
                                          color: Colors.black87,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                  
                        // ── Check button ────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: selectedWords.length == answerEn.length
                                  ? _checkAnswer
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: greenPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                elevation: 5,
                              ),
                              child: const Text(
                                'Check',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                  color: Colors.white,
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