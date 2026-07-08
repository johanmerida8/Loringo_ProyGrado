import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';

// ── Idle view ─────────────────────────────────────────────────────────────────

class TeacherIdleView extends StatelessWidget {
  final int selectedCount, minRecommended;
  final bool isRecommended, hasFiles;
  final VoidCallback onPreview, onClear;

  const TeacherIdleView({
    super.key,
    required this.selectedCount,
    required this.minRecommended,
    required this.isRecommended,
    required this.hasFiles,
    required this.onPreview,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    gradient: hasFiles
                        ? LinearGradient(
                            colors: [
                              Colors.orange.shade400,
                              Colors.orange.shade700
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight)
                        : AppDecorations.primaryGradient,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                          color: (hasFiles
                                  ? Colors.orange
                                  : AppColors.primary)
                              .withOpacity(0.4),
                          blurRadius: 18,
                          offset: const Offset(0, 6))
                    ],
                  ),
                  child: Icon(
                      hasFiles
                          ? Icons.photo_library_rounded
                          : Icons.add_photo_alternate_outlined,
                      size: 46,
                      color: AppColors.onPrimary),
                ),
                const SizedBox(height: 24),
                Text(
                    hasFiles
                        ? 'Ready to Upload'
                        : 'Select PNG or SVG images',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                    textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.sm),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                      color: (isRecommended
                              ? AppColors.primary
                              : Colors.orange)
                          .withOpacity(0.1),
                      borderRadius:
                          BorderRadius.circular(AppRadii.pill),
                      border: Border.all(
                          color: (isRecommended
                                  ? AppColors.primary
                                  : Colors.orange)
                              .withOpacity(0.3))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        isRecommended
                            ? Icons.check_circle
                            : Icons.info_outline,
                        size: 16,
                        color: isRecommended
                            ? AppColors.primary
                            : Colors.orange),
                    const SizedBox(width: AppSpacing.xs + 2),
                    Text(
                      selectedCount == 0
                          ? 'No images selected'
                          : isRecommended
                              ? '$selectedCount selected · Ready!'
                              : '$selectedCount selected · ${minRecommended - selectedCount} more recommended',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isRecommended
                              ? AppColors.primary
                              : Colors.orange),
                    ),
                  ]),
                ),
                const SizedBox(height: AppSpacing.xs + 2),
                Text('Recommended: $minRecommended+ images per category',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic)),
                if (hasFiles) ...[
                  const SizedBox(height: 28),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: onPreview,
                      icon: const Icon(Icons.preview_rounded, size: 18),
                      label: const Text('Preview', style: TextStyle(fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          side: const BorderSide(color: Colors.orange, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md - 3),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md))),
                    )),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: OutlinedButton.icon(
                      onPressed: onClear,
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      label: const Text('Clear', style: TextStyle(fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md - 3),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md))),
                    )),
                  ]),
                ] else ...[
                  const SizedBox(height: AppSpacing.md),
                  Text('Only PNG and SVG files are accepted',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[400])),
                ],
                const SizedBox(height: 100),
              ]),
        ),
      );
}