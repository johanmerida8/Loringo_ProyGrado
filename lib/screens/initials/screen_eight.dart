// screen_eight.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
// import 'package:just_audio/just_audio.dart';
import 'package:loringo_app/screens/initials/widget/responsive_activity_shell.dart';
import 'package:loringo_app/screens/initials/widget/task_result_sheet.dart';
import 'package:loringo_app/services/audio/feedback_sound_service.dart';
import 'package:loringo_app/services/audio/task_feedback.dart';
import 'package:lottie/lottie.dart';
import 'package:loringo_app/screens/initials/widget/exit_task_dialog.dart';

class ScreenEight extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final String taskId;
  final Function(bool isCorrect) onTaskComplete;
  final int currentTaskNumber;
  final int totalTasks;
  final String collectionName;

  const ScreenEight({
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
  State<ScreenEight> createState() => _ScreenEightState();
}

class _ScreenEightState extends State<ScreenEight> {
  // final AudioPlayer _player = AudioPlayer();
  final FlutterTts _tts = FlutterTts();

  static const Color _green = Color(0xFF4CAF50);
  static const Color _greyBg = Color(0xFFF5F5F5);

  // Task data
  String _promptSentence = '';
  String _direction = 'es_to_en';
  List<String> _correctAnswer = [];
  List<String> _wordBank = [];

  // Student answer
  List<String> _selectedWords = [];

  // UI state
  bool _isLoading = true;

  // FIX 3: Track whether bottom sheet is already open to prevent re-entry
  bool _isResultSheetOpen = false;

  // Feedback messages shown when the answer is incorrect — no answer exposed
  // (FIX 2)
  static const List<String> _incorrectHints = [
    '¡Casi! Revisa el orden de las palabras.',
    '¡Buen intento! Sigue intentándolo.',
    '¡Tú puedes! Piensa en la oración completa.',
    '¡Inténtalo de nuevo! Estás muy cerca.',
    '¡No te rindas! Vuelve a intentarlo.',
  ];
  int _attemptCount = 0;

  // convenience getters - everything UI-facing derives from these
  bool get _isEsToEn => _direction == 'es_to_en';
  String get _promptLangCode => _isEsToEn ? 'es-ES' : 'en-GB';
  String get _headerLabel => _isEsToEn ? 'Translate to English' : 'Translate to Spanish';
  String get _listenTooltip => _isEsToEn ? 'Listen to Spanish' : 'Listen to English';

  @override
  void initState() {
    super.initState();
    _initTts();
    _fetchTask();
  }

  Future<void> _initTts() async {
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
  }

  Future<void> _handleClose() async {
    final shouldExit = await confirmExitTask(context);
    if (shouldExit && context.mounted) Navigator.pop(context);
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
        final taskData = doc.data() as Map<String, dynamic>;
        final data = taskData['data'] as Map<String, dynamic>? ?? {};

        setState(() {
          _direction = data['direction'] ?? 'es_to_en';
          // sentence is the current key: spanishSentence kept as fallback
          // for tasks created before the direction toggle was added
          _promptSentence = data['sentence'] ?? data['spanishSentence'] ?? '';
          _correctAnswer = List<String>.from(data['correctAnswer'] ?? []);
          _wordBank = List<String>.from(data['wordBank'] ?? []);
          _wordBank.shuffle(); // Shuffle for variety each time
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching sentence builder task: $e');
      setState(() => _isLoading = false);
    }
  }

  void _speakPrompt() async {
    await _tts.setLanguage(_promptLangCode);
    await _tts.speak(_promptSentence);
  }

  void _addWord(String word) {
    setState(() {
      _selectedWords.add(word);
      _wordBank.remove(word);
    });
  }

  void _removeWord(int index) {
    setState(() {
      final word = _selectedWords[index];
      _selectedWords.removeAt(index);
      _wordBank.add(word);
    });
  }

  void _clearAll() {
    setState(() {
      _wordBank.addAll(_selectedWords);
      _selectedWords.clear();
      _wordBank.shuffle();
    });
  }

  // FIX 3: _checkAnswer now shows the sheet synchronously; audio plays in the
  // background without blocking the UI.  No await before showModalBottomSheet.
  void _checkAnswer() {
    if (_isResultSheetOpen) return;

    final isCorrect = _selectedWords.join(' ') == _correctAnswer.join(' ');
    if (!isCorrect) _attemptCount++;

    TaskFeedback.fire(isCorrect);

    _isResultSheetOpen = true;
    TaskResultSheet.show(
      context,
      isCorrect: isCorrect,
      // initialChildSize: 0.38,
      // maxChildSize: 0.55,
      extraContent: isCorrect ? null : TaskResultHintBox(hint: _currentHint),
      onContinue: () {
        _isResultSheetOpen = false;
        if (isCorrect) {
          widget.onTaskComplete(true);
        } else {
          _clearAll();
        }
      },
    ).then((_) => _isResultSheetOpen = false);
  }

  /// Plays the success / failure sound without blocking the caller.
  // void _playFeedbackSound(bool isCorrect) {
  //   FeedbackSoundService.instance.playResult(isCorrect);
  // }

  // FIX 2: Incorrect feedback never exposes the correct answer.
  // Instead, it cycles through encouraging hint messages.
  String get _currentHint {
    return _incorrectHints[(_attemptCount - 1) % _incorrectHints.length];
  }

  // void _showResultBottomSheet(bool isCorrect) {
  //   _isResultSheetOpen = true;

  //   showModalBottomSheet(
  //     context: context,
  //     backgroundColor: Colors.transparent,
  //     isScrollControlled: true,
  //     isDismissible: false,
  //     enableDrag: false,
  //     builder: (_) => DraggableScrollableSheet(
  //       initialChildSize: 0.38,
  //       maxChildSize: 0.55,
  //       builder: (_, __) => Container(
  //         padding: const EdgeInsets.all(24),
  //         decoration: const BoxDecoration(
  //           color: Colors.white,
  //           borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
  //           boxShadow: [
  //             BoxShadow(
  //               color: Colors.black26,
  //               blurRadius: 20,
  //               offset: Offset(0, -5),
  //             ),
  //           ],
  //         ),
  //         child: Column(
  //           mainAxisAlignment: MainAxisAlignment.center,
  //           children: [
  //             Lottie.asset(
  //               isCorrect
  //                   ? 'assets/animation/correct.json'
  //                   : 'assets/animation/fail.json',
  //               height: 120,
  //             ),
  //             const SizedBox(height: 12),

  //             if (!isCorrect) ...[
  //               // FIX 2: Show encouragement hint — no correct answer revealed
  //               Container(
  //                 padding: const EdgeInsets.symmetric(
  //                   horizontal: 16,
  //                   vertical: 12,
  //                 ),
  //                 decoration: BoxDecoration(
  //                   color: Colors.orange.shade50,
  //                   borderRadius: BorderRadius.circular(12),
  //                   border: Border.all(color: Colors.orange.shade200),
  //                 ),
  //                 child: Row(
  //                   children: [
  //                     Icon(
  //                       Icons.lightbulb_outline,
  //                       color: Colors.orange.shade600,
  //                       size: 20,
  //                     ),
  //                     const SizedBox(width: 10),
  //                     Expanded(
  //                       child: Text(
  //                         _currentHint,
  //                         style: TextStyle(
  //                           fontSize: 14,
  //                           color: Colors.orange.shade800,
  //                           fontWeight: FontWeight.w500,
  //                         ),
  //                       ),
  //                     ),
  //                   ],
  //                 ),
  //               ),
  //               const SizedBox(height: 16),
  //             ],

  //             SizedBox(
  //               width: double.infinity,
  //               child: ElevatedButton(
  //                 onPressed: () {
  //                   Navigator.pop(context);
  //                   _isResultSheetOpen = false;
  //                   if (isCorrect) {
  //                     widget.onTaskComplete(true);
  //                   } else {
  //                     // Reset so student can try again
  //                     _clearAll();
  //                   }
  //                 },
  //                 style: ElevatedButton.styleFrom(
  //                   backgroundColor: isCorrect ? _green : Colors.orange,
  //                   padding: const EdgeInsets.symmetric(vertical: 16),
  //                   shape: RoundedRectangleBorder(
  //                     borderRadius: BorderRadius.circular(12),
  //                   ),
  //                 ),
  //                 child: Text(
  //                   isCorrect ? 'Continue' : 'Try Again',
  //                   style: const TextStyle(
  //                     color: Colors.white,
  //                     fontSize: 18,
  //                     fontWeight: FontWeight.bold,
  //                   ),
  //                 ),
  //               ),
  //             ),
  //           ],
  //         ),
  //       ),
  //     ),
  //   ).whenComplete(() {
  //     // Safety net: ensure the flag is reset even if the sheet is dismissed
  //     // by some other means.
  //     _isResultSheetOpen = false;
  //   });
  // }

  @override
  void dispose() {
    // _player.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final progressValue = (widget.currentTaskNumber + 1) / widget.totalTasks;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE8F5E9), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: ResponsiveActivityShell(
            child: Column(
              children: [
                // ── Progress Bar ──────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.black87,
                          size: 28,
                        ),
                        onPressed: _handleClose,
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(30),
                          ),
                          child: LinearProgressIndicator(
                            value: progressValue,
                            backgroundColor: Colors.blueGrey,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              _green,
                            ),
                            minHeight: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            
                // ── Spanish Sentence Card ─────────────────────────────────────
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.translate, color: _green, size: 24),
                          const SizedBox(width: 12),
                          const Text(
                            'Translate to English',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54,
                            ),
                          ),
                          const Spacer(),
                          // FIX 1: Only the sentence card has audio
                          IconButton(
                            icon: Icon(
                              Icons.volume_up,
                              color: _green,
                              size: 24,
                            ),
                            onPressed: _speakPrompt,
                            tooltip: _listenTooltip,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _promptSentence,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
            
                const SizedBox(height: 16),
            
                // ── Your Answer header ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Text(
                        'Your Answer',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      if (_selectedWords.isNotEmpty)
                        TextButton.icon(
                          onPressed: _clearAll,
                          icon: const Icon(Icons.clear_all, size: 18),
                          label: const Text('Clear All'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                        ),
                    ],
                  ),
                ),
            
                const SizedBox(height: 8),
            
                // ── Selected Words Area ───────────────────────────────────────
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _greyBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: _selectedWords.isEmpty
                      ? Center(
                          child: Text(
                            'Tap words below to build your sentence',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 14,
                            ),
                          ),
                        )
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: _selectedWords.asMap().entries.map((entry) {
                            final index = entry.key;
                            final word = entry.value;
                            return GestureDetector(
                              onTap: () => _removeWord(index),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: _green,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _green.withOpacity(0.3),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      word,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.white70,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                ),
            
                const SizedBox(height: 20),
            
                // ── Word Bank header ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Text(
                        'Word Bank',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Tap to add',
                          style: TextStyle(
                            fontSize: 11,
                            color: _green,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            
                const SizedBox(height: 8),
            
                // ── Word Bank Grid ────────────────────────────────────────────
                // FIX 1: Tiles no longer have individual audio buttons.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _wordBank.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 60,
                                  color: _green.withOpacity(0.5),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'All words used!',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap CHECK when ready',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 1.8,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: _wordBank.length,
                            itemBuilder: (context, index) {
                              final word = _wordBank[index];
                              return GestureDetector(
                                onTap: () => _addWord(word),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: _green.withOpacity(0.3),
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  // FIX 1: Simple centered text, no audio icon
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: Text(
                                        word,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
            
                // ── CHECK Button ──────────────────────────────────────────────
                // FIX 3: No longer uses _isSubmitting as a gating bool.
                // The _isResultSheetOpen flag prevents double-tap; the button
                // itself is disabled only when no words are selected.
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          _selectedWords.isEmpty ? null : _checkAnswer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 3,
                      ),
                      child: const Text(
                        'CHECK',
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
    );
  }
}