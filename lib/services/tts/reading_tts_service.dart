// lib/services/tts/reading_tts_service.dart
// Reading narration via flutter_edge_tts (Microsoft Edge neural voices).
// Free, no API key, no quota. Voice: en-GB-SoniaNeural.
// Caches synthesized audio + word-boundary metadata in memory per
// (text, speed) so repeats are instant. Call prefetchPages() after
// loading a task to warm the cache in the background.
//
// Word boundaries: enableWordBoundary:true makes synthesize() return
// per-word timing (offset/duration in 100ns ticks) alongside the audio,
// used by screen_seven.dart to highlight the word currently being
// spoken. Converted to milliseconds here (ticks / 10000) so callers
// don't need to know about ticks.

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_edge_tts/flutter_edge_tts.dart';
import 'package:just_audio/just_audio.dart';

enum ReadingSpeed { slow, normal }

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
  static const String _voice = 'en-GB-SoniaNeural';

  static final FlutterEdgeTts _tts = FlutterEdgeTts(
    voice: _voice,
    outputFormat: EdgeTtsOutputFormat.audio24Khz96KbitrateMonoMp3,
    enableWordBoundary: true,
  );

  static const Map<ReadingSpeed, EdgeTtsProsody> _prosodyBySpeed = {
    ReadingSpeed.slow: EdgeTtsProsody(rate: '-40%', pitch: '+3Hz'),
    ReadingSpeed.normal: EdgeTtsProsody(rate: '-20%', pitch: '+3Hz'),
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

  static String _cacheKey(String text) => '${_speed.name}::$text';

  static Future<bool> speak(String text, {VoidCallback? onAudioReady}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    await stop();

    try {
      final result = await _getOrSynthesize(trimmed);
      if (result == null || result.audioBytes.isEmpty) return false;

      _currentWords = result.words;
      await _player.setAudioSource(_BytesAudioSource(result.audioBytes));
      onAudioReady?.call();
      await _player.play();
      await _player.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      );
      return true;
    } catch (e) {
      debugPrint('ReadingTtsService: speak failed: $e');
      return false;
    }
  }

  /// Warms the cache in the background for the current speed. Not awaited.
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