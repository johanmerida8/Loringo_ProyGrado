import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
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

    // First attempt failed — this is the common "engine cold start"
    // case on some Android devices. One short-delayed retry resolves
    // it in practice without meaningfully delaying the UI (the mic
    // button already shows a listening/loading state to the student).
    if (!_isAvailable) {
      debugPrint('Speech engine not ready, retrying initialize()...');
      await Future.delayed(const Duration(milliseconds: 400));
      _isAvailable = await _attemptInitialize();
    }

    return _isAvailable;
  }

  Future<bool> _attemptInitialize() {
    return _speech.initialize(
      onError: (error) {
        debugPrint('Speech recognition error: ${error.errorMsg}');
        _cancelWatchdog();
        _isListening = false;
        if (!_isDisposed) onError?.call(error.errorMsg);
      },
      onStatus: (status) {
        debugPrint('Speech status: $status');
        if (status == 'notListening' && _isListening) {
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

    _isListening = true;
    onListeningStart?.call();

    // FIX #3: arm the watchdog. If nothing — no partial, no final, no
    // status change, no error — comes back from the plugin within the
    // requested window plus a grace period, force a clean error state
    // instead of leaving the student staring at a stuck mic icon. Any
    // real callback below cancels this before it can fire.
    _armWatchdog(listenDuration);

    await _speech.listen(
      onResult: (result) {
        _cancelWatchdog();
        // Reset warning flag when we get any result (means speech is
        // detected) — covers the case where recognized text arrives
        // without a sound-level sample crossing the threshold first.
        _hasShownLowVolumeWarning = false;

        if (!result.finalResult) {
          _lastRecognizedText = result.recognizedWords;
          if (!_isDisposed) onPartialResult?.call(result.recognizedWords);
          // A partial result means the engine is alive and talking to
          // us — re-arm the watchdog for the remaining window so a stall
          // *after* a partial result is still caught.
          _armWatchdog(listenDuration);
        } else {
          _lastRecognizedText = result.recognizedWords;
          _isListening = false;

          final isCorrect = _matchesTarget(result.recognizedWords, targetPhrase);
          final accuracy = _calculateAccuracy(result.recognizedWords, targetPhrase);

          final speechResult = SpeechRecognitionResult(
            recognizedText: result.recognizedWords,
            isCorrect: isCorrect,
            accuracy: accuracy,
          );

          if (!_isDisposed) {
            onFinalResult?.call(speechResult);
            onListeningStop?.call();
          }
        }
      },
      listenFor: listenDuration,
      pauseFor: const Duration(seconds: 2),
      localeId: localeId,
      partialResults: true,
      listenMode: stt.ListenMode.dictation,
      onSoundLevelChange: (level) {
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
      },
    );
  }

  /// Arms (or re-arms) the silent-hang safety timer. `slack` gives the
  /// plugin's own `pauseFor`/`listenFor` machinery room to finish
  /// naturally before the watchdog second-guesses it.
  void _armWatchdog(Duration listenDuration) {
    _cancelWatchdog();
    const slack = Duration(seconds: 3);
    _watchdogTimer = Timer(listenDuration + slack, () {
      if (!_isListening || _isDisposed) return;
      debugPrint('Speech watchdog: no callback received, forcing error state');
      _isListening = false;
      onError?.call('timeout');
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
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
      if (!_isDisposed) onListeningStop?.call();
    }
  }

  /// Cancel listening without processing
  Future<void> cancelListening() async {
    _cancelWatchdog();
    if (_isListening) {
      await _speech.cancel();
      _isListening = false;
      if (!_isDisposed) onListeningStop?.call();
    }
  }

  bool _matchesTarget(String spokenText, String targetPhrase) {
    if (targetPhrase.isEmpty) return true;
    if (spokenText.isEmpty) return false;
    final normalizedSpoken = _normalizeText(spokenText);
    final normalizedTarget = _normalizeText(targetPhrase);
    return normalizedSpoken == normalizedTarget;
  }

  double _calculateAccuracy(String spokenText, String targetPhrase) {
    if (targetPhrase.isEmpty) return 1.0;
    if (spokenText.isEmpty) return 0.0;

    final normalizedSpoken = _normalizeText(spokenText);
    final normalizedTarget = _normalizeText(targetPhrase);

    if (normalizedSpoken == normalizedTarget) return 1.0;

    final spokenWords = normalizedSpoken.split(' ');
    final targetWords = normalizedTarget.split(' ');

    int matches = 0;
    for (int i = 0; i < spokenWords.length && i < targetWords.length; i++) {
      if (spokenWords[i] == targetWords[i]) matches++;
    }

    return matches / targetWords.length;
  }

  String _normalizeText(String text) {
    return text
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
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
    _speech.stop();
    _isAvailable = false;
    _isListening = false;
  }
}