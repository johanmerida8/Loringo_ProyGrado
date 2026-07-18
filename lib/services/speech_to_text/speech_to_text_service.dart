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

  // Callbacks
  VoidCallback? onListeningStart;
  VoidCallback? onListeningStop;
  Function(String)? onPartialResult;
  Function(SpeechRecognitionResult)? onFinalResult;
  Function(String)? onError;

  bool get isAvailable => _isAvailable;
  bool get isListening => _isListening;
  String get lastRecognizedText => _lastRecognizedText;

  /// Initialize speech recognition
  Future<bool> initialize() async {
    // First check permission
    final hasPermission = await SpeechPermissions.isMicrophonePermissionGranted();
    if (!hasPermission) {
      debugPrint('Microphone permission not granted');
      return false;
    }

    // Initialize speech recognition
    _isAvailable = await _speech.initialize(
      onError: (error) {
        debugPrint('Speech recognition error: ${error.errorMsg}');
        _isListening = false;
        onError?.call(error.errorMsg);
      },
      onStatus: (status) {
        debugPrint('Speech status: $status');
        if (status == 'notListening' && _isListening) {
          _isListening = false;
          onListeningStop?.call();
        }
      },
    );

    return _isAvailable;
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

    await _speech.listen(
      onResult: (result) {
        // Reset warning flag when we get any result (means speech is detected)
        _hasShownLowVolumeWarning = false;

        if (!result.finalResult) {
          _lastRecognizedText = result.recognizedWords;
          onPartialResult?.call(result.recognizedWords);
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

          onFinalResult?.call(speechResult);
          onListeningStop?.call();
        }
      },
      listenFor: listenDuration,
      pauseFor: const Duration(seconds: 2),
      localeId: localeId,
      partialResults: true,
      listenMode: stt.ListenMode.dictation,
      onSoundLevelChange: (level) {
        _currentSoundLevel = level;
        // ✅ Solo mostrar advertencia una vez y cuando no hay resultados
        if (!_hasShownLowVolumeWarning && level < 0.05 && _isListening && _lastRecognizedText.isEmpty) {
          _hasShownLowVolumeWarning = true;
          // Usar onError solo para errores reales, no para advertencias
          // Mejor manejarlo con un callback separado o simplemente no mostrar SnackBar
          debugPrint('Volume too low: $level');
        }
      },
    );
  }

  /// Stop listening
  Future<void> stopListening() async {
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
      onListeningStop?.call();
    }
  }

  /// Cancel listening without processing
  Future<void> cancelListening() async {
    if (_isListening) {
      await _speech.cancel();
      _isListening = false;
      onListeningStop?.call();
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
  void dispose() {
    _speech.stop();
    _isAvailable = false;
    _isListening = false;
  }
}