// lib/services/tts/reading_tts_service.dart
// Reading narration via the `generateReadingAudio` Cloud Function (Google
// Cloud Text-to-Speech). Caches synthesized audio + word-boundary metadata
// in memory per (voice, speed, text) so repeats are instant.
//
// PREFETCHING: screen_seven.dart calls prefetchPages() with every page's
// text as soon as a reading task's content loads, so by the time the
// student flips to page 3 or 8, that page's audio is either already in
// _cache or already in flight -- speak() then only has to await the same
// in-flight future rather than starting a fresh request. This is on top
// of (not a replacement for) prewarmTtsCache.ts server-side, which
// pre-synthesizes the Cloudinary-cached audio the moment a teacher saves
// the page -- prefetchPages here is what gets that already-cached audio
// (or a URL from a genuine cache-miss synthesis) into THIS device's
// in-memory cache ahead of when it's actually needed to play.
//
// WHY A CLOUD FUNCTION INSTEAD OF flutter_edge_tts: the previous
// implementation talked to Microsoft Edge's neural voices over a raw
// dart:io WebSocket, which doesn't exist on Flutter Web -- narration
// silently failed there. Moving synthesis server-side (a plain callable,
// same mechanism as moderateImage) works identically on every platform.
// See functions/src/generateReadingAudio.ts for the synthesis + word-timing
// logic (SSML <mark> timepointing takes the place of Edge's word-boundary
// events).
//
// Word boundaries: the Cloud Function returns per-word start/end times in
// milliseconds directly (no ticks-to-ms conversion needed client-side, since
// that conversion now happens server-side), used by screen_seven.dart to
// highlight the word currently being spoken.
//
// AUDIO DELIVERY: the Cloud Function returns an audioUrl (a Cloudinary URL,
// or a data: URI as a fallback -- see generateReadingAudio.ts) rather than
// raw base64 bytes, since synthesized audio is cached in Cloudinary, not in
// Firestore. just_audio plays straight from that URL via setUrl(), so there
// is no decode/StreamAudioSource step on this side any more.

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:loringo_app/services/tts/reading_voices.dart';

enum ReadingSpeed { slow, normal }

enum SpeakResult { success, cancelled, failed }

/// One word's timing within the synthesized audio, in milliseconds.
class WordTiming {
  final String text;
  final int startMs;
  final int endMs;
  const WordTiming({required this.text, required this.startMs, required this.endMs});
}

class ReadingResult {
  final String audioUrl;
  final List<WordTiming> words;
  const ReadingResult({required this.audioUrl, required this.words});
}

class ReadingTtsService {
  static final AudioPlayer _player = AudioPlayer();

  // Single source of truth for the default voice.
  static const ReadingVoice _defaultVoice = ReadingVoice.maisie;

  static ReadingVoice _voice = _defaultVoice;
  static ReadingVoice get voice => _voice;

  static ReadingSpeed _speed = ReadingSpeed.normal;
  static ReadingSpeed get speed => _speed;
  static void setSpeed(ReadingSpeed speed) => _speed = speed;

  static final Map<String, ReadingResult> _cache = {};
  static final Map<String, Future<ReadingResult?>> _inFlight = {};

  // Words for whatever is currently playing/loaded -- screen_seven reads
  // this to render the highlight.
  static List<WordTiming> _currentWords = [];
  static List<WordTiming> get currentWords => _currentWords;
  static Stream<Duration> get positionStream => _player.positionStream;

  static bool get isPlaying => _player.playing;

  /// Switches the active voice. Clears the cache since cache keys are
  /// voice-scoped (see _cacheKey) -- old entries just become unreachable
  /// dead weight rather than wrong, but clearing keeps memory from growing
  /// unbounded across repeated voice switches.
  static void setVoice(ReadingVoice newVoice) {
    if (newVoice == _voice) return;
    _voice = newVoice;
    _cache.clear();
  }

  static String _cacheKey(String text) => '${_voice.edgeId}::${_speed.name}::$text';

  static int _playToken = 0;

  static Future<SpeakResult> speak(String text, {VoidCallback? onAudioReady}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return SpeakResult.failed;

    final myToken = ++_playToken;

    await stop();
    // A newer speak() call may have come in and bumped the token while
    // we were awaiting stop() -- if so, yield to it now rather than
    // continuing to load audio nobody wants anymore.
    if (myToken != _playToken) return SpeakResult.cancelled;

    try {
      final result = await _getOrSynthesize(trimmed);
      if (myToken != _playToken) return SpeakResult.cancelled; // superseded during synthesis
      if (result == null || result.audioUrl.isEmpty) return SpeakResult.failed;

      _currentWords = result.words;
      await _player.setUrl(result.audioUrl);
      if (myToken != _playToken) return SpeakResult.cancelled; // superseded during load

      onAudioReady?.call();
      await _player.play();
      await _player.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      );
      return myToken == _playToken ? SpeakResult.success : SpeakResult.cancelled;
    } catch (e) {
      // Interruption from a newer speak()/stop() call is expected
      // traffic, not a real failure -- don't log it as an error or let
      // it surface a "couldn't play" message to the student.
      if (myToken != _playToken) return SpeakResult.cancelled;
      debugPrint('ReadingTtsService: speak failed: $e');
      return SpeakResult.failed;
    }
  }

  /// Kicks off synthesis for every page up front (title + all pages), so
  /// speak() later just hits an already-resolved (or already in-flight)
  /// cache entry instead of starting fresh. Fire-and-forget by design --
  /// callers don't await this, it just warms _cache/_inFlight in the
  /// background while the student reads. Errors are swallowed here (same
  /// as any other _getOrSynthesize failure): a page that fails to
  /// prefetch just falls back to speak()'s normal on-demand synthesis
  /// when the student actually reaches it.
  static void prefetchPages(List<String> texts) {
    for (final text in texts) {
      final trimmed = text.trim();
      if (trimmed.isEmpty) continue;
      unawaited(_getOrSynthesize(trimmed));
    }
  }

  static Future<ReadingResult?> _getOrSynthesize(String text) {
    final key = _cacheKey(text);
    final cached = _cache[key];
    if (cached != null) return Future.value(cached);

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _synthesizeAndCache(text, key);
    _inFlight[key] = future;
    future.whenComplete(() => _inFlight.remove(key));
    return future;
  }

  static Future<ReadingResult?> _synthesizeAndCache(String text, String key) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'generateReadingAudio',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final result = await callable.call({
        'text': text,
        'voice': _voice.edgeId,
        'speed': _speed.name,
      });

      final data = result.data as Map;
      final audioUrl = data['audioUrl'] as String?;
      if (audioUrl == null || audioUrl.isEmpty) {
        debugPrint('ReadingTtsService: no audio returned');
        return null;
      }

      final wordsJson = (data['words'] as List?) ?? const [];
      final words = wordsJson
          .cast<Map>()
          .map((w) => WordTiming(
                text: w['text'] as String,
                startMs: (w['startMs'] as num).toInt(),
                endMs: (w['endMs'] as num).toInt(),
              ))
          .toList();

      final reading = ReadingResult(audioUrl: audioUrl, words: words);
      _cache[key] = reading;
      return reading;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('ReadingTtsService: generateReadingAudio failed: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      // If you're debugging a "Couldn't play narration" issue: this is the
      // line that will print the real cause. Check your console/logcat
      // output right here when the error happens -- whether it's a network
      // timeout, a malformed response, or something else determines the fix.
      debugPrint('ReadingTtsService: synthesize failed: $e');
      return null;
    }
  }

  static Future<void> stop() async {
    try {
      if (_player.playing) await _player.stop();
    } catch (e) {
      debugPrint('ReadingTtsService: stop failed: $e');
    }
  }

  static Future<void> dispose() async {
    await _player.dispose();
  }
}
