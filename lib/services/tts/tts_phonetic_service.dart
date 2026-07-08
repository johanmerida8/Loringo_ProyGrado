// tts_phonetic_service.dart
//
// Centralizes phonetic corrections for words the on-device TTS engine
// mispronounces (most commonly: short proper names that get spelled out
// letter-by-letter instead of read as a word, e.g. "Mia" -> "M, I, A").
//
// Shared by reading_task.dart (teacher preview) and screen_seven.dart
// (student playback) so both always speak the same way — avoids the kind
// of drift we had before with audioData living in two places.
//
// The corrections file is a simple JSON map of {original: phonetic spelling}
// loaded once and cached. The ORIGINAL text is always what's displayed on
// screen; only the string handed to flutter_tts's speak() is substituted.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class TtsPhoneticService {
  TtsPhoneticService._internal();
  static final TtsPhoneticService instance = TtsPhoneticService._internal();

  static const String _assetPath = 'assets/data/tts_phonetic_fixes.json';

  Map<String, String> _fixes = {};
  bool _loaded = false;

  /// Loads (and caches) the phonetic fixes map. Safe to call multiple times
  /// — only reads the asset once. Call this once at app startup, or lazily
  /// before the first _applyFixes call; either works since it's idempotent.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _fixes = decoded.map((k, v) => MapEntry(k, v.toString()));
      _loaded = true;
    } catch (e) {
      debugPrint('[TtsPhoneticService] Could not load $_assetPath: $e');
      // Fail open: no corrections applied, but TTS still works with the
      // original (possibly mispronounced) text rather than crashing.
      _fixes = {};
      _loaded = true;
    }
  }

  /// Returns [text] with any known mispronounced words swapped for their
  /// phonetic spelling. Word-boundary matching so "Mia" doesn't also match
  /// inside a longer word like "Miami". Case-sensitive by design — "mia"
  /// lowercase mid-sentence is unlikely to be the name and safer to leave
  /// untouched.
  String applyFixes(String text) {
    if (_fixes.isEmpty) return text;
    String result = text;
    for (final entry in _fixes.entries) {
      final pattern = RegExp(r'\b' + RegExp.escape(entry.key) + r'\b');
      result = result.replaceAll(pattern, entry.value);
    }
    return result;
  }

  /// Adds or updates a single correction at runtime (in-memory only — does
  /// not persist back to the asset file). Useful if you ever want to let a
  /// teacher add a fix from within the app without shipping a new build.
  void addRuntimeFix(String original, String phonetic) {
    _fixes[original] = phonetic;
  }

  bool get isLoaded => _loaded;
}