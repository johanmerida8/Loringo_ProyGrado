// lib/screens/initials/widget/task_result_sheet.dart
//
// Shared bottom sheet for showing a correct/incorrect result after a task
// answer, used across every task screen (screen_one through screen_ten).
//
// ── v4 fix ─────────────────────────────────────────────────────────
// isDismissible:false and enableDrag:false (kept from v2/v3) only block
// gestures made directly ON the sheet — tap-outside, drag-down on the
// card. Neither blocks the Android system back-gesture/button, because a
// showModalBottomSheet is its own route pushed on top of the Navigator:
// the OS back action can pop that route directly, before it ever reaches
// a PopScope on the screen underneath. This showed up as the sheet
// visibly appearing after a wrong answer, then closing itself the moment
// the student made the system back gesture — WITHOUT the button's
// onPressed (and therefore onContinue) ever running. Every screen that
// gates its next action on onContinue (in particular slow_reveal's
// retry-in-place logic) was left permanently stuck: nothing had called
// back into the screen to unstick its "waiting for an answer" state.
//
// Fix: wrap the sheet's own content in a PopScope with canPop: false,
// scoped to the sheet's own route. This intercepts the back gesture at
// the level where it actually first lands — the sheet's route itself —
// so it's a no-op that leaves the student looking at the same sheet,
// same as tapping outside or dragging down already did. The button
// remains the only way through.
//
// ── v3 fix (kept) ─────────────────────────────────────────────────────
// Every task screen now advances on both correct AND wrong answers —
// ActivityPlayScreen owns the retry logic via a review round at the end
// of the activity, not the individual screens anymore. The old default
// button label of "Try Again" for a wrong answer was left over from when
// screens retried in place; since a wrong answer now moves forward just
// like a correct one, both cases read "Continue" unless a screen
// explicitly overrides buttonLabel for its own reason (e.g. "Finish" on
// the last question of a multi-part task).
//
// Also added: isPracticeRound. When ActivityPlayScreen is replaying a
// previously-wrong task during its end-of-activity review round, a wrong
// answer there needs to read differently than a wrong answer during the
// main pass — the student should understand this attempt doesn't count
// against their score, it's there so they can get it right before
// finishing. Rather than stack a second popup on top of this sheet
// (extra tap, more jarring), the practice-round context is folded into
// this same sheet as a small note.
//
// A full-screen parrot intro (PracticeRoundIntroScreen) is shown once by
// ActivityPlayScreen right before the first task of the review round
// begins — this sheet itself carries no mascot/parrot content, that logic
// lives entirely in that separate screen instead.
//
// ── v2 fix (kept) ─────────────────────────────────────────────────────
// v1 wrapped the content in a DraggableScrollableSheet with a fixed
// initialChildSize. v2 sizes the sheet to its actual content instead.

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class TaskResultSheet extends StatelessWidget {
  /// Whether the answer was correct. Drives the animation, color, and
  /// default button label.
  final bool isCorrect;

  /// Called when the primary button is tapped, AFTER the sheet has
  /// already been popped. Every task screen now calls
  /// widget.onTaskComplete(isCorrect) here regardless of correctness —
  /// ActivityPlayScreen decides whether that means "next task" or
  /// "queue for review round."
  final VoidCallback onContinue;

  /// Overrides the button label. If null, defaults to "Continue" for
  /// both correct and incorrect answers — see v3 note above. Screens
  /// with their own multi-step flow (e.g. "Finish" on a last question)
  /// can still override this explicitly.
  final String? buttonLabel;

  /// Optional message shown above the button (below the animation). Used
  /// by screens like screen_nine/screen_ten for
  /// "¡Excellent!"/"Almost there!"/mic-capture-error text.
  final String? message;

  /// Optional color override for the message text. Falls back to a
  /// green/orange pair based on [isCorrect] if not provided.
  final Color? messageColor;

  /// Optional secondary content shown between the message and the
  /// button — e.g. a hint box (screen_eight) or "You said: ..." text
  /// (screen_nine, screen_ten).
  final Widget? extraContent;

  /// True when this task is being shown as part of ActivityPlayScreen's
  /// end-of-activity review round (a previously-wrong task being
  /// replayed), rather than the normal first-attempt pass. Only changes
  /// the sheet's messaging on a wrong answer — correct answers, and the
  /// main pass, are unaffected.
  final bool isPracticeRound;

  const TaskResultSheet({
    super.key,
    required this.isCorrect,
    required this.onContinue,
    this.buttonLabel,
    this.message,
    this.messageColor,
    this.extraContent,
    this.isPracticeRound = false,
  });

  static const Color _green = Color(0xFF4CAF50);

  /// Shows the sheet. This is the single entry point every screen should
  /// call instead of building `showModalBottomSheet` inline.
  ///
  /// Locked down against every way out except the button: not
  /// dismissible by tap-out, no drag-to-dismiss, and (see PopScope in
  /// build() below) no system back-gesture/button either.
  static Future<void> show(
    BuildContext context, {
    required bool isCorrect,
    required VoidCallback onContinue,
    String? buttonLabel,
    String? message,
    Color? messageColor,
    Widget? extraContent,
    double? minHeight,
    bool isPracticeRound = false,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => TaskResultSheet(
        isCorrect: isCorrect,
        onContinue: onContinue,
        buttonLabel: buttonLabel,
        message: message,
        messageColor: messageColor,
        extraContent: extraContent,
        isPracticeRound: isPracticeRound,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showPracticeNote = isPracticeRound && !isCorrect;

    // PopScope here, not just on the calling screen: this sheet is its
    // own route (pushed by showModalBottomSheet), so the system
    // back-gesture can pop THIS route directly without ever reaching a
    // PopScope on the screen underneath. canPop: false makes the back
    // gesture a no-op while this sheet is showing — same effect as
    // isDismissible:false/enableDrag:false above, just covering the
    // gesture those two don't.
    return PopScope(
      canPop: false,
      child: Container(
      width: double.infinity,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -5)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Drag handle — purely visual now since drag is disabled,
              // kept because it reads as "this is a sheet" to the student.
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              Lottie.asset(
                isCorrect
                    ? 'assets/animation/correct.json'
                    : 'assets/animation/fail.json',
                height: 120,
                repeat: true,
              ),

              if (message != null) ...[
                const SizedBox(height: 12),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: messageColor ??
                        (isCorrect ? const Color(0xFF2E7D32) : const Color(0xFFE65100)),
                    height: 1.4,
                  ),
                ),
              ],

              // Practice-round note — only on a wrong answer during the
              // review round. Explains this attempt doesn't affect the
              // score, framed as an encouragement to nail it before
              // finishing rather than as a penalty.
              if (showPracticeNote) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.replay_rounded, color: Colors.orange.shade600, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "This is a practice round — it won't count against your score. Take another look and try again!",
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (extraContent != null) ...[
                const SizedBox(height: 12),
                extraContent!,
              ],

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    onContinue();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isCorrect ? _green : Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: isCorrect ? 5 : 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    // Both correct and wrong now read "Continue" by
                    // default — see v3 note at the top of this file.
                    buttonLabel ?? 'Continue',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
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

/// Small reusable "hint box" content for the incorrect state, matching
/// screen_eight's amber lightbulb hint card. Pass as `extraContent` to
/// TaskResultSheet.show when you have an encouragement hint but don't
/// want to reveal the answer.
class TaskResultHintBox extends StatelessWidget {
  final String hint;
  const TaskResultHintBox({super.key, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline, color: Colors.orange.shade600, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hint,
              style: TextStyle(
                fontSize: 14,
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small reusable "you said: ..." content, matching screen_nine and
/// screen_ten's recognized-speech display. Pass as `extraContent`.
class TaskResultSpokenTextBox extends StatelessWidget {
  final String spokenText;
  /// screen_nine shows it as a bare italic line; screen_ten wraps it in a
  /// "You said:" labeled card. Toggle to match.
  final bool showLabel;

  const TaskResultSpokenTextBox({
    super.key,
    required this.spokenText,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!showLabel) {
      return Text(
        '"$spokenText"',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey.shade500,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'You said:',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            '"$spokenText"',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}