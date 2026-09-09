// lib/services/tts/task_tts_service.dart
//
// Task-oriented TTS via the `generateTaskAudio` Cloud Function (Google Cloud
// Text-to-Speech). Sibling to ReadingTtsService, stripped of word-boundary
// tracking, but sharing the same "synthesize server-side, cache client-side"
// shape.
//
// WHY A CLOUD FUNCTION INSTEAD OF flutter_tts: flutter_tts wraps each
// platform's native speech engine (Android TextToSpeech, iOS/macOS
// AVSpeechSynthesizer, the browser's Web Speech API), selecting only by
// locale (e.g. "en-GB") and letting the platform pick its own installed
// voice. That works everywhere but means the SAME locale sounds like a
// different person on different platforms/browsers -- e.g. en-GB came out
// as a woman's voice on mobile and a man's voice on web. Moving synthesis
// server-side to a specific named Google voice (same mechanism
// ReadingTtsService already uses for reading narration, see
// functions/src/generateTaskAudio.ts) makes it identical everywhere.
//
// CACHING: two layers --
//   - In-memory here, per (voice, text), for the lifetime of the app
//     session: repeat taps on the same prompt within a session skip the
//     network entirely.
//   - Server-side in Firestore (see generateTaskAudio.ts's `ttsCache`
//     collection), per (voice, text), persisted across sessions/devices:
//     since task text is per-task Firestore content played by every student
//     assigned to it, only the very first play of a given prompt anywhere
//     pays for Cloud TTS synthesis.
//
// VOICE SELECTION: speak() takes an optional `voice` parameter. Pass it
// explicitly at every call site rather than relying on whatever the LAST
// caller left active via setVoice() -- _voice is shared global state across
// every screen using this service. A screen that only ever speaks English
// should always pass `voice: TtsVoiceDefaults.defaultEnglish`; only
// screen_eight.dart's bilingual toggle has a real reason to switch voice
// based on direction. Omitting `voice` falls back to whatever _voice
// currently is.
//
// AUDIO DELIVERY: the Cloud Function returns an audioUrl (a Cloudinary URL,
// or a data: URI as a fallback -- see generateTaskAudio.ts) rather than raw
// base64 bytes, since synthesized audio is cached in Cloudinary, not in
// Firestore. just_audio plays straight from that URL via setUrl().

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:loringo_app/services/tts/tts_voices.dart';

class TaskTtsService {
  static final AudioPlayer _player = AudioPlayer();

  static TtsVoice _voice = TtsVoice.jenny;
  static TtsVoice get voice => _voice;

  static bool get isPlaying => _player.playing;

  static final Map<String, String> _cache = {};
  static final Map<String, Future<String?>> _inFlight = {};

  static String _cacheKey(TtsVoice voice, String text) => '${voice.edgeId}::$text';

  static int _playToken = 0;

  /// Switches the active voice.
  static void setVoice(TtsVoice newVoice) {
    _voice = newVoice;
  }

  /// [voice] should be passed explicitly by every call site that knows what
  /// language it's speaking -- see the class-level doc comment for why.
  /// When provided, switches to it (via setVoice) before speaking; when
  /// omitted, uses whatever _voice currently is.
  static Future<bool> speak(String text, {TtsVoice? voice}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    if (voice != null) setVoice(voice);
    final activeVoice = _voice;

    final myToken = ++_playToken;
    await stop();
    if (myToken != _playToken) return false;

    try {
      final audioUrl = await _getOrSynthesize(activeVoice, trimmed);
      if (myToken != _playToken) return false;
      if (audioUrl == null || audioUrl.isEmpty) return false;

      await _player.setUrl(audioUrl);
      if (myToken != _playToken) return false;

      await _player.play();
      return myToken == _playToken;
    } catch (e) {
      if (myToken != _playToken) return false;
      debugPrint('TaskTtsService: speak failed: $e');
      return false;
    }
  }

  static Future<String?> _getOrSynthesize(TtsVoice voice, String text) {
    final key = _cacheKey(voice, text);
    final cached = _cache[key];
    if (cached != null) return Future.value(cached);

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _synthesizeAndCache(voice, text, key);
    _inFlight[key] = future;
    future.whenComplete(() => _inFlight.remove(key));
    return future;
  }

  static Future<String?> _synthesizeAndCache(
    TtsVoice voice,
    String text,
    String key,
  ) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'generateTaskAudio',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final result = await callable.call({
        'text': text,
        'voice': voice.edgeId,
      });

      final data = result.data as Map;
      final audioUrl = data['audioUrl'] as String?;
      if (audioUrl == null || audioUrl.isEmpty) {
        debugPrint('TaskTtsService: no audio returned');
        return null;
      }

      _cache[key] = audioUrl;
      return audioUrl;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('TaskTtsService: generateTaskAudio failed: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      debugPrint('TaskTtsService: synthesize failed: $e');
      return null;
    }
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
  }
}
