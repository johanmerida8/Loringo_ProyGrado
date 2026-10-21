import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_result.dart' as stt_result;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'phrase_matcher.dart';
import 'speech_permissions.dart';
import 'speech_recognition_result.dart';

/// Wraps the `speech_to_text` plugin for push-to-talk word/phrase
/// matching.
///
/// BUGFIX — no longer a singleton. Previously this class used a
/// `factory` constructor returning a single shared `_instance`, which
/// meant every screen that did `SpeechToTextService()` — ScreenNine
/// (repeat_after_me) and ScreenThirteen (slow_reveal) both do this in
/// their State classes exactly as if they owned a private instance —
/// was actually sharing one global object. Two concrete problems came
/// from that:
///
/// 1. Callback stomping: each screen's `_setupSpeechService()`
///    unconditionally overwrites `onFinalResult`/`onError`/etc. on
///    whatever instance it got. If a previous screen's instance hadn't
///    been fully torn down yet, a new screen's setup could silently
///    steal callbacks mid-flight, or a stale screen could still receive
///    results meant for a screen that replaced it.
/// 2. `dispose()` calling `_speech.stop()` on the ONE shared underlying
///    `stt.SpeechToText` engine — closing a mic session for the entire
///    app, not just the screen being torn down. Worse, `_isAvailable`
///    was never reset in `dispose()`, so the shared engine could be
///    left in a state where `_isAvailable == true` but the underlying
///    native engine had actually been stopped, causing later
///    `startListening()` calls to skip re-initialization and misbehave
///    intermittently — matching the "sometimes it just doesn't respond"
///    symptom.
///
/// Removing `factory`/`_instance` means `SpeechToTextService()` now
/// creates a genuinely new instance — and a new underlying
/// `stt.SpeechToText()` engine — every time. Each screen's instance is
/// fully independent: its own callbacks, its own `dispose()` blast
/// radius, no cross-talk between task types.
///
/// ROBUSTNESS PASS (this revision): addresses three concrete failure
/// modes reported in manual testing, all of which previously left the
/// student stuck with a spinning mic and no feedback:
///
/// 1. Transient `initialize()` failure. On some Android devices the
///    native speech engine isn't warmed up yet on the very first call
///    (common right after granting mic permission) and `_speech
///    .initialize()` returns false once even though a second attempt a
///    moment later succeeds. `initialize()` now retries once after a
///    short delay before giving up, instead of failing permanently on
///    the first false.
/// 2. Concurrent start calls. If the student double-taps the mic button
///    fast enough that a second `startListening()` fires before the
///    first `initialize()` finishes, both calls used to race against
///    `_isAvailable`/`_isListening`. An `_isInitializing` guard now
///    makes a second call wait on the in-flight initialization instead
///    of kicking off a duplicate one.
/// 3. Silent hang with no callback at all. `stt.listen()` normally
///    guarantees either a result or an `onStatus`/`onError` callback,
///    but on a handful of OEM Android builds the plugin has been
///    observed to never call back if the native engine dies
///    mid-session (no exception thrown either). Previously this left
///    `_isListening == true` forever with the mic UI stuck listening.
///    A local safety timer now fires `onError` and force-resets state
///    if nothing at all — no partial result, no final result, no
///    status change — arrives within [listenDuration] plus a grace
///    window. This is a pure backstop: it never fires if the plugin is
///    behaving normally, since any real result or status change cancels
///    it immediately.
class SpeechToTextService {
  SpeechToTextService();

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isAvailable = false;
  bool _isListening = false;
  String _lastRecognizedText = '';

  double _currentSoundLevel = 0.0;
  double get currentSoundLevel => _currentSoundLevel;

  // Para evitar múltiples errores de volumen bajo
  bool _hasShownLowVolumeWarning = false;

  // Guards against duplicate/concurrent initialize() calls (fix #2).
  Future<bool>? _initializingFuture;

  // Safety-net timer for silent hangs (fix #3). Cancelled the instant
  // any real callback (partial, final, status, or error) arrives.
  Timer? _watchdogTimer;

  // Tracks whether this instance has already been torn down, so a
  // watchdog firing after dispose() can't call back into a disposed
  // screen's callbacks.
  bool _isDisposed = false;

  // ACCURACY PASS: the phrase the current session is checked against, and
  // whether that session already delivered its result. Kept on the
  // instance (not just in startListening's closure) because the
  // error/watchdog paths, which live outside listen(), may now deliver a
  // result too — see _deliverFromLastHeard.
  String _targetPhrase = '';
  bool _resultDelivered = false;
  // True from startListening() until the session's verdict/error — unlike
  // _isListening, it survives the engine's "notListening" status.
  bool _sessionActive = false;

  // PATIENT MODE (opt-in via startListening(patient: true)): the engine
  // closes a segment on its own after a pause (~3s) or its listenFor limit
  // and judging that half-said phrase made students fail while still
  // speaking slowly. In patient mode a segment ending is NOT a verdict:
  // what was heard is kept in _committedText and listening restarts. The
  // session only ends when the phrase is perfect, the student taps stop,
  // no new words arrive for a few seconds, or _patientMaxTotal passes.
  bool _patient = false;
  bool _userStopped = false;
  bool _restartPending = false;
  String _committedText = '';
  // Last partial text of the CURRENT engine segment (not yet committed).
  String _segmentText = '';
  String _localeId = 'en_US';
  Duration _listenDuration = const Duration(seconds: 8);
  Timer? _idleTimer;
  Timer? _maxTimer;
  Timer? _segmentEndTimer;
  Timer? _stopFallbackTimer;
  static const Duration _patientSegmentFor = Duration(seconds: 25);
  static const Duration _patientPauseFor = Duration(seconds: 4);
  // Time allowed with no NEW words: short once the student has started
  // (they finished or are stuck), a bit longer before they say anything.
  static const Duration _patientIdleAfterSpeech = Duration(seconds: 4);
  static const Duration _patientIdleBeforeSpeech = Duration(seconds: 8);
  static const Duration _patientMaxTotal = Duration(seconds: 25);

  // Locales the device's recognizer supports, read once after a
  // successful initialize(). Used to fall back to another English locale
  // when en_US isn't installed — never to a non-English one, since every
  // speaking task is in English.
  List<String>? _deviceLocaleIds;

  // Callbacks
  VoidCallback? onListeningStart;
  VoidCallback? onListeningStop;
  Function(String)? onPartialResult;
  Function(SpeechRecognitionResult)? onFinalResult;
  Function(String)? onError;

  /// FEATURE: fired once per listening session the first time the sound
  /// level stays below threshold with nothing recognized yet. Previously
  /// this state was tracked internally (_hasShownLowVolumeWarning) but
  /// only ever reached a debugPrint — the student had no way to know
  /// the mic wasn't picking them up, so a genuinely quiet room or a
  /// phone held too far away looked identical to "not listening at
  /// all" from the UI. Screens can now surface this as a "Speak
  /// louder" hint while the mic is open. Cleared automatically the
  /// moment any speech is detected (see onSoundLevelChange below), so
  /// it never lingers as a stale warning once the student is heard.
  VoidCallback? onLowVolumeWarning;

  bool get isAvailable => _isAvailable;
  bool get isListening => _isListening;
  String get lastRecognizedText => _lastRecognizedText;

  /// Initialize speech recognition.
  ///
  /// FIX #1: retries once after a short delay if the first attempt
  /// returns false. This specifically targets the "engine not warmed up
  /// yet" case rather than genuine unavailability (e.g. no mic
  /// permission, which is checked up front and returns immediately
  /// without wasting the retry).
  ///
  /// FIX #2: if a call is already in flight, subsequent callers await
  /// the same Future instead of starting a second, redundant
  /// initialization race.
  Future<bool> initialize() async {
    if (_initializingFuture != null) {
      return _initializingFuture!;
    }
    final future = _initializeInternal();
    _initializingFuture = future;
    try {
      return await future;
    } finally {
      _initializingFuture = null;
    }
  }

  Future<bool> _initializeInternal() async {
    final hasPermission = await SpeechPermissions.isMicrophonePermissionGranted();
    if (!hasPermission) {
      debugPrint('Microphone permission not granted');
      return false;
    }

    _isAvailable = await _attemptInitialize();
    if (_isAvailable) await _loadDeviceLocales();

    // First attempt failed — this is the common "engine cold start"
    // case on some Android devices. One short-delayed retry resolves
    // it in practice without meaningfully delaying the UI (the mic
    // button already shows a listening/loading state to the student).
    if (!_isAvailable) {
      debugPrint('Speech engine not ready, retrying initialize()...');
      await Future.delayed(const Duration(milliseconds: 400));
      _isAvailable = await _attemptInitialize();
      if (_isAvailable) await _loadDeviceLocales();
    }

    return _isAvailable;
  }

  Future<void> _loadDeviceLocales() async {
    if (_deviceLocaleIds != null) return;
    try {
      final locales = await _speech.locales();
      _deviceLocaleIds = locales.map((l) => l.localeId).toList();
    } catch (e) {
      debugPrint('Could not read speech locales: $e');
    }
  }

  /// [requested] if the device supports it, otherwise another English
  /// locale it does support (en_GB, en_AU…), otherwise [requested] as-is
  /// and let the engine decide. Locale ids come back as both "en_US" and
  /// "en-US" depending on platform, so they're compared loosely.
  String _resolveLocale(String requested) {
    final ids = _deviceLocaleIds;
    if (ids == null || ids.isEmpty) return requested;
    String norm(String id) => id.replaceAll('-', '_').toLowerCase();
    for (final id in ids) {
      if (norm(id) == norm(requested)) return id;
    }
    for (final id in ids) {
      if (norm(id).startsWith('en')) return id;
    }
    return requested;
  }

  static bool _isNoMatchError(String error) {
    final e = error.toLowerCase();
    return e.contains('no_match') ||
        e.contains('no match') ||
        e.contains('speech_timeout') ||
        e.contains('no speech') ||
        e == 'timeout';
  }

  /// Builds the verdict for [heardOptions] (the recognizer's alternative
  /// interpretations, best-guess first): the FIRST one that passes wins, so
  /// the recognizer's own top reading decides and an accent can still be
  /// rescued by a lower-ranked alternative when the top one fails. If none
  /// passes, the closest one is reported.
  ///
  /// [confidences] (parallel to [heardOptions], `-1` = not reported) are the
  /// recognizer's own confidence for each interpretation; the chosen
  /// option's value is returned in the result's `confidence`.
  SpeechRecognitionResult _evaluate(
    List<String> heardOptions, {
    List<double> confidences = const [],
  }) {
    String bestText = heardOptions.isEmpty ? '' : heardOptions.first;
    PhraseMatchResult? best;
    double bestConfidence = -1;
    for (var i = 0; i < heardOptions.length; i++) {
      final heard = heardOptions[i];
      final confidence = i < confidences.length ? confidences[i] : -1.0;
      final m = PhraseMatcher.match(heard, _targetPhrase);
      // Diagnostics: shows every interpretation the recognizer offered,
      // how each one scored against the target phrase and how confident
      // the recognizer was (-1 = the device doesn't report it).
      debugPrint('Speech option: "$heard" -> ${m.matchedCount}/${m.totalCount}'
          '${m.isCorrect ? ' PASS' : ''}'
          '${m.approximateWords.isEmpty ? '' : ' ~${m.approximateWords}'}'
          ' conf=${confidence.toStringAsFixed(2)}'
          ' (target "$_targetPhrase")');
      // The first option that passes wins: the recognizer lists its most
      // likely reading first, and a lower-ranked alternative that happens
      // to be "more exact" must not hide a word the student really
      // mispronounced ("rad" first, "red" second). Until something passes,
      // keep the closest one.
      if (best == null || (!best.isCorrect && _isBetterMatch(m, best))) {
        bestText = heard;
        best = m;
        bestConfidence = confidence;
      }
    }
    best ??= PhraseMatcher.match(bestText, _targetPhrase);
    return SpeechRecognitionResult(
      recognizedText: bestText,
      isCorrect: best.isCorrect,
      accuracy: best.accuracy,
      missedWords: best.missedWords,
      approximateWords: best.approximateWords,
      confidence: bestConfidence,
    );
  }

  /// Whether [a] is a better reading than [b] when [b] hasn't passed: a
  /// passing one wins, otherwise the one with more words matched.
  static bool _isBetterMatch(PhraseMatchResult a, PhraseMatchResult b) {
    if (a.isCorrect != b.isCorrect) return a.isCorrect;
    return a.accuracy > b.accuracy;
  }

  /// Delivers a verdict built from the last partial text, for sessions
  /// that ended in "no match"/timeout after the engine had already shown
  /// the student's words on screen. Returns false (nothing delivered) if
  /// nothing was heard at all, so the caller falls back to the error.
  bool _deliverFromLastHeard() {
    if (_isDisposed || _resultDelivered || _lastRecognizedText.trim().isEmpty) {
      return false;
    }
    _resultDelivered = true;
    debugPrint('Speech: judging last partial "$_lastRecognizedText" instead of error');
    onFinalResult?.call(_evaluate([_lastRecognizedText]));
    onListeningStop?.call();
    return true;
  }

  Future<bool> _attemptInitialize() {
    return _speech.initialize(
      onError: (error) {
        debugPrint('Speech recognition error: ${error.errorMsg}');
        _cancelWatchdog();
        // Not _isListening: the engine usually reports "notListening"
        // (clearing _isListening) just BEFORE the no-match error arrives.
        final wasListening = _sessionActive;
        // Patient mode: the engine gave up on a quiet/odd segment, but the
        // student may still be working on the phrase — keep what was
        // heard and listen again instead of judging or erroring.
        if (_patient &&
            wasListening &&
            !_userStopped &&
            !_resultDelivered &&
            _isNoMatchError(error.errorMsg)) {
          _segmentEndTimer?.cancel();
          _isListening = true;
          _committedText = _lastRecognizedText;
          _scheduleRestart(delay: const Duration(milliseconds: 250));
          return;
        }
        _stopPatientTimers();
        _sessionActive = false;
        _isListening = false;
        // The session already produced its verdict (e.g. a late
        // "no match" after the final result) — don't stack an error on
        // top of the result the student is already looking at.
        if (_resultDelivered) return;
        // "No match"/"no speech" after the engine HAD shown partial text:
        // judge what it already heard instead of throwing it away.
        if (wasListening && _isNoMatchError(error.errorMsg) &&
            _deliverFromLastHeard()) {
          return;
        }
        if (!_isDisposed) onError?.call(error.errorMsg);
      },
      onStatus: (status) {
        debugPrint('Speech status: $status');
        if (status == 'notListening' && _isListening) {
          if (_patient && _sessionActive && !_userStopped && !_resultDelivered) {
            // Engine closed this segment by itself. Give its final
            // result / no-match error a moment to arrive (they are
            // handled above and below); if neither does, listen again.
            _segmentEndTimer?.cancel();
            _segmentEndTimer = Timer(const Duration(milliseconds: 150), () {
              _committedText = _lastRecognizedText;
              _scheduleRestart();
            });
            return;
          }
          _cancelWatchdog();
          _isListening = false;
          if (!_isDisposed) onListeningStop?.call();
        }
      },
    );
  }

  /// Start listening for speech.
  ///
  /// [listenDuration] bounds how long the engine will listen for before
  /// giving up on its own even if the student never speaks. Defaults to
  /// 8 seconds, matching the previous hardcoded behavior for callers
  /// that don't have a specific timing requirement (e.g. ScreenNine).
  /// Callers whose UI runs its own longer countdown — e.g. slow_reveal's
  /// 10-15s curtain reveal — should pass a [listenDuration] that covers
  /// their full window; otherwise the mic can close on its own partway
  /// through, well before the on-screen deadline, and report a spurious
  /// "no speech" error even though the student still had time left
  /// according to what they can see on screen.
  Future<void> startListening({
    String targetPhrase = '',
    String localeId = 'en_US',
    Duration listenDuration = const Duration(seconds: 8),
    bool patient = false,
  }) async {
    if (!_isAvailable) {
      final initialized = await initialize();
      if (!initialized) {
        onError?.call('Speech recognition not available');
        return;
      }
    }

    if (_isListening) return;

    // Reset warning flag
    _hasShownLowVolumeWarning = false;
    _currentSoundLevel = 0.0;

    // Fresh session state for the accuracy pass.
    _targetPhrase = targetPhrase;
    _resultDelivered = false;
    _sessionActive = true;
    _lastRecognizedText = '';

    // [patient] sessions ignore [listenDuration]: segments are long and
    // the session is bounded by the idle/max timers instead.
    _stopPatientTimers();
    _patient = patient;
    _userStopped = false;
    _committedText = '';
    _segmentText = '';
    _localeId = localeId;
    _listenDuration = patient ? _patientSegmentFor : listenDuration;

    _isListening = true;
    onListeningStart?.call();

    if (patient) {
      _armIdleTimer();
      _maxTimer = Timer(_patientMaxTotal, _finishPatient);
    }

    // FIX #3: arm the watchdog. If nothing — no partial, no final, no
    // status change, no error — comes back from the plugin within the
    // requested window plus a grace period, force a clean error state
    // instead of leaving the student staring at a stuck mic icon. Any
    // real callback below cancels this before it can fire.
    _armWatchdog(_listenDuration);

    await _listenSegment();
  }

  /// One engine listening segment. Non-patient sessions have exactly one;
  /// patient sessions chain several (see _scheduleRestart).
  Future<void> _listenSegment() async {
    await _speech.listen(
      onResult: _onSegmentResult,
      listenOptions: stt.SpeechListenOptions(
        listenFor: _listenDuration,
        // 3s (was 2s): children and English learners pause between words;
        // 2s often closed the mic mid-phrase. Patient sessions wait longer
        // and restart anyway if the engine closes early.
        pauseFor: _patient ? _patientPauseFor : const Duration(seconds: 3),
        localeId: _resolveLocale(_localeId),
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
        cancelOnError: false,
      ),
      onSoundLevelChange: _onSoundLevel,
    );
  }

  void _onSegmentResult(stt_result.SpeechRecognitionResult result) {
    _cancelWatchdog();
    _segmentEndTimer?.cancel();
    // Reset warning flag when we get any result (means speech is
    // detected) — covers the case where recognized text arrives
    // without a sound-level sample crossing the threshold first.
    _hasShownLowVolumeWarning = false;

    if (_patient) _commitIfEngineRestartedText(result.recognizedWords);

    // An empty result in patient mode (typically the engine's final after
    // a pause) means "nothing new", not "the student said nothing": keep
    // what this segment had already heard instead of erasing it.
    final keepSegment = _patient && result.recognizedWords.trim().isEmpty;
    final segment = keepSegment ? _segmentText : result.recognizedWords;

    // Everything heard in this session so far (earlier segments + this one).
    final combined = PhraseMatcher.joinSegments(_committedText, segment);

    // The student started over and said the whole phrase right ("the
    // gross" ... "the grass is green"): judge and show that attempt alone,
    // not the misheard start glued in front of it.
    final restartedAndPerfect = _patient &&
        !_userStopped &&
        !keepSegment &&
        segment != combined &&
        _isPerfect(segment);

    if (!result.finalResult) {
      if (restartedAndPerfect) {
        // Drop the misheard start: only the attempt that came out right is
        // judged and shown.
        _committedText = '';
        _lastRecognizedText = segment;
        if (!_isDisposed) onPartialResult?.call(segment);
        _finishViaFinalResult();
        return;
      }
      final changed = combined != _lastRecognizedText;
      _lastRecognizedText = combined;
      if (!_isDisposed) onPartialResult?.call(combined);
      if (_patient && !_userStopped) {
        if (changed) _armIdleTimer();
        if (_isPerfect(combined)) {
          _finishViaFinalResult();
          return;
        }
      }
      // A partial result means the engine is alive and talking to
      // us — re-arm the watchdog for the remaining window so a stall
      // *after* a partial result is still caught.
      _armWatchdog(_listenDuration);
      return;
    }

    // Judge every interpretation the recognizer offered, not just
    // its top guess — with an accent the right words are often its
    // 2nd or 3rd option.
    final alternates = result.alternates
        .where((a) => !keepSegment && a.recognizedWords.trim().isNotEmpty)
        .toList();
    final options = <String>[
      for (final a in alternates)
        PhraseMatcher.joinSegments(_committedText, a.recognizedWords),
    ];
    // The recognizer's confidence for each option (-1 = not reported).
    final confidences = <double>[
      for (final a in alternates) a.confidence,
    ];
    if (options.isEmpty) {
      options.add(combined);
      confidences.add(-1);
    }
    if (restartedAndPerfect) {
      options.insert(0, segment);
      confidences.insert(0, confidences.isEmpty ? -1 : confidences.first);
    }

    // Patient mode: the engine closed this segment, the student hasn't
    // finished (not perfect, didn't tap stop) — keep the words and listen
    // again instead of delivering a verdict.
    if (_patient &&
        !_userStopped &&
        !_resultDelivered &&
        !options.any(_isPerfect)) {
      if (combined != _lastRecognizedText) _armIdleTimer();
      _lastRecognizedText = combined;
      _committedText = combined;
      _scheduleRestart();
      return;
    }

    _lastRecognizedText = combined;
    _isListening = false;
    _sessionActive = false;
    _stopPatientTimers();
    if (_resultDelivered) return;
    _resultDelivered = true;

    if (!_isDisposed) {
      onFinalResult?.call(_evaluate(options, confidences: confidences));
      onListeningStop?.call();
    }
  }

  void _onSoundLevel(double level) {
    _currentSoundLevel = level;
    // Fire once per session — repeated low-level samples (the
    // callback runs many times a second while listening) would
    // otherwise spam the UI. _hasShownLowVolumeWarning gates that;
    // it's reset in startListening() so each new attempt gets its
    // own fresh warning if needed again.
    if (!_hasShownLowVolumeWarning && level < 0.05 && _isListening && _lastRecognizedText.isEmpty) {
      _hasShownLowVolumeWarning = true;
      debugPrint('Volume too low: $level');
      if (!_isDisposed) onLowVolumeWarning?.call();
    }
    // Speech resumed above threshold — clear the flag so a later
    // dip during the SAME session can warn again (e.g. the student
    // trails off mid-phrase) instead of staying silenced after the
    // first blip.
    if (level >= 0.05 && _hasShownLowVolumeWarning) {
      _hasShownLowVolumeWarning = false;
    }
  }

  // ── Patient mode helpers ────────────────────────────────────────────────

  /// Every word of the target was said (none missing), however exactly. Used
  /// to close the session as soon as the student finishes the phrase; the
  /// verdict itself (including "too many loose words") comes from
  /// [_evaluate].
  bool _isPerfect(String heard) {
    if (_targetPhrase.trim().isEmpty) return false;
    final m = PhraseMatcher.match(heard, _targetPhrase);
    return m.totalCount > 0 && m.matchedCount == m.totalCount;
  }

  /// After a pause the engine can start a fresh hypothesis INSIDE the same
  /// segment, without any final result: the text so far ("the apple")
  /// disappears and only the new words ("is red") come back. Detect that
  /// (the new text no longer continues the old one) and keep the old text
  /// as committed, so the session still adds up to the whole phrase —
  /// including when the student says one word at a time ("is" -> "blue").
  /// Small revisions of the same words ("to" -> "two") are not a restart.
  void _commitIfEngineRestartedText(String incoming) {
    // An empty result (the engine closing with nothing new) must never
    // wipe what this segment already heard.
    if (PhraseMatcher.words(incoming).isEmpty) return;
    if (PhraseMatcher.startsNewUtterance(_segmentText, incoming)) {
      _committedText = PhraseMatcher.joinSegments(_committedText, _segmentText);
    }
    _segmentText = incoming;
  }

  void _armIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(
      _lastRecognizedText.trim().isEmpty
          ? _patientIdleBeforeSpeech
          : _patientIdleAfterSpeech,
      _finishPatient,
    );
  }

  void _stopPatientTimers() {
    _idleTimer?.cancel();
    _maxTimer?.cancel();
    _segmentEndTimer?.cancel();
    _stopFallbackTimer?.cancel();
    _idleTimer = _maxTimer = _segmentEndTimer = _stopFallbackTimer = null;
  }

  /// Listens again after the engine closed a segment on its own.
  ///
  /// The mic is deaf between segments, so [delay] is kept as short as the
  /// engine tolerates: a word started during that gap ("is" in "the sky …
  /// is blue") is the one that gets lost. After the engine's own final
  /// result it can restart almost at once; after a bare no-match error a
  /// longer delay avoids a tight restart loop.
  void _scheduleRestart({Duration delay = const Duration(milliseconds: 80)}) {
    // The next segment starts from scratch; everything so far is committed.
    _segmentText = '';
    // The engine can report the same segment end twice (final result, then
    // a no-match error): only one restart may be in flight.
    if (_restartPending) return;
    _restartPending = true;
    Future.delayed(delay, () async {
      _restartPending = false;
      if (_isDisposed || !_sessionActive || _userStopped || _resultDelivered) {
        return;
      }
      _armWatchdog(_listenDuration);
      try {
        if (_speech.isListening) await _speech.stop();
        await _listenSegment();
      } catch (e) {
        debugPrint('Speech: could not restart listening: $e');
        _finishPatient();
      }
    });
  }

  /// The phrase is already perfect in a PARTIAL result. Partials carry no
  /// confidence, so instead of judging that text right away, stop the engine
  /// and let its FINAL result (alternatives + confidence) deliver the
  /// verdict — same mechanism as the student tapping stop. If the final
  /// result doesn't arrive in time, the fallback judges the partial text.
  void _finishViaFinalResult() {
    if (_userStopped) return; // already waiting for it
    _userStopped = true;
    _idleTimer?.cancel();
    _maxTimer?.cancel();
    _segmentEndTimer?.cancel();
    _cancelWatchdog();
    _stopFallbackTimer?.cancel();
    _stopFallbackTimer =
        Timer(const Duration(milliseconds: 1500), _finishPatient);
    _speech.stop().catchError((_) {});
  }

  /// Ends a patient session with whatever was heard: judges it, or reports
  /// a "nothing heard" timeout if there is nothing.
  void _finishPatient() {
    if (_isDisposed || _resultDelivered || !_sessionActive) return;
    _resultDelivered = true;
    _sessionActive = false;
    _isListening = false;
    _stopPatientTimers();
    _cancelWatchdog();
    _speech.stop().catchError((_) {});
    if (_lastRecognizedText.trim().isEmpty) {
      onError?.call('timeout');
    } else {
      onFinalResult?.call(_evaluate([_lastRecognizedText]));
      onListeningStop?.call();
    }
  }

  /// Arms (or re-arms) the silent-hang safety timer. `slack` gives the
  /// plugin's own `pauseFor`/`listenFor` machinery room to finish
  /// naturally before the watchdog second-guesses it.
  void _armWatchdog(Duration listenDuration) {
    _cancelWatchdog();
    const slack = Duration(seconds: 3);
    _watchdogTimer = Timer(listenDuration + slack, () {
      if (!_isListening || _isDisposed) return;
      if (_patient && _sessionActive) {
        _finishPatient();
        _speech.stop().catchError((_) {});
        return;
      }
      debugPrint('Speech watchdog: no callback received, forcing error state');
      _isListening = false;
      _sessionActive = false;
      // Same rescue as the no-match path: if words were already heard,
      // judge them rather than reporting a capture failure.
      if (!_deliverFromLastHeard() && !_resultDelivered) {
        onError?.call('timeout');
      }
      // Best-effort cleanup of the native session; ignore failures here
      // since we're already in a degraded state and the user-facing
      // error has already been dispatched above.
      _speech.stop().catchError((_) {});
    });
  }

  void _cancelWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  /// Stop listening
  Future<void> stopListening() async {
    _cancelWatchdog();
    if (_patient && _sessionActive) {
      // The student is done: judge what was heard. The engine's own final
      // result normally arrives right after stop(); if it doesn't (stopped
      // between two segments), judge the accumulated text after a moment.
      _userStopped = true;
      _idleTimer?.cancel();
      _maxTimer?.cancel();
      _segmentEndTimer?.cancel();
      _stopFallbackTimer?.cancel();
      _stopFallbackTimer = Timer(const Duration(milliseconds: 1500), _finishPatient);
    }
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
      if (!_isDisposed) onListeningStop?.call();
    }
  }

  /// Cancel listening without processing
  Future<void> cancelListening() async {
    _cancelWatchdog();
    _stopPatientTimers();
    // A cancelled session must not be "rescued" into a verdict later.
    _sessionActive = false;
    _resultDelivered = true;
    if (_isListening) {
      await _speech.cancel();
      _isListening = false;
      if (!_isDisposed) onListeningStop?.call();
    }
  }

  /// BUGFIX: previously this only called `_speech.stop()` and left
  /// `_isAvailable` untouched. Since this was a shared singleton engine,
  /// that meant the NEXT screen to reuse the (single) instance would see
  /// `_isAvailable == true` and skip re-initialization, even though the
  /// underlying native engine had just been stopped — a stale-available
  /// state that produced intermittent mic failures. Now that every
  /// screen owns its own instance, this dispose() only ever affects that
  /// screen's own engine — but the fix is kept regardless, since leaving
  /// `_isAvailable` stale after a stop is wrong either way: resetting it
  /// guarantees the next `startListening()` call on this instance (if
  /// any) properly re-initializes rather than assuming a now-stopped
  /// engine is still ready.
  ///
  /// Also cancels the watchdog and marks the instance disposed so any
  /// in-flight native callback that arrives after dispose() (a known
  /// possibility with this plugin) is a no-op instead of calling back
  /// into a State that's already been torn down.
  void dispose() {
    _isDisposed = true;
    _cancelWatchdog();
    _stopPatientTimers();
    _speech.stop();
    _isAvailable = false;
    _isListening = false;
  }
}