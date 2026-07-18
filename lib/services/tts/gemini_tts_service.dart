// // lib/services/tts/gemini_tts_service.dart
// //
// // Client-side wrapper around the `generateReadingAudio` Cloud Function,
// // following the OneSignalNotificationService pattern: static methods,
// // FirebaseFunctions.instance.httpsCallable(...), try/catch with
// // debugPrint. Used ONLY for reading narration.
// //
// // v2: speak() now accepts optional onAudioReady callback, fired the
// // instant playback actually starts (audio decoded, player.play() has
// // been called) — separate from the network/generation wait that
// // precedes it. Callers that want to show a loading state during the
// // network round-trip (which can take several seconds for a full page
// // of text — there's no way around that with a network-backed TTS
// // engine) can use this to know exactly when to switch from "loading" to
// // "speaking" UI, instead of guessing or showing "speaking" prematurely
// // the moment speak() is called.

// import 'dart:convert';
// import 'dart:typed_data';

// import 'package:cloud_functions/cloud_functions.dart';
// import 'package:flutter/foundation.dart';
// import 'package:just_audio/just_audio.dart';

// class GeminiTtsService {
//   static final AudioPlayer _player = AudioPlayer();
//   static final Map<String, Uint8List> _audioCache = {};
//   static String? _currentKey;

//   static bool get isPlaying => _player.playing;

//   static bool isCurrentText(String text) =>
//       _currentKey == text && isPlaying;

//   /// Speaks [text] via the generateReadingAudio Cloud Function.
//   ///
//   /// [onAudioReady] fires right before playback actually starts (after
//   /// the network fetch + decode is done) — use it to switch a "loading"
//   /// UI state to a "speaking" one at the right moment. Not called at all
//   /// if speak() fails before reaching playback, or if the audio was
//   /// already cached (fires immediately in that case, since there's no
//   /// network wait).
//   ///
//   /// Returns true on success, false on any failure (network, no audio
//   /// returned, playback error) — logged via debugPrint either way.
//   static Future<bool> speak(
//     String text, {
//     VoidCallback? onAudioReady,
//   }) async {
//     final trimmed = text.trim();
//     if (trimmed.isEmpty) return false;

//     await stop();

//     try {
//       final wavBytes = _audioCache[trimmed] ?? await _fetchAndCache(trimmed);
//       if (wavBytes == null) return false;

//       _currentKey = trimmed;
//       await _player.setAudioSource(_BytesAudioSource(wavBytes));

//       onAudioReady?.call();

//       await _player.play();
//       await _player.playerStateStream.firstWhere(
//         (state) => state.processingState == ProcessingState.completed,
//       );
//       return true;
//     } catch (e) {
//       debugPrint('GeminiTtsService: speak failed: $e');
//       return false;
//     }
//   }

//   static Future<void> stop() async {
//     try {
//       if (_player.playing) await _player.stop();
//     } catch (e) {
//       debugPrint('GeminiTtsService: stop failed: $e');
//     }
//     _currentKey = null;
//   }

//   static Future<Uint8List?> _fetchAndCache(String text) async {
//     try {
//       final callable = FirebaseFunctions.instance.httpsCallable(
//         'generateReadingAudio',
//         options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
//       );
//       final result = await callable.call({'text': text});

//       final data = result.data as Map<dynamic, dynamic>?;
//       final audioBase64 = data?['audioBase64'] as String?;
//       if (audioBase64 == null || audioBase64.isEmpty) {
//         debugPrint('GeminiTtsService: no audio returned');
//         return null;
//       }

//       final pcmBytes = base64Decode(audioBase64);
//       final wavBytes = _pcmToWav(pcmBytes, sampleRate: 24000, channels: 1);

//       _audioCache[text] = wavBytes;
//       return wavBytes;
//     } on FirebaseFunctionsException catch (e) {
//       debugPrint('generateReadingAudio failed: ${e.code} - ${e.message}');
//       return null;
//     } catch (e) {
//       debugPrint('GeminiTtsService: fetch error: $e');
//       return null;
//     }
//   }

//   static Uint8List _pcmToWav(
//     Uint8List pcmData, {
//     required int sampleRate,
//     required int channels,
//     int bitsPerSample = 16,
//   }) {
//     final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
//     final blockAlign = channels * bitsPerSample ~/ 8;
//     final dataLength = pcmData.length;
//     final fileLength = 44 + dataLength - 8;

//     final header = BytesBuilder();
//     void writeString(String s) => header.add(ascii.encode(s));
//     void writeUint32(int v) {
//       final b = ByteData(4)..setUint32(0, v, Endian.little);
//       header.add(b.buffer.asUint8List());
//     }

//     void writeUint16(int v) {
//       final b = ByteData(2)..setUint16(0, v, Endian.little);
//       header.add(b.buffer.asUint8List());
//     }

//     writeString('RIFF');
//     writeUint32(fileLength);
//     writeString('WAVE');
//     writeString('fmt ');
//     writeUint32(16);
//     writeUint16(1);
//     writeUint16(channels);
//     writeUint32(sampleRate);
//     writeUint32(byteRate);
//     writeUint16(blockAlign);
//     writeUint16(bitsPerSample);
//     writeString('data');
//     writeUint32(dataLength);

//     return Uint8List.fromList([...header.toBytes(), ...pcmData]);
//   }

//   static Future<void> dispose() async {
//     await _player.dispose();
//   }
// }

// class _BytesAudioSource extends StreamAudioSource {
//   final Uint8List _bytes;
//   _BytesAudioSource(this._bytes) : super(tag: 'gemini-tts');

//   @override
//   Future<StreamAudioResponse> request([int? start, int? end]) async {
//     start ??= 0;
//     end ??= _bytes.length;
//     return StreamAudioResponse(
//       sourceLength: _bytes.length,
//       contentLength: end - start,
//       offset: start,
//       stream: Stream.value(_bytes.sublist(start, end)),
//       contentType: 'audio/wav',
//     );
//   }
// }