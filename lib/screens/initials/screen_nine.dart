import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lottie/lottie.dart';
import 'package:loringo_app/screens/initials/widget/highlight_text.dart';
import 'package:loringo_app/services/speech_to_text/speech_permissions.dart';
import 'package:loringo_app/services/speech_to_text/speech_to_text_service.dart';
import 'package:loringo_app/services/speech_to_text/speech_recognition_result.dart';

class ScreenNine extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final String taskId;
  final Function(bool isCorrect) onTaskComplete;
  final int currentTaskNumber;
  final int totalTasks;
  final String collectionName;

  const ScreenNine({
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
  State<ScreenNine> createState() => _ScreenNineState();
}

class _ScreenNineState extends State<ScreenNine>
    with SingleTickerProviderStateMixin {
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();
  final SpeechToTextService _speechService = SpeechToTextService();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const Color _green = Color(0xFF4CAF50);
  static const Color _greenLight = Color(0xFFE8F5E9);
  static const Color _orange = Color(0xFFFF9800);
  static const Color _highlightColor = Color(0xFFFFD54F);

  // Task data
  String _phrase = '';
  String _hint = '';
  bool _isLoading = true;

  // UI states
  bool _isSpeaking = false;
  bool _isListening = false;
  bool _isResultSheetOpen = false;

  // Speech recognition results
  String _recognizedText = '';
  List<String> _highlightWordsList = [];
  List<String> _phraseWords = [];

  @override
  void initState() {
    super.initState();
    _initTts();
    _fetchTask();
    _setupSpeechService();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.14).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  // ── Speech service ────────────────────────────────────────────────────────

  void _setupSpeechService() {
    _speechService.onListeningStart = () => setState(() => _isListening = true);
    _speechService.onListeningStop = () => setState(() => _isListening = false);

    _speechService.onPartialResult = (text) {
      setState(() {
        _recognizedText = text;
        _updateHighlightWords(text);
      });
    };

    _speechService.onFinalResult = (SpeechRecognitionResult result) {
      setState(() {
        _recognizedText = result.recognizedText;
        _isListening = false;
        _updateHighlightWords(result.recognizedText);
      });
      // Play sound immediately (no await — instant feedback, no delay)
      _playFeedbackSound(result.isCorrect);
      // Show the bottom sheet right away
      _showResultSheet(
        isCorrect: result.isCorrect,
        captureError: false,
      );
    };

    _speechService.onError = (error) {
      setState(() => _isListening = false);
      // Treat any speech error as a capture failure and show the sheet
      final isNoSpeech = error.toLowerCase().contains('no speech') ||
          error.toLowerCase().contains('no match') ||
          error.toLowerCase().contains('timeout');
      _playFeedbackSound(false);
      _showResultSheet(
        isCorrect: false,
        captureError: isNoSpeech,
        errorMessage: isNoSpeech
            ? "Couldn't capture your voice.\nPlease try again."
            : "Microphone error.\nPlease try again.",
      );
    };
  }

  // ── Word highlighting ─────────────────────────────────────────────────────

  void _updateHighlightWords(String spokenText) {
    if (_phraseWords.isEmpty) return;
    final spokenWords = _normalizeText(spokenText).split(' ');
    final List<String> matched = [];
    int si = 0;
    for (int i = 0; i < _phraseWords.length && si < spokenWords.length; i++) {
      if (_normalizeWord(_phraseWords[i]) == _normalizeWord(spokenWords[si])) {
        matched.add(_phraseWords[i]);
        si++;
      }
    }
    setState(() => _highlightWordsList = matched);
  }

  String _normalizeText(String text) => text
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^\w\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');

  String _normalizeWord(String word) =>
      word.toLowerCase().trim().replaceAll(RegExp(r'[^\w]'), '');

  void _initializeHighlightWords() {
    _phraseWords = _phrase.split(' ');
    setState(() => _highlightWordsList = []);
  }

  // ── TTS & audio ───────────────────────────────────────────────────────────

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
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
        final data = (doc.data() as Map<String, dynamic>)['data']
                as Map<String, dynamic>? ??
            {};
        setState(() {
          _phrase = data['phrase'] ?? '';
          _hint = data['hint'] ?? '';
          _isLoading = false;
        });
        _initializeHighlightWords();
        // Auto-speak on load — student hears the phrase immediately.
        Future.delayed(const Duration(milliseconds: 350), _speakPhrase);
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching repeat task: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _speakPhrase() async {
    if (_isSpeaking) return;
    setState(() => _isSpeaking = true);
    await _tts.speak(_phrase);
    setState(() => _isSpeaking = false);
  }

  /// Plays success or failure sound without blocking the caller.
  void _playFeedbackSound(bool isCorrect) async {
    try {
      await _player.setAsset(
        isCorrect ? 'assets/sound/success-2.mp3' : 'assets/sound/fail-2.mp3',
      );
      await _player.play();
    } catch (e) {
      debugPrint('Audio error: $e');
    }
  }

  // ── Mic ───────────────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (_isResultSheetOpen) return;
    setState(() {
      _recognizedText = '';
      _highlightWordsList = [];
    });
    final hasPermission =
        await SpeechPermissions.isMicrophonePermissionGranted();
    if (!hasPermission) {
      final granted = await SpeechPermissions.showPermissionDialog(context);
      if (!granted) return;
    }
    await _speechService.startListening(targetPhrase: _phrase);
  }

  void _stopRecording() => _speechService.stopListening();

  // ── Result bottom sheet ───────────────────────────────────────────────────

  void _showResultSheet({
    required bool isCorrect,
    required bool captureError,
    String? errorMessage,
  }) {
    if (_isResultSheetOpen) return;
    _isResultSheetOpen = true;

    if (isCorrect) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: false,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.42,
        maxChildSize: 0.58,
        builder: (_, __) => Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 20,
                offset: Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Lottie animation
              Lottie.asset(
                isCorrect
                    ? 'assets/animation/correct.json'
                    : 'assets/animation/fail.json',
                height: 120,
                repeat: true,
              ),

              const SizedBox(height: 12),

              // Message
              Text(
                captureError
                    ? (errorMessage ?? "Couldn't capture your voice.\nPlease try again.")
                    : isCorrect
                        ? '¡Excellent! Perfect pronunciation!'
                        : 'Almost there! Give it another try.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isCorrect
                      ? const Color(0xFF2E7D32)
                      : captureError
                          ? Colors.grey.shade700
                          : const Color(0xFFE65100),
                  height: 1.4,
                ),
              ),

              // Show what the student said if it was a wrong attempt (not a capture error)
              if (!isCorrect && !captureError && _recognizedText.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '"$_recognizedText"',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Single action button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _isResultSheetOpen = false;
                    if (isCorrect) {
                      widget.onTaskComplete(true);
                    } else {
                      // Reset so the student can try again
                      setState(() {
                        _recognizedText = '';
                        _highlightWordsList = [];
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isCorrect ? _green : _orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    isCorrect ? 'Continue' : 'Try Again',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() => _isResultSheetOpen = false);
  }

  @override
  void dispose() {
    _tts.stop();
    _player.dispose();
    _speechService.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final progressValue = (widget.currentTaskNumber + 1) / widget.totalTasks;

    return Scaffold(
      backgroundColor: _greenLight,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _green))
            : Column(
                children: [
                  // ── Progress bar ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 20, 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.black54, size: 26),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(30),
                            child: LinearProgressIndicator(
                              value: progressValue,
                              backgroundColor: Colors.black12,
                              valueColor:
                                  const AlwaysStoppedAnimation<Color>(_green),
                              minHeight: 8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Hint ──────────────────────────────────────────────────
                  if (_hint.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                      child: Text(
                        _hint,
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  const SizedBox(height: 12),

                  // ── Loringo character ──────────────────────────────────────
                  Image.asset(
                    'assets/images/loringo-listening.png',
                    width: 110,
                    height: 110,
                    fit: BoxFit.contain,
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Repeat after me',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black45,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Phrase card with embedded Listen button ───────────────
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: _green.withOpacity(0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Phrase text with yellow highlight as words are spoken
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                          child: HighlightTextWidget(
                            text: _phrase,
                            wordsToHighlight: _highlightWordsList,
                            normalStyle: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              height: 1.45,
                            ),
                            highlightStyle: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF5D4037),
                              backgroundColor: _highlightColor,
                              height: 1.45,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),

                        Divider(
                          height: 1,
                          color: Colors.grey.shade100,
                          indent: 16,
                          endIndent: 16,
                        ),

                        // Replay button embedded inside the card
                        InkWell(
                          onTap: _isSpeaking ? null : _speakPhrase,
                          borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(28)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 24),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 250),
                                  child: _isSpeaking
                                      ? SizedBox(
                                          key: const ValueKey('loading'),
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: _orange,
                                          ),
                                        )
                                      : Icon(
                                          Icons.volume_up_rounded,
                                          key: const ValueKey('icon'),
                                          color: _orange,
                                          size: 20,
                                        ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _isSpeaking
                                      ? 'Playing…'
                                      : 'Listen to pronunciation',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        _isSpeaking ? Colors.grey : _orange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Word progress pill (while speaking) ────────────────────
                  if (_highlightWordsList.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: _green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle,
                              size: 13, color: _green),
                          const SizedBox(width: 5),
                          Text(
                            '${_highlightWordsList.length} / ${_phraseWords.length} words',
                            style: const TextStyle(
                              fontSize: 12,
                              color: _green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── Partial "you said" text while listening ────────────────
                  if (_recognizedText.isNotEmpty && _isListening) ...[
                    const SizedBox(height: 10),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.record_voice_over_rounded,
                              size: 16, color: Colors.grey.shade500),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _recognizedText,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Spacer(),

                  // ── Mic button ─────────────────────────────────────────────
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) => Transform.scale(
                      scale: _isListening ? _pulseAnimation.value : 1.0,
                      child: child,
                    ),
                    child: GestureDetector(
                      onTap: _isListening ? _stopRecording : _startRecording,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isListening ? Colors.red : _green,
                          boxShadow: [
                            BoxShadow(
                              color: (_isListening ? Colors.red : _green)
                                  .withOpacity(0.4),
                              blurRadius: _isListening ? 28 : 16,
                              spreadRadius: _isListening ? 8 : 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                          size: 38,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    _isListening ? 'Listening… speak now' : 'Tap to speak',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
      ),
    );
  }
}