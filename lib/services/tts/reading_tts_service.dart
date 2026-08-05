// lib/services/tts/reading_tts_service.dart
// Reading narration via flutter_edge_tts (Microsoft Edge neural voices).
// Free, no API key, no quota. Default voice: Oliver (en-GB-OliverNeural).
// Caches synthesized audio + word-boundary metadata in memory per
// (voice, speed, text) so repeats are instant. Call prefetchPages() after
// loading a task to warm the cache in the background.
//
// Word boundaries: enableWordBoundary:true makes synthesize() return
// per-word timing (offset/duration in 100ns ticks) alongside the audio,
// used by screen_seven.dart to highlight the word currently being
// spoken. Converted to milliseconds here (ticks / 10000) so callers
// don't need to know about ticks.
//
// FIX: _voice and _tts were previously initialized to two different
// voices (_voice defaulted to maisie, _tts was hardcoded to oliver's
// edgeId) -- callers reading `voice` would see "maisie" while audio
// actually played in Oliver's voice, and any code trusting `voice` for
// display/cache-key purposes would be wrong from the very first launch,
// before setVoice() was ever called. Both are now seeded from the same
// ReadingVoice value so they can never disagree on startup.
//
// FIX: _cacheKey did not include the voice, only speed+text. Once
// voice became switchable, replaying the same text after a setVoice()
// call would silently return the PREVIOUS voice's cached audio instead
// of resynthesizing -- the student would hear the old voice with no
// error, which is worse than a crash because it's silent. Voice is now
// part of the key.

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_edge_tts/flutter_edge_tts.dart';
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
  final Uint8List audioBytes;
  final List<WordTiming> words;
  const ReadingResult({required this.audioBytes, required this.words});
}

class ReadingTtsService {
  static final AudioPlayer _player = AudioPlayer();

  // Single source of truth for the default voice. Both _voice and the
  // initial _tts instance are seeded from this constant so they start
  // in agreement -- change this one line to change the app-wide default.
  static const ReadingVoice _defaultVoice = ReadingVoice.ryan;

  static ReadingVoice _voice = _defaultVoice;
  static ReadingVoice get voice => _voice;

  static FlutterEdgeTts _tts = FlutterEdgeTts(
    voice: _defaultVoice.edgeId,
    outputFormat: EdgeTtsOutputFormat.audio24Khz96KbitrateMonoMp3,
    enableWordBoundary: true,
  );

  static const Map<ReadingSpeed, EdgeTtsProsody> _prosodyBySpeed = {
    ReadingSpeed.slow: EdgeTtsProsody(rate: '-50%', pitch: '+3Hz'),
    ReadingSpeed.normal: EdgeTtsProsody(rate: '-25%', pitch: '+3Hz'),
  };

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
  /// voice-scoped (see _cacheKey) -- old entries just become
  /// unreachable dead weight rather than wrong, but clearing keeps
  /// memory from growing unbounded across repeated voice switches.
  static void setVoice(ReadingVoice newVoice) {
    if (newVoice == _voice) return;
    _voice = newVoice;
    _tts = FlutterEdgeTts(
      voice: newVoice.edgeId,
      outputFormat: EdgeTtsOutputFormat.audio24Khz96KbitrateMonoMp3,
      enableWordBoundary: true,
    );
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
      if (result == null || result.audioBytes.isEmpty) return SpeakResult.failed;

      _currentWords = result.words;
      await _player.setAudioSource(_BytesAudioSource(result.audioBytes));
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

  /// Warms the cache in the background for the current voice+speed.
  /// Not awaited.
  static void prefetchPages(List<String> texts) {
    () async {
      for (final text in texts) {
        final trimmed = text.trim();
        if (trimmed.isEmpty) continue;
        await _getOrSynthesize(trimmed);
      }
    }();
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
      final result = await _tts.synthesize(text, prosody: _prosodyBySpeed[_speed]!);
      if (result.audioBytes.isEmpty) return null;

      final words = <WordTiming>[];
      for (final item in result.metadata) {
        if (item.type != 'WordBoundary') continue;
        final word = item.data.text?.text;
        if (word == null || word.isEmpty) continue;
        // offset/duration are in 100ns ticks -- /10000 to get ms.
        final startMs = item.data.offset ~/ 10000;
        final endMs = startMs + (item.data.duration ~/ 10000);
        words.add(WordTiming(text: word, startMs: startMs, endMs: endMs));
      }

      final reading = ReadingResult(audioBytes: result.audioBytes, words: words);
      _cache[key] = reading;
      return reading;
    } catch (e) {
      // If you're debugging the "Couldn't play narration" issue with
      // Oliver: this is the line that will print the real cause. Check
      // your console/logcat output right here when the error happens --
      // whether it's a network timeout, a word-boundary parsing failure
      // specific to this voice, or something else determines the fix.
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
    await _tts.close();
  }
}

class _BytesAudioSource extends StreamAudioSource {
  final Uint8List _bytes;
  _BytesAudioSource(this._bytes) : super(tag: 'reading-tts');

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: 'audio/mpeg',
    );
  }
}