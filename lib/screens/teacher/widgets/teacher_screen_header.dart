import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';

// ── TeacherScreenHeader ────────────────────────────────────────────────────
// Replaces Scaffold.appBar across the teacher content hierarchy screens
// (Content → Unit → Lesson → Activity → Task).
//
// Design decision: this is intentionally NOT a colored bar — the first
// version of this widget used a Container with a gradient BoxDecoration,
// which visually reproduced the exact same solid-color AppBar look this
// change was meant to remove. That was wrong. The actual reference is
// teacher_home_screen.dart's inline header:
//
//   GestureDetector(onTap: () => Scaffold.of(ctx).openDrawer(),
//     child: Container(padding: ..., decoration: BoxDecoration(
//       color: AppColors.primarySoft(0.1), borderRadius: ...),
//       child: Icon(Icons.menu_rounded, color: AppColors.primary))),
//   const Text('My Groups', style: AppText.h1),
//
// i.e. no background fill behind the row at all — it sits directly on
// AppColors.scaffoldBackground. Only the back icon gets a small soft-tint
// box (AppColors.primarySoft), matching the drawer-menu icon treatment.
// This widget mirrors that exactly, just swapping the drawer-menu icon for
// a back arrow and adding an optional subtitle line.
//
// Not a PreferredSizeWidget on purpose: it's meant to sit as the first
// child inside Scaffold.body (typically wrapped in a Column), not inside
// Scaffold.appBar.
class TeacherScreenHeader extends StatelessWidget {
  const TeacherScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.color = AppColors.primary,
    this.onBack,
  });

  /// Main heading, e.g. the unit/lesson/activity title.
  final String title;

  /// Optional small caption under the title, e.g. "Lessons", "Activities".
  final String? subtitle;

  /// Tint used for the back-icon box and the title text — pass the
  /// group/content accent color so this stays visually tied to whichever
  /// branch of content it's in, same role AppColors.primary plays for the
  /// menu icon + "My Groups" title on the home screen.
  final Color color;

  /// Defaults to Navigator.pop when not supplied.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    // SafeArea(bottom: false): this header replaces Scaffold.appBar, which
    // handles the status-bar/notch inset automatically. A plain Padding
    // does not, so without this the title clips under the status bar —
    // exactly what happened before this was added.
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: onBack ?? () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft(0.1),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Icon(Icons.arrow_back_rounded, color: color, size: 22),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppText.h1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: AppText.caption),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}