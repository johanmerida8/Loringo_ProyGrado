// screen_nine.dart
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
import 'package:loringo_app/screens/initials/widget/highlight_text.dart';
import 'package:loringo_app/screens/initials/widget/exit_task_dialog.dart';
import 'package:loringo_app/screens/initials/widget/task_callbacks.dart';
import 'package:loringo_app/services/speech_to_text/speech_permissions.dart';
import 'package:loringo_app/services/speech_to_text/speech_to_text_service.dart';
import 'package:loringo_app/services/speech_to_text/speech_recognition_result.dart';
import 'package:loringo_app/services/tts/task_tts_service.dart';
import 'package:loringo_app/services/tts/tts_voices.dart';

class ScreenNine extends StatefulWidget {
  final String contentId;
  final String unitId;
  final String lessonId;
  final String activityId;
  final String taskId;
  // ── TEACHER REVIEW FEATURE ──────────────────────────────────────────
  // See widget/task_callbacks.dart for why this uses a shared typedef.
  // answerDetail shape: {'type': 'repeat_after_me', 'targetPhrase': <the
  // phrase the student was asked to repeat>, 'recognizedText': <what
  // speech-to-text captured on the FINAL attempt that produced this
  // isCorrect result>}. Unlike the text/image task types, there's no
  // "correct option" to compare against — the review screen shows the
  // target phrase alongside what the system heard, letting the teacher
  // judge pronunciation quality themselves rather than a binary
  // right/wrong per word.
  final TaskCompleteCallback onTaskComplete;
  final int currentTaskNumber;
  final int totalTasks;
  final String collectionName;
  final bool isPracticeRound;

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
    this.isPracticeRound = false,
  });

  @override
  State<ScreenNine> createState() => _ScreenNineState();
}

// RetryableTask added: a wrong PRONUNCIATION (mic captured something,
// it just didn't match) now gets one local retry before counting
// against the student, same mechanic as the other task screens using
// this mixin. See retryable_task.dart's file header for the full
// rationale and the important distinction it draws between a soft
// (retryable) wrong answer and a hard (scored) one.
//
// Deliberately NOT used for mic-capture failures (no speech / timeout)
// — those stay on the existing indefinite-retry path via captureError
// in _showResultSheet, unchanged from before. Rationale: RetryableTask
// counts attempts at answering, and a capture failure means the
// student's pronunciation was never actually evaluated at all. Folding
// that into the 2-attempt budget would let a noisy room or a flaky mic
// burn through both attempts without the app ever having judged a
// single real pronunciation — punishing hardware conditions instead of
// language skill, which is exactly the kind of discouraging failure
// mode this app's design principles try to avoid for young learners.
class _ScreenNineState extends State<ScreenNine>
    with SingleTickerProviderStateMixin, RetryableTask<ScreenNine> {
  // final FlutterTts _tts = FlutterTts();
  // final AudioPlayer _player = AudioPlayer();

  // BUGFIX CONTEXT: SpeechToTextService used to be a singleton (a
  // `factory` constructor returning one shared `_instance` across the
  // whole app). This line looked like it was creating a private
  // instance for this screen, but it wasn't — every screen that wrote
  // `SpeechToTextService()`, including ScreenThirteen (slow_reveal), was
  // actually grabbing the same global object and overwriting its
  // callbacks (onFinalResult, onError, etc.) out from under each other.
  // SpeechToTextService's constructor is no longer a factory/singleton,
  // so this line now does exactly what it always looked like it did:
  // creates a private, isolated instance scoped to this screen's
  // lifecycle. No other change was needed here — this screen's usage
  // pattern (create in the field initializer, configure callbacks in
  // _setupSpeechService(), tear down in dispose()) was already correct
  // for a non-shared instance.
  final SpeechToTextService _speechService = SpeechToTextService();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const Color _green = Color(0xFF4CAF50);
  static const Color _greenLight = Color(0xFFE8F5E9);
  static const Color _orange = Color(0xFFFF9800);
  static const Color _highlightColor = Color(0xFFFFD54F);

  // Task data
  String _phrase = '';
  bool _isLoading = true;

  // CHANGE: this used to be local UI-only state the student toggled
  // themselves. It's now sourced from Firestore (data['showPhrase'],
  // set by the teacher in RepeatAfterMeTask's editor) and represents
  // the task's configured difficulty mode, not a runtime student
  // action. See _fetchTask() for where it's read and _revealPhrase()
  // for why the student can still override it upward (never downward)
  // during a single attempt.
  bool _showPhrase = false;

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

  // REVEAL MECHANIC: when the teacher configures this task with
  // showPhrase == false, the phrase starts masked (dash placeholders)
  // and the student must rely on the TTS audio + their own recall.
  // Tapping "Reveal" sets this true and shows the real text for the
  // rest of THIS attempt — no penalty, since a failed mic capture
  // (background noise, permission hiccup, etc.) is a technical
  // failure, not the student not knowing the answer, and shouldn't be
  // conflated with "gave up and peeked." Always available when the
  // task starts hidden, unlike Duolingo where reveal sometimes costs
  // hearts in other exercise types — CJ's app avoids anything that
  // could discourage young learners (5-9yo), so no punitive framing
  // here.
  //
  // Initialized from _showPhrase once the task loads (see _fetchTask):
  // if the teacher set showPhrase == true, the phrase is visible from
  // the start and there's nothing to "reveal." If false, this starts
  // false and the reveal button becomes the student's own escape
  // hatch.
  bool _isRevealed = false;

  // Speech recognition results
  String _recognizedText = '';
  List<String> _highlightWordsList = [];
  List<String> _phraseWords = [];

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

  // ── Speech service ────────────────────────────────────────────────────────

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
        _updateHighlightWords(text);
      });
    };

    _speechService.onFinalResult = (SpeechRecognitionResult result) {
      setState(() {
        _recognizedText = result.recognizedText;
        _isListening = false;
        _isVolumeLow = false;
        _updateHighlightWords(result.recognizedText);
      });
      _showResultSheet(isCorrect: result.isCorrect, captureError: false);
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

  // ── Reveal ────────────────────────────────────────────────────────────────

  // No penalty, no tracking side-effect — just flips the mask off. Kept
  // as its own method (rather than an inline setState in the button's
  // onTap) so the "no penalty here" decision is a single, obvious,
  // commentable point for jury Q&A rather than buried in a widget tree.
  void _revealPhrase() {
    if (_isRevealed) return;
    setState(() => _isRevealed = true);
  }

  // ── TTS & audio ───────────────────────────────────────────────────────────

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
          // Absent field (tasks created before this toggle existed)
          // defaults to false, matching RepeatAfterMeTask's editor
          // default — old tasks adopt the hidden-phrase UX
          // automatically rather than needing a data migration.
          _showPhrase = data['showPhrase'] as bool? ?? false;
          // _isRevealed starts in sync with the teacher's configured
          // mode: if the task is set to always show the phrase, there's
          // no masked state to reveal from. If hidden, the student
          // starts masked and can reveal manually via _revealPhrase().
          _isRevealed = _showPhrase;
          _isLoading = false;
        });
        _initializeHighlightWords();
        // Fresh attempt budget for this task instance — mirrors what
        // every other RetryableTask screen does on load, and matters
        // in particular for the review round, where ActivityPlayScreen
        // rebuilds this screen: without this reset, a task that used
        // its retry on the first pass would arrive at the review round
        // with zero attempts left and skip straight to hard-wrong on
        // any mistake.
        resetAttempts();
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
    await TaskTtsService.speak(_phrase, voice: TtsVoiceDefaults.defaultEnglish);
    setState(() => _isSpeaking = false);
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

    // RetryableTask hook: only for a genuine wrong PRONUNCIATION, never
    // for a capture failure (see the class-level doc comment for why
    // captureError is excluded). offerRetry() increments the attempt
    // counter and, if a retry remains, shows its own sheet and clears
    // this screen's local recognition state via onRetry — returning
    // true tells us to stop here instead of opening TaskResultSheet at
    // all for this pass.
    if (!isCorrect && !captureError) {
      final retried = offerRetry(
        context: context,
        onRetry: () {
          setState(() {
            _recognizedText = '';
            _highlightWordsList = [];
          });
        },
      );
      if (retried) return;
    }

    _isResultSheetOpen = true;

    TaskFeedback.fire(isCorrect);

    final message = captureError
        ? (errorMessage ?? 'initials.screen_nine.couldntCaptureVoice'.tr())
        : isCorrect
            ? 'initials.screen_nine.excellentPronunciation'.tr()
            : 'initials.screen_nine.almostThereTryAgain'.tr();

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
      extraContent: (!isCorrect && !captureError && _recognizedText.isNotEmpty)
          ? TaskResultSpokenTextBox(spokenText: _recognizedText)
          : null,
      onContinue: () {
        _isResultSheetOpen = false;
        // A microphone-capture error (no speech detected, timeout, etc.)
        // isn't a wrong *answer* — it's the mic not hearing anything, so
        // that case still lets the student retry right here rather than
        // burning an attempt that was never actually evaluated. A genuine
        // wrong pronunciation now only reaches this point once
        // RetryableTask's attempts are exhausted (see above), and
        // advances via onTaskComplete(false) exactly as before —
        // ActivityPlayScreen queues it for the review round.
        if (captureError) {
          setState(() {
            _recognizedText = '';
            _highlightWordsList = [];
          });
        } else {
          // Teacher review detail: whatever speech-to-text captured on
          // THIS final (scored) attempt, alongside the target phrase.
          // There's no per-word "correct option" here — the teacher
          // judges pronunciation quality by comparing the two strings
          // themselves.
          widget.onTaskComplete(isCorrect, {
            'type': 'repeat_after_me',
            'targetPhrase': _phrase,
            'recognizedText': _recognizedText,
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
    // disposing it only tears down THIS screen's mic session — it can
    // no longer affect a slow_reveal screen or any other speech-using
    // screen elsewhere in the app.
    _speechService.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
                        'initials.screen_nine.repeatAfterMe'.tr(),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black45,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3,
                        ),
                      ),

                      const SizedBox(height: 6),

                      // ── Reveal button ───────────────────────────────────────────
                      // Only shown while masked, which only happens when the
                      // teacher configured this task with showPhrase == false.
                      // No cost/penalty (see _revealPhrase doc comment) — this
                      // is purely an accessibility escape hatch for when the
                      // student genuinely can't recall the phrase or the mic
                      // failed to capture it on a previous attempt.
                      if (!_isRevealed)
                        InkWell(
                          onTap: _revealPhrase,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            child: Text(
                              'initials.screen_nine.reveal'.tr(),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: Colors.blue.shade400,
                              ),
                            ),
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
                            // Phrase text — masked with dash placeholders unless
                            // the teacher set showPhrase == true or the student
                            // tapped Reveal, with correctly-recognized words
                            // un-masking in place as the student speaks (see
                            // HighlightTextWidget doc comment for the mechanic).
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                              child: HighlightTextWidget(
                                text: _phrase,
                                wordsToHighlight: _highlightWordsList,
                                isRevealed: _isRevealed,
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
                                maskedStyle: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade400,
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
                                          ? 'initials.screen_nine.playing'.tr()
                                          : 'initials.screen_nine.listenToPronunciation'.tr(),
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
                                'initials.screen_nine.wordsProgress'.tr(namedArgs: {
                                  'matched': '${_highlightWordsList.length}',
                                  'total': '${_phraseWords.length}',
                                }),
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

                      // ── Low volume warning (while listening) ───────────────────
                      // Purely advisory — never blocks recording, never
                      // counts as an error on its own. Only visible while
                      // the mic is open and the last sound-level sample
                      // was below threshold with nothing recognized yet.
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
                        _isListening
                            ? 'initials.screen_nine.listeningSpeakNow'.tr()
                            : 'initials.screen_nine.tapToSpeak'.tr(),
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500),
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