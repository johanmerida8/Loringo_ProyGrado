// screen_ten.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_tts/flutter_tts.dart';
// import 'package:just_audio/just_audio.dart';
import 'package:loringo_app/screens/initials/widget/responsive_activity_shell.dart';
import 'package:loringo_app/screens/initials/widget/retryable_task.dart';
import 'package:loringo_app/screens/initials/widget/task_exit_guard.dart';
import 'package:loringo_app/screens/initials/widget/task_result_sheet.dart';
// import 'package:loringo_app/services/audio/feedback_sound_service.dart';
import 'package:loringo_app/services/audio/task_feedback.dart';
// import 'package:lottie/lottie.dart';
import 'package:loringo_app/screens/initials/widget/exit_task_dialog.dart';
import 'package:loringo_app/screens/initials/widget/task_callbacks.dart';
import 'package:loringo_app/services/speech_to_text/speech_permissions.dart';
import 'package:loringo_app/services/speech_to_text/speech_to_text_service.dart';
import 'package:loringo_app/services/speech_to_text/speech_recognition_result.dart';
import 'package:loringo_app/services/tts/task_tts_service.dart';
import 'package:loringo_app/services/tts/tts_voices.dart';

class ScreenTen extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final String taskId;
  // ── TEACHER REVIEW FEATURE ──────────────────────────────────────────
  // See widget/task_callbacks.dart for why this uses a shared typedef.
  // answerDetail shape: {'type': 'listen_and_speak', 'targetPhrase':
  // <phrase the student heard and had to repeat>, 'recognizedText':
  // <what speech-to-text captured on the FINAL (scored) attempt>}. Same
  // rationale as ScreenNine's repeat_after_me: no per-word "correct
  // option" here, the teacher judges pronunciation by comparing the two
  // strings directly.
  final TaskCompleteCallback onTaskComplete;
  final int currentTaskNumber;
  final int totalTasks;
  final String collectionName;
  final bool isPracticeRound;

  const ScreenTen({
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
  State<ScreenTen> createState() => _ScreenTenState();
}

// RetryableTask added: a wrong PRONUNCIATION (mic captured something,
// it just didn't match) now gets one local retry before counting
// against the student — same mechanic and same exclusion of
// mic-capture failures as ScreenNine. See screen_nine.dart's class doc
// comment and retryable_task.dart's file header for the full
// rationale.
class _ScreenTenState extends State<ScreenTen>
    with SingleTickerProviderStateMixin, RetryableTask<ScreenTen> {
  // final FlutterTts _tts = FlutterTts();
  // final AudioPlayer _player = AudioPlayer();

  // BUGFIX CONTEXT: same fix as ScreenNine and ScreenThirteen.
  // SpeechToTextService used to be a singleton, so this line looked
  // like it created a private instance for this screen but was actually
  // grabbing one shared object across every screen using speech
  // recognition in the app — this one, ScreenNine (repeat_after_me), and
  // ScreenThirteen (slow_reveal) were all silently overwriting each
  // other's callbacks. SpeechToTextService's constructor is no longer a
  // factory/singleton, so this line now genuinely creates an isolated
  // instance scoped to this screen. No other change was needed here —
  // this screen's usage pattern (create in the field initializer,
  // configure callbacks in _setupSpeechService(), tear down in
  // dispose()) was already correct for a non-shared instance.
  final SpeechToTextService _speechService = SpeechToTextService();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const Color _green = Color(0xFF4CAF50);
  static const Color _greenLight = Color(0xFFE8F5E9);
  static const Color _orange = Color(0xFFFF9800);

  // Task data
  String _phrase = '';
  String _hint = '';
  bool _isLoading = true;

  // UI states
  bool _isSpeaking = false;
  bool _isListening = false;
  bool _isResultSheetOpen = false;

  // FEATURE: true while the mic is open AND the last sound-level
  // sample came back below threshold with nothing recognized yet.
  // Driven by SpeechToTextService.onLowVolumeWarning /
  // onListeningStop — see _setupSpeechService(). Purely advisory UI;
  // it never blocks or delays recording.
  bool _isVolumeLow = false;

  // Speech recognition
  String _recognizedText = '';

  @override
  void initState() {
    super.initState();
    // _initTts();
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

  void _setupSpeechService() {
    _speechService.onListeningStart = () => setState(() {
          _isListening = true;
          _isVolumeLow = false;
        });
    _speechService.onListeningStop = () => setState(() {
          _isListening = false;
          _isVolumeLow = false;
        });

    // FEATURE: surfaces the low-volume state as a visible hint instead
    // of the previous debugPrint-only behavior. See
    // SpeechToTextService.onLowVolumeWarning doc comment for when this
    // fires and how it self-clears.
    _speechService.onLowVolumeWarning = () {
      if (mounted) setState(() => _isVolumeLow = true);
    };

    _speechService.onPartialResult = (text) {
      setState(() {
        _recognizedText = text;
        _isVolumeLow = false;
      });
    };

    _speechService.onFinalResult = (SpeechRecognitionResult result) {
      setState(() {
        _recognizedText = result.recognizedText;
        _isListening = false;
        _isVolumeLow = false;
      });

      // Haptic + sound now happen inside _showResultSheet via
      // TaskFeedback.fire — calling them here too would double-fire both.
      _showResultSheet(
        isCorrect: result.isCorrect,
        captureError: false,
        spokenText: result.recognizedText,
      );
    };

    _speechService.onError = (error) {
      setState(() {
        _isListening = false;
        _isVolumeLow = false;
      });
      final isNoSpeech = error.toLowerCase().contains('no speech') ||
          error.toLowerCase().contains('no match') ||
          error.toLowerCase().contains('timeout');

      _showResultSheet(
        isCorrect: false,
        captureError: isNoSpeech,
        errorMessage: isNoSpeech
            ? 'initials.screen_nine.couldntCaptureVoice'.tr()
            : 'initials.screen_nine.microphoneError'.tr(),
        spokenText: '',
      );
    };
  }

  // Future<void> _initTts() async {
  //   await _tts.setLanguage('en-GB');
  //   await _tts.setSpeechRate(0.45);
  //   await _tts.setPitch(1.0);
  // }

  Future<void> _handleClose() async {
    final shouldExit = await confirmExitTask(context);
    if (shouldExit && context.mounted) Navigator.pop(context);
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
        // Fresh attempt budget for this task instance — see
        // ScreenNine's _fetchTask for why this matters at the review
        // round specifically.
        resetAttempts();
        // Auto-speak on load
        Future.delayed(const Duration(milliseconds: 500), _speakPhrase);
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching listen & speak task: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _speakPhrase() async {
    if (_isSpeaking) return;
    setState(() => _isSpeaking = true);
    await TaskTtsService.speak(_phrase, voice: TtsVoiceDefaults.defaultEnglish);
    setState(() => _isSpeaking = false);
  }

  Future<void> _startRecording() async {
    if (_isResultSheetOpen) return;
    setState(() {
      _recognizedText = '';
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

  void _showResultSheet({
    required bool isCorrect,
    required bool captureError,
    String? errorMessage,
    String spokenText = '',
  }) {
    if (_isResultSheetOpen) return;

    // RetryableTask hook — same placement and same exclusion of
    // captureError as ScreenNine. Only a genuinely wrong pronunciation
    // consumes an attempt; a mic-capture failure never evaluated the
    // student's speech at all, so it stays on the existing indefinite
    // retry path below unchanged.
    if (!isCorrect && !captureError) {
      final retried = offerRetry(
        context: context,
        onRetry: () {
          setState(() => _recognizedText = '');
          Future.delayed(const Duration(milliseconds: 300), _speakPhrase);
        },
      );
      if (retried) return;
    }

    _isResultSheetOpen = true;

    TaskFeedback.fire(isCorrect);

    final message = captureError
        ? (errorMessage ?? 'initials.screen_nine.couldntCaptureVoice'.tr())
        : isCorrect
            ? 'initials.screen_ten.perfectRepeated'.tr()
            : 'initials.screen_ten.almostThereListenAgain'.tr();

    final messageColor = isCorrect
        ? const Color(0xFF2E7D32)
        : captureError
            ? Colors.grey.shade700
            : const Color(0xFFE65100);

    TaskResultSheet.show(
      context,
      isCorrect: isCorrect,
      isPracticeRound: widget.isPracticeRound,
      message: message,
      messageColor: messageColor,
      extraContent: spokenText.isNotEmpty
          ? TaskResultSpokenTextBox(spokenText: spokenText, showLabel: true)
          : null,
      onContinue: () {
        _isResultSheetOpen = false;
        // A microphone-capture error (no speech detected, timeout) isn't a
        // wrong *answer* — nothing was actually evaluated — so it still
        // retries locally here rather than being scored. A genuine wrong
        // pronunciation now only reaches this point once RetryableTask's
        // attempts are exhausted (see above), and advances via
        // onTaskComplete(false) like every other screen; ActivityPlayScreen
        // queues it for the review round.
        if (captureError) {
          setState(() => _recognizedText = '');
          Future.delayed(const Duration(milliseconds: 300), _speakPhrase);
        } else {
          // Teacher review detail: what speech-to-text captured on THIS
          // final scored attempt, alongside the target phrase.
          widget.onTaskComplete(isCorrect, {
            'type': 'listen_and_speak',
            'targetPhrase': _phrase,
            'recognizedText': spokenText,
          });
        }
      },
    ).then((_) => _isResultSheetOpen = false);
  }

  @override
  void dispose() {
    // _tts.stop();
    TaskTtsService.stop();
    // _player.dispose();
    // Now safe by construction: this instance is private to this
    // screen (SpeechToTextService is no longer a singleton), so
    // disposing it only tears down THIS screen's mic session.
    _speechService.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final progressValue = (widget.currentTaskNumber + 1) / widget.totalTasks;

    return TaskExitGuard(
      onRequestExit: _handleClose,
      child: Scaffold(
        backgroundColor: _greenLight,
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: _green))
              : ResponsiveActivityShell(
                child: Column(
                    children: [
                      // ── Progress bar ──────────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 20, 8),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close,
                                  color: Colors.black54, size: 26),
                              onPressed: _handleClose,
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
                              fontStyle: FontStyle.italic,
                            ),
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
                
                      Text(
                        'initials.screen_ten.listenAndSpeak'.tr(),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black45,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3,
                        ),
                      ),
                
                      const SizedBox(height: 16),
                
                      // ── Audio card — the listen control lives right under the
                      // parrot, same pattern as the phrase card in screen_nine,
                      // just with a headphone glyph instead of revealed text. ──
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
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                              child: Icon(
                                Icons.headphones_rounded,
                                size: 56,
                                color: _green.withOpacity(0.35),
                              ),
                            ),
                
                            Divider(
                              height: 1,
                              color: Colors.grey.shade100,
                              indent: 16,
                              endIndent: 16,
                            ),
                
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
                                                color: _green,
                                              ),
                                            )
                                          : Icon(
                                              Icons.play_circle_fill_rounded,
                                              key: const ValueKey('icon'),
                                              color: _green,
                                              size: 22,
                                            ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _isSpeaking
                                          ? 'initials.screen_nine.playing'.tr()
                                          : 'initials.screen_ten.tapToListen'.tr(),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _isSpeaking ? Colors.grey : _green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                
                      // ── Low volume warning (while listening) ───────────────────
                      // Purely advisory — never blocks recording, never
                      // counts as an error on its own. Only visible while
                      // the mic is open and the last sound-level sample was
                      // below threshold with nothing recognized yet.
                      if (_isListening && _isVolumeLow) ...[
                        const SizedBox(height: 10),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 24),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.volume_off_rounded,
                                  size: 16, color: Colors.orange.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'initials.screen_nine.speakLouder'.tr(),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                
                      // ── "You said" text while listening ───────────────────────
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
                        _isListening
                            ? 'initials.screen_nine.listeningSpeakNow'.tr()
                            : 'initials.screen_nine.tapToSpeak'.tr(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                
                      const SizedBox(height: 32),
                    ],
                  ),
              ),
        ),
      ),
    );
  }
}