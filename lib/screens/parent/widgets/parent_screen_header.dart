import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// Replaces Scaffold.appBar across the parent screens pushed from My
/// Children (Activities, Learning Path, Join Group) -- mirrors
/// TeacherScreenHeader's design (see that file's header comment for the
/// full rationale): no solid-color bar, just a soft-tint circular back
/// button + large title sitting directly on AppColors.scaffoldBackground.
/// This also replaces the near-identical inline _buildHeader() that used
/// to be copy-pasted separately into each of those screens.
///
/// Not a PreferredSizeWidget on purpose: it's meant to sit as the first
/// child inside Scaffold.body, not inside Scaffold.appBar.
class ParentScreenHeader extends StatelessWidget {
  const ParentScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onBack,
  });

  /// Main heading, e.g. "Join Group", "Luca's Path".
  final String title;

  /// Optional small caption under the title.
  final String? subtitle;

  /// Optional widget shown between the back button and the title -- e.g.
  /// a child's avatar, so the header reads as "this screen is about
  /// them" at a glance.
  final Widget? leading;

  /// Optional widget shown at the end of the header row.
  final Widget? trailing;

  /// Defaults to Navigator.pop when not supplied.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    // SafeArea(bottom: false): this header replaces Scaffold.appBar, which
    // handles the status-bar/notch inset automatically. A plain Padding
    // does not, so without this the title clips under the status bar.
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
                  borderRadius: AppRadii.mdAll,
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.sm),
            ],
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
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
