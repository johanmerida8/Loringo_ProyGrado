// lib/screens/initials/widget/task_exit_guard.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/initials/widget/exit_task_dialog.dart';

/// Wraps a task screen's [Scaffold] so the only way to leave it is the
/// explicit X button (which each screen already wires to
/// [confirmExitTask] via its own `_handleClose`). Blocks the Android
/// system back-gesture/button from popping the route directly — same
/// rationale as the PopScope already used standalone in
/// ScreenThirteen, just factored out so the other 10 task screens don't
/// each need to hand-roll the same block.
///
/// Usage — wrap only the outermost Scaffold returned from build():
/// ```dart
/// return TaskExitGuard(
///   onRequestExit: _handleClose, // reuses the screen's existing method
///   child: Scaffold(...),
/// );
/// ```
///
/// For screens that need conditional pop behavior (e.g. ScreenThirteen,
/// which allows the back-gesture once an attempt is resolved), use
/// [canPop] to override the default `false`. Leave it at the default
/// for every other screen.
class TaskExitGuard extends StatelessWidget {
  /// Called when the student attempts to leave via the system back
  /// gesture/button. Screens pass their existing `_handleClose` method,
  /// which already shows [confirmExitTask] and pops on confirmation —
  /// so behavior is identical whether the student taps the X or
  /// swipes back.
  final Future<void> Function() onRequestExit;

  /// Whether the system back gesture is allowed to pop this route
  /// directly, bypassing [onRequestExit]. Defaults to false (always
  /// intercept). Only ScreenThirteen needs this to vary — pass
  /// `_resolved` there.
  final bool canPop;

  final Widget child;

  const TaskExitGuard({
    super.key,
    required this.onRequestExit,
    required this.child,
    this.canPop = false,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await onRequestExit();
      },
      child: child,
    );
  }
}