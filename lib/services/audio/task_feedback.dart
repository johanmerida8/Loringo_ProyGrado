// lib/services/audio/task_feedback.dart
//
// Centralizes the "respond to a correct/incorrect answer" sequence that
// was previously inlined (and duplicated) in every screen's
// `_playFeedback` method:
//
//     if (isCorrect) HapticFeedback.mediumImpact();
//     else HapticFeedback.heavyImpact();
//     FeedbackSoundService.instance.playResult(isCorrect);
//
// Splitting this into its own file/class does two things:
//   1. Makes the intent explicit at the call site — `TaskFeedback.fire`
//      instead of two separate statements that are easy to reorder or
//      forget one half of when copy-pasting into a new screen.
//   2. Keeps the haptic and sound steps independently named
//      (`_haptic` / sound service call) so if one needs to change later
//      (e.g. different haptic strength, or skipping sound when the
//      device is muted) there's one place to do it, not ten.

import 'package:flutter/services.dart';
import 'package:loringo_app/services/audio/feedback_sound_service.dart';

class TaskFeedback {
  TaskFeedback._();

  /// Fires haptic feedback and plays the success/fail sound for a task
  /// result. Fire-and-forget safe — does not need to be awaited.
  static void fire(bool isCorrect) {
    _haptic(isCorrect);
    FeedbackSoundService.instance.playResult(isCorrect);
  }

  static void _haptic(bool isCorrect) {
    if (isCorrect) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
  }
}