import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';

// ── AdminScreenHeader ────────────────────────────────────────────────────
// Mirrors TeacherScreenHeader (lib/screens/teacher/widgets/teacher_screen_header.dart)
// for the admin side — same no-AppBar pattern as admin_dashboard_screen.dart:
// no solid-color bar, just a back-icon box + title sitting directly on
// AppColors.scaffoldBackground.
//
// Not a PreferredSizeWidget on purpose: it's meant to sit as the first
// child inside Scaffold.body (typically wrapped in a Column), not inside
// Scaffold.appBar.
class AdminScreenHeader extends StatelessWidget {
  const AdminScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.color = AppColors.primary,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final Color color;

  /// Defaults to Navigator.pop when not supplied.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
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
