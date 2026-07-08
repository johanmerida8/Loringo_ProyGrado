// lib/screens/initials/widget/task_result_sheet.dart
//
// Shared bottom sheet for showing a correct/incorrect result after a task
// answer, used across every task screen (screen_one through screen_ten).
//
// ── v2 fix ─────────────────────────────────────────────────────────────
// v1 wrapped the content in a DraggableScrollableSheet with a fixed
// initialChildSize (e.g. 0.4 = 40% of the FULL screen height), regardless
// of how much actual content there was. For the common case — just the
// Lottie animation and a button, no message/extraContent — that forced
// the sheet to stretch to 40% of the screen with a lot of empty space
// below the button, which is exactly the "too tall, content floating at
// the top" look in the screenshot.
//
// v2 drops DraggableScrollableSheet in favor of a plain Container sized
// by its content (MainAxisSize.min), wrapped in SafeArea so it still
// respects the bottom notch/gesture bar. The sheet is now exactly as
// tall as its content — small for the plain correct/incorrect case,
// taller when a message or extraContent (hint box, spoken text) is
// present. All text is explicitly centered.

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class TaskResultSheet extends StatelessWidget {
  /// Whether the answer was correct. Drives the animation, color, and
  /// default button label.
  final bool isCorrect;

  /// Called when the primary button is tapped, AFTER the sheet has
  /// already been popped. Use this to advance to the next task (correct)
  /// or reset the task state for a retry (incorrect).
  final VoidCallback onContinue;

  /// Overrides the button label. If null, defaults to
  /// "Continue"/"Try Again" based on [isCorrect].
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

  const TaskResultSheet({
    super.key,
    required this.isCorrect,
    required this.onContinue,
    this.buttonLabel,
    this.message,
    this.messageColor,
    this.extraContent,
  });

  static const Color _green = Color(0xFF4CAF50);

  /// Shows the sheet. This is the single entry point every screen should
  /// call instead of building `showModalBottomSheet` inline.
  ///
  /// Locked down the same way every screen already had it: not
  /// dismissible by swipe or tap-out, must use the button — a wrong
  /// answer (or a correct one) needs an explicit decision, not an
  /// accidental dismiss.
  ///
  /// Note: `initialChildSize`/`maxChildSize` params from v1 are gone —
  /// the sheet now sizes itself to content instead of a fixed screen
  /// fraction. If a specific screen ever needs a minimum height (e.g. to
  /// avoid layout jump when extraContent loads asynchronously), pass
  /// [minHeight].
  static Future<void> show(
    BuildContext context, {
    required bool isCorrect,
    required VoidCallback onContinue,
    String? buttonLabel,
    String? message,
    Color? messageColor,
    Widget? extraContent,
    double? minHeight,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
                    buttonLabel ?? (isCorrect ? 'Continue' : 'Try Again'),
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