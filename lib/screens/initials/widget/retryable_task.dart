// lib/screens/initials/widget/retryable_task.dart
//
// Shared "one extra try" mechanic for task screens where a wrong answer
// on the FIRST attempt shouldn't immediately count against the student —
// it should offer one more shot right there, in place, before it's
// scored as wrong and handed off to ActivityPlayScreen (which then
// queues it for the end-of-activity review round as usual).
//
// This is a separate, earlier mechanism than isPracticeRound / the
// review round itself. isPracticeRound still means exactly what it did
// before (see task_result_sheet.dart's v3 note): it only affects
// wording/behavior for tasks being REPLAYED at the end of the activity
// after being queued from a first-pass wrong answer. This mixin only
// affects the FIRST pass — attempt 1 wrong -> retry locally; attempt 2
// wrong -> count it wrong and call onTaskComplete(false) exactly like
// every screen already did before this mixin existed. The two systems
// don't overlap: by the time a task reaches the review round, this
// mixin's attempt counter has already been reset (see resetAttempts)
// and the screen gets its 2 fresh local attempts there too, same as the
// first pass — ActivityPlayScreen's own review-retry-on-wrong loop
// still governs how many times the review task itself can be replayed
// after that.
//
// ── What this mixin owns ─────────────────────────────────────────────
// - The attempt counter (max 2 attempts total per task instance).
// - Deciding, given a correctness result, whether this was a "soft"
//   wrong answer (attempts remain -> local retry) or a "hard" wrong
//   answer (attempts exhausted -> score it, hand off to
//   onTaskComplete(false) same as always).
// - Showing the retry-prompt sheet (orange, "Try Again") for the soft
//   case, via a lightweight sheet distinct from TaskResultSheet — it is
//   NOT a task result (nothing was scored yet), so reusing
//   TaskResultSheet's isCorrect:false styling/copy would misrepresent
//   what's actually happening to the student.
//
// ── What this mixin does NOT own ─────────────────────────────────────
// - Resetting each screen's own local answer-selection state
//   (_selectedOptionEn, _droppedWords, _selectedWords, selectedOption,
//   etc.) — that's screen-specific, so it's the required onRetry
//   callback the screen supplies.
// - Showing TaskResultSheet for the correct case or the hard-wrong
//   case — screens keep calling TaskResultSheet.show themselves for
//   those, exactly as before. This mixin is consulted BEFORE that call
//   to decide whether this particular wrong answer should short-circuit
//   into a local retry instead.
//
// ── Usage in a screen ─────────────────────────────────────────────────
//   class _ScreenOneState extends State<ScreenOne> with RetryableTask {
//     void _checkAnswer() {
//       final isCorrect = ...;
//       TaskFeedback.fire(isCorrect);
//
//       if (!isCorrect && offerRetry(
//         context: context,
//         onRetry: () => setState(() => selectedOption = ''),
//       )) {
//         return; // retry sheet shown, local state reset, stop here
//       }
//
//       TaskResultSheet.show(
//         context,
//         isCorrect: isCorrect,
//         isPracticeRound: widget.isPracticeRound,
//         onContinue: () => widget.onTaskComplete?.call(isCorrect),
//       );
//     }
//   }
//
// offerRetry returns true (and has already shown the retry sheet +
// invoked onRetry) when this was a soft wrong answer the screen should
// swallow. It returns false when the screen should proceed to its
// normal TaskResultSheet call — either because the answer was correct
// (callers only invoke offerRetry on a wrong answer, but it's harmless
// either way) or because attempts are exhausted.

import 'package:flutter/material.dart';

mixin RetryableTask<T extends StatefulWidget> on State<T> {
  int _attemptCount = 0;

  /// Total attempts made so far on the current task instance (resets
  /// via [resetAttempts], typically when ActivityPlayScreen rebuilds
  /// this screen fresh for the review round — same trigger point every
  /// screen already resets its own local selection state at).
  int get attemptCount => _attemptCount;

  /// Hard-coded at 2 per the agreed mechanic: first wrong answer offers
  /// one retry, second wrong answer counts. Not exposed as a parameter
  /// to keep the 8 call sites identical — if a screen ever needs a
  /// different count, that's a deliberate enough deviation to warrant
  /// its own explicit logic rather than a silent parameter.
  static const int _maxAttempts = 2;

  bool get hasAttemptsLeft => _attemptCount < _maxAttempts;

  void resetAttempts() {
    _attemptCount = 0;
  }

  /// Call this on a WRONG answer, before showing TaskResultSheet.
  ///
  /// Increments the attempt counter. If attempts remain, shows the
  /// retry-prompt sheet, calls [onRetry] once the student dismisses it
  /// (so the screen can clear its local selection), and returns true —
  /// the caller should return immediately without showing
  /// TaskResultSheet. If attempts are exhausted, returns false without
  /// showing anything — the caller proceeds to its normal
  /// TaskResultSheet.show(...) / onTaskComplete(false) flow exactly as
  /// it did before this mixin existed.
  ///
  /// [retryMessage] lets a screen customize the prompt copy (e.g.
  /// screen_eight's word-order phrasing) — defaults to a generic line
  /// if omitted.
  bool offerRetry({
    required BuildContext context,
    required VoidCallback onRetry,
    String? retryMessage,
  }) {
    _attemptCount++;
    if (!hasAttemptsLeft) return false;

    _showRetryPromptSheet(
      context: context,
      message: retryMessage ?? "Not quite — give it one more try!",
      onRetry: onRetry,
    );
    return true;
  }

  void _showRetryPromptSheet({
    required BuildContext context,
    required String message,
    required VoidCallback onRetry,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) => PopScope(
        // Same rationale as TaskResultSheet's own PopScope: this sheet
        // is its own route, so the system back gesture can pop it
        // directly without the button's onPressed (and therefore
        // onRetry) ever running, silently leaving the screen's local
        // state un-reset. canPop:false makes back a no-op here too.
        canPop: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            boxShadow: [
              BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -5)),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.refresh_rounded, color: Colors.orange.shade600, size: 34),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      onRetry();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Try Again',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}