// lib/services/tts/task_tts_service.dart
//
// Task-oriented TTS via flutter_edge_tts (Microsoft Edge neural voices).
// Sibling to ReadingTtsService, stripped of word-boundary tracking.
// Default voice: Maisie (English child voice).
//
// VOICE SELECTION: speak() takes an optional `voice` parameter. Pass it
// explicitly at every call site rather than relying on whatever the
// LAST caller left active via setVoice() -- _voice is shared global
// state across every screen using this service. A screen that only
// ever speaks English (screen_two, screen_three, screen_six,
// screen_nine, screen_ten, screen_eleven) should always pass
// `voice: TtsVoice.maisie` explicitly; only screen_eight.dart's
// bilingual toggle has a real reason to switch voice based on
// direction. Omitting `voice` falls back to whatever _voice currently
// is -- this exists for backward compatibility and for call sites that
// deliberately manage voice state across multiple speak() calls (rare),
// but new code should prefer passing voice explicitly every time.
//
// This is what fixes the "mixed accent" bug: previously, if
// screen_eight.dart left the voice set to Ximena (Spanish) and the
// student then moved to screen_six.dart (Match, English-only) without
// screen_six ever calling setVoice() itself, English words would
// silently play in a Spanish voice. Passing voice explicitly at every
// call site makes that impossible -- no screen can inherit stale voice
// state from whatever ran before it.
//
// TWO-LAYER CACHE:
// 1. In-memory (_memCache): fastest, but wiped on app restart.
// 2. Disk (getApplicationSupportDirectory()/tts_cache/<hash>.mp3):
//    survives restarts, and is what makes previously-heard phrases
//    playable with NO internet connection. Every synthesize() result
//    is written to disk immediately; every speak()/prefetch() checks
//    disk before hitting the network. Cache key is the SHA-1 of
//    voice+text (not raw text) so switching voices/languages never
//    serves stale audio in the wrong voice, and so we don't have to
//    worry about filesystem-illegal characters in task sentences.
//
// This does NOT attempt full offline-first behavior for content never
// heard before -- that would need bundling audio as assets or a
// teacher-triggered "download this unit" flow, which is a bigger
// feature. This is the pragmatic middle ground: first play of any
// given sentence needs internet, every replay after that (including
// across app restarts) does not.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_edge_tts/flutter_edge_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:loringo_app/services/tts/tts_voices.dart';

class TaskTtsService {
  static final AudioPlayer _player = AudioPlayer();

  static TtsVoice _voice = TtsVoice.jenny;
  static TtsVoice get voice => _voice;

  static FlutterEdgeTts _tts = FlutterEdgeTts(
    voice: TtsVoice.jenny.edgeId,
    outputFormat: EdgeTtsOutputFormat.audio24Khz96KbitrateMonoMp3,
    enableWordBoundary: false,
  );

  static const EdgeTtsProsody _prosody = EdgeTtsProsody(rate: '-10%', pitch: '+0Hz');
  static final Map<String, Uint8List> _memCache = {};
  static final Map<String, Future<Uint8List?>> _inFlight = {};

  static Directory? _diskDirCache;

  static int _playToken = 0;

  static bool get isPlaying => _player.playing;

  /// Switches the active voice/language. Clears in-memory cache since
  /// cached entries are keyed by voice+text already (see _memKey), so
  /// old entries just become unreachable dead weight rather than wrong
  /// -- clearing is a memory-hygiene choice, not a correctness fix.
  static void setVoice(TtsVoice newVoice) {
    if (newVoice == _voice) return;
    _voice = newVoice;
    _tts = FlutterEdgeTts(
      voice: newVoice.edgeId,
      outputFormat: EdgeTtsOutputFormat.audio24Khz96KbitrateMonoMp3,
      enableWordBoundary: false,
    );
    _memCache.clear();
  }

  static String _memKey(String text) => '${_voice.edgeId}::$text';

  /// [voice] should be passed explicitly by every call site that knows
  /// what language it's speaking -- see the class-level doc comment for
  /// why. When provided, switches to it (via setVoice) before speaking;
  /// when omitted, uses whatever _voice currently is.
  static Future<bool> speak(String text, {TtsVoice? voice}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    if (voice != null) setVoice(voice);

    final myToken = ++_playToken;

    await stop();
    if (myToken != _playToken) return false;

    try {
      final bytes = await _getOrSynthesize(trimmed);
      if (myToken != _playToken) return false;
      if (bytes == null || bytes.isEmpty) return false;

      await _player.setAudioSource(_BytesAudioSource(bytes));
      if (myToken != _playToken) return false;

      await _player.play();
      await _player.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      );
      return myToken == _playToken;
    } catch (e) {
      if (myToken != _playToken) return false;
      debugPrint('TaskTtsService: speak failed: $e');
      return false;
    }
  }

  /// [voice], same rationale as speak() -- pass explicitly so prefetch
  /// warms the cache under the voice that will actually be used to
  /// play it later, not whatever was active when prefetch() happened
  /// to be called.
  static void prefetch(List<String> texts, {TtsVoice? voice}) {
    if (voice != null) setVoice(voice);
    for (final text in texts) {
      final trimmed = text.trim();
      if (trimmed.isEmpty) continue;
      _getOrSynthesize(trimmed); // fire-and-forget, not awaited
    }
  }

  static Future<Uint8List?> _getOrSynthesize(String text) {
    final key = _memKey(text);
    final memHit = _memCache[key];
    if (memHit != null) return Future.value(memHit);

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _resolveFromDiskOrNetwork(text, key);
    _inFlight[key] = future;
    future.whenComplete(() => _inFlight.remove(key));
    return future;
  }

  static Future<Uint8List?> _resolveFromDiskOrNetwork(String text, String memKey) async {
    final file = await _diskFileFor(text);

    if (file != null && await file.exists()) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          _memCache[memKey] = bytes;
          return bytes;
        }
      } catch (e) {
        debugPrint('TaskTtsService: disk read failed, refetching: $e');
      }
    }

    try {
      final result = await _tts.synthesize(text, prosody: _prosody);
      if (result.audioBytes.isEmpty) return null;

      _memCache[memKey] = result.audioBytes;

      if (file != null) {
        try {
          await file.writeAsBytes(result.audioBytes, flush: true);
        } catch (e) {
          debugPrint('TaskTtsService: disk write failed: $e');
        }
      }

      return result.audioBytes;
    } catch (e) {
      debugPrint('TaskTtsService: synthesize failed (no internet?): $e');
      return null;
    }
  }

  static Future<Directory?> _diskDir() async {
    if (_diskDirCache != null) return _diskDirCache;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/tts_cache');
      if (!await dir.exists()) await dir.create(recursive: true);
      _diskDirCache = dir;
      return dir;
    } catch (e) {
      debugPrint('TaskTtsService: could not resolve cache dir: $e');
      return null;
    }
  }

  static Future<File?> _diskFileFor(String text) async {
    final dir = await _diskDir();
    if (dir == null) return null;
    final hash = sha1.convert(utf8.encode('${_voice.edgeId}::$text')).toString();
    return File('${dir.path}/$hash.mp3');
  }

  static Future<void> stop() async {
    try {
      if (_player.playing) await _player.stop();
    } catch (e) {
      debugPrint('TaskTtsService: stop failed: $e');
    }
  }

  static Future<void> dispose() async {
    await _player.dispose();
    await _tts.close();
  }
}

class _BytesAudioSource extends StreamAudioSource {
  final Uint8List _bytes;
  _BytesAudioSource(this._bytes) : super(tag: 'task-tts');

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