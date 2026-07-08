// lib/services/audio/feedback_sound_service.dart
//
// Centralized, race-condition-safe, delay-free player for the
// correct/incorrect feedback sound effects used across every task screen
// (screen_one through screen_ten).
//
// ── Version history ──────────────────────────────────────────────────────
// v1: single shared player, fresh setAsset() every play, token-guarded.
//     Fixed the web race, but reloading the asset on every play
//     introduced a noticeable delay.
//
// v2: two dedicated players (success/fail), preloaded once, played via
//     seek+play instead of reloading. Fixed the delay, but kept a stale
//     v1 token guard that caused "worked once then went silent".
//
// v3: removed the token guard entirely (unnecessary once success/fail
//     are separate players).
//
// v4: fixed a second silence bug — a player landing in
//     ProcessingState.completed/idle needs a full stop() before seek(),
//     not seek() alone, to be playable again reliably on web.
//
// v5 (this version): fixes first-play latency. `setAsset()` during
//     preload() only fetches the file and reads metadata — it does NOT
//     force the underlying audio engine to actually decode the codec or
//     (on web) fully initialize the AudioContext. That decode/init cost
//     was previously being paid on the *first real* play() call, which
//     is exactly why the first correct/incorrect sound in a session had
//     a noticeable delay while every one after it was instant.
//
//     The fix: preload() now also does a genuine "warm-up" play — start
//     playback at volume 0, then immediately stop and restore volume —
//     right after loading each asset. This forces the decode/init cost
//     to happen during preload (while the student is looking at the
//     loading screen / first task, not during their first answer),
//     instead of being deferred to the first time playResult() is
//     actually called for real.
//
// ── Usage ───────────────────────────────────────────────────────────────
// Call once, early, ideally right after runApp() in main.dart:
//
//     FeedbackSoundService.instance.preload();
//
// Then in every screen:
//     FeedbackSoundService.instance.playResult(isCorrect);
//
// Fire-and-forget is fine — you don't need to await this to keep the UI
// responsive, and the internal try/catch means a failure here will never
// throw into your calling code.

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class FeedbackSoundService {
  FeedbackSoundService._internal();
  static final FeedbackSoundService instance = FeedbackSoundService._internal();

  final AudioPlayer _successPlayer = AudioPlayer();
  final AudioPlayer _failPlayer = AudioPlayer();

  bool _successLoaded = false;
  bool _failLoaded = false;
  bool _successWarmed = false;
  bool _failWarmed = false;

  static const String _successAsset = 'assets/sound/success-2.mp3';
  static const String _failAsset = 'assets/sound/fail-2.mp3';

  /// Loads AND warms up both assets. Safe to call multiple times — each
  /// step only redoes the part that hasn't succeeded yet.
  ///
  /// Call this once at app startup (see main.dart). The warm-up briefly
  /// plays each sound at volume 0 so the real decode/init cost is paid
  /// here, not on the student's first actual correct/incorrect answer.
  Future<void> preload() async {
    await Future.wait([
      _ensureLoaded(_successPlayer, _successAsset, isSuccess: true),
      _ensureLoaded(_failPlayer, _failAsset, isSuccess: false),
    ]);
    await Future.wait([
      _ensureWarmed(_successPlayer, isSuccess: true),
      _ensureWarmed(_failPlayer, isSuccess: false),
    ]);
  }

  Future<void> _ensureLoaded(
    AudioPlayer player,
    String asset, {
    required bool isSuccess,
  }) async {
    if (isSuccess ? _successLoaded : _failLoaded) return;
    try {
      await player.setAsset(asset);
      if (isSuccess) {
        _successLoaded = true;
      } else {
        _failLoaded = true;
      }
    } catch (e) {
      debugPrint('FeedbackSoundService: failed to load $asset: $e');
      // Leave the loaded flag false so the next call retries.
    }
  }

  /// Forces the audio engine to actually decode/initialize by playing at
  /// volume 0 and immediately stopping. This is the step that eliminates
  /// first-play latency — without it, that decode cost gets silently
  /// deferred to the first real playResult() call.
  Future<void> _ensureWarmed(AudioPlayer player, {required bool isSuccess}) async {
    final alreadyLoaded = isSuccess ? _successLoaded : _failLoaded;
    final alreadyWarmed = isSuccess ? _successWarmed : _failWarmed;
    if (!alreadyLoaded || alreadyWarmed) return;

    try {
      await player.setVolume(0);
      await player.seek(Duration.zero);
      await player.play();
      // A few ms is enough for the engine to start actually decoding —
      // we don't need to hear it, just need the pipeline primed.
      await Future.delayed(const Duration(milliseconds: 60));
      await player.stop();
      await player.seek(Duration.zero);
      await player.setVolume(1);
      if (isSuccess) {
        _successWarmed = true;
      } else {
        _failWarmed = true;
      }
    } catch (e) {
      debugPrint('FeedbackSoundService: warm-up failed: $e');
      // Restore volume defensively even if something above threw
      // mid-sequence, so a failed warm-up never leaves playback muted.
      try {
        await player.setVolume(1);
      } catch (_) {}
    }
  }

  /// Plays the correct/incorrect feedback chime. Fire-and-forget safe.
  Future<void> playResult(bool isCorrect) async {
    final player = isCorrect ? _successPlayer : _failPlayer;
    final asset = isCorrect ? _successAsset : _failAsset;

    if (!(isCorrect ? _successLoaded : _failLoaded)) {
      await _ensureLoaded(player, asset, isSuccess: isCorrect);
    }
    // If playResult is somehow called before preload() finished the
    // warm-up step (e.g. preload() is still in flight), warm up here
    // instead of paying the latency silently on the real play — this is
    // the fallback path, preload() finishing first is the normal path.
    if (!(isCorrect ? _successWarmed : _failWarmed)) {
      await _ensureWarmed(player, isSuccess: isCorrect);
    }

    try {
      final state = player.processingState;
      final needsHardReset =
          state == ProcessingState.completed || state == ProcessingState.idle;

      if (needsHardReset) {
        await player.stop();
      }
      await player.seek(Duration.zero);
    } catch (e) {
      debugPrint('FeedbackSoundService: seek failed for $asset: $e');
      if (isCorrect) {
        _successLoaded = false;
        _successWarmed = false;
      } else {
        _failLoaded = false;
        _failWarmed = false;
      }
      await _ensureLoaded(player, asset, isSuccess: isCorrect);
    }

    try {
      await player.play();
    } catch (e) {
      debugPrint('FeedbackSoundService: play failed for $asset: $e');
    }
  }

  /// Plays an arbitrary one-off asset (not success/fail), for screens
  /// with a custom sound effect. Not preloaded/warmed, so this pays the
  /// full cost every call — use playResult for the hot-path sounds.
  Future<void> playAsset(String assetPath) async {
    final player = AudioPlayer();
    try {
      await player.setAsset(assetPath);
      await player.play();
      unawaited(
        player.playerStateStream
            .firstWhere((s) => s.processingState == ProcessingState.completed)
            .then((_) => player.dispose())
            .catchError((_) => player.dispose()),
      );
    } catch (e) {
      debugPrint('FeedbackSoundService: error playing $assetPath: $e');
      await player.dispose();
    }
  }

  Future<void> dispose() async {
    await _successPlayer.dispose();
    await _failPlayer.dispose();
  }
}

// Small local helper so we don't need to import dart:async just for this.
void unawaited(Future<void> future) {}