// screen_three.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
// import 'package:just_audio/just_audio.dart';
import 'package:loringo_app/screens/initials/widget/responsive_activity_shell.dart';
import 'package:loringo_app/screens/initials/widget/task_result_sheet.dart';
import 'package:loringo_app/services/audio/feedback_sound_service.dart';
import 'package:loringo_app/services/audio/task_feedback.dart';
import 'package:lottie/lottie.dart';
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
  });

  @override
  State<ScreenThree> createState() => _ScreenThreeState();
}

class _ScreenThreeState extends State<ScreenThree> {
  // final AudioPlayer player = AudioPlayer();
  final FlutterTts flutterTts = FlutterTts();
  late OnDeviceTranslator? translator; // ✅ Make it nullable

  static const Color greenPrimary = Color(0xFF4CAF50);

  String _userLang = 'English';
  String subtitle = '';
  String questionEn = '';
  List<String> answerEn = [];
  List<Map<String, String>> shuffledWords = [];
  List<Map<String, String>> selectedWords = [];

  @override
  void initState() {
    super.initState();
    _setUp();
  }

  Future<void> _setUp() async {
    await _initTranslator();
    await _initializeTts();
    await _fetchTask();
  }

  Future<void> _initTranslator() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      String userLang = 'Spanish';
      
      if (userId != null) {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection("users")
              .doc(userId)
              .get();
          
          if (userDoc.exists) {
            final data = userDoc.data();
            // ✅ Safe access with null check
            userLang = (data?['language'] as String?) ?? 'Spanish';
          }
        } catch (e) {
          debugPrint('Error fetching user language: $e');
          userLang = 'Spanish';
        }
      }
      
      _userLang = userLang;
      
      // ✅ Initialize translator safely
      try {
        translator = OnDeviceTranslator(
          sourceLanguage: TranslateLanguage.english,
          targetLanguage: _mapLanguageToEnum(userLang),
        );
      } catch (e) {
        debugPrint('Error initializing translator: $e');
        translator = null; // Set to null if initialization fails
      }
      
    } catch (e) {
      debugPrint('Error in _initTranslator: $e');
      translator = null;
    }
  }

  TranslateLanguage _mapLanguageToEnum(String lang) {
    switch (lang.toLowerCase()) {
      case 'spanish': return TranslateLanguage.spanish;
      case 'french':  return TranslateLanguage.french;
      case 'german':  return TranslateLanguage.german;
      case 'italian': return TranslateLanguage.italian;
      default:        return TranslateLanguage.spanish;
    }
  }

  Future<void> _initializeTts() async {
    try {
      await flutterTts.setSpeechRate(0.5);
      await flutterTts.setPitch(1.0);
      await flutterTts.setLanguage('en-US');
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

        subtitle = taskData['subtitle'] ?? '';
        questionEn = taskData['question'] ?? '';
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

  void _checkAnswer() {
    final selected = selectedWords.map((w) => w['en']).toList();
    final isCorrect = selected.join(' ') == answerEn.join(' ');

    TaskFeedback.fire(isCorrect);

    TaskResultSheet.show(
      context,
      isCorrect: isCorrect,
      onContinue: () {
        if (isCorrect) {
          widget.onTaskComplete?.call(true);
        } else {
          _resetWordsForRetry();
        }
      },
    );
  }

  // void _playFeedback(bool isCorrect) async {
  //   try {
  //     isCorrect ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact();

  //     FeedbackSoundService.instance.playResult(isCorrect);
  //   } catch (e) {
  //     debugPrint('Error playing sound: $e');
  //   }
  //   _showResultBottomSheet(isCorrect ? 'success' : 'fail', isCorrect);
  // }

  /// Puts every word back in the pool and reshuffles it, so a retry starts
  /// from a clean slate rather than re-showing the wrong arrangement.
  void _resetWordsForRetry() {
    setState(() {
      selectedWords = [];
      shuffledWords = answerEn.map((w) => {'en': w}).toList()..shuffle();
    });
  }

  // void _showResultBottomSheet(String animationType, bool isCorrect) {
  //   showModalBottomSheet(
  //     context: context,
  //     backgroundColor: Colors.transparent,
  //     isScrollControlled: true,
  //     // Locked: must use the button to proceed, no swipe/tap-out escape.
  //     isDismissible: false,
  //     enableDrag: false,
  //     builder: (_) => DraggableScrollableSheet(
  //       initialChildSize: 0.4,
  //       maxChildSize: 0.6,
  //       builder: (_, controller) => Container(
  //         padding: const EdgeInsets.all(16),
  //         decoration: const BoxDecoration(
  //           color: Colors.white,
  //           borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
  //           boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -5))],
  //         ),
  //         child: Column(
  //           mainAxisAlignment: MainAxisAlignment.center,
  //           children: [
  //             Lottie.asset(
  //               animationType == 'success'
  //                   ? 'assets/animation/correct.json'
  //                   : 'assets/animation/fail.json',
  //               height: 120,
  //             ),
  //             const SizedBox(height: 20),
  //             SizedBox(
  //               width: double.infinity,
  //               child: ElevatedButton(
  //                 onPressed: () {
  //                   Navigator.pop(context);
  //                   if (isCorrect) {
  //                     widget.onTaskComplete?.call(true);
  //                   } else {
  //                     _resetWordsForRetry();
  //                   }
  //                 },
  //                 style: ElevatedButton.styleFrom(
  //                   backgroundColor: isCorrect ? greenPrimary : Colors.orange,
  //                   padding: const EdgeInsets.symmetric(vertical: 16),
  //                   shape: RoundedRectangleBorder(
  //                       borderRadius: BorderRadius.circular(12)),
  //                   elevation: 5,
  //                 ),
  //                 child: Text(
  //                   isCorrect ? 'Continue' : 'Try Again',
  //                   style: const TextStyle(
  //                     color: Colors.white,
  //                     fontSize: 18,
  //                     fontWeight: FontWeight.bold,
  //                     letterSpacing: 1.2,
  //                   ),
  //                 ),
  //               ),
  //             ),
  //           ],
  //         ),
  //       ),
  //     ),
  //   );
  // }

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

          // ── Word chips ──────────────────────────────────────────────
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

    return Scaffold(
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
                
                      // ── Subtitle / instruction ──────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                
                      // ── Question with TTS button ────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                questionEn,
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.black54,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.volume_up, color: greenPrimary, size: 28),
                              onPressed: () => _speak(questionEn),
                            ),
                          ],
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
    );
  }
}