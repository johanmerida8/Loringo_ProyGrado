import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
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
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Center(
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
                        ? 'teacher.teacher_upload_idle_view.readyToUpload'.tr()
                        : 'teacher.teacher_upload_idle_view.selectImages'.tr(),
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
                          ? 'teacher.teacher_upload_idle_view.noImagesSelected'.tr()
                          : isRecommended
                              ? 'teacher.teacher_upload_idle_view.selectedReady'
                                  .tr(namedArgs: {'count': '$selectedCount'})
                              : 'teacher.teacher_upload_idle_view.selectedMoreRecommended'
                                  .tr(namedArgs: {
                                  'count': '$selectedCount',
                                  'remaining':
                                      '${minRecommended - selectedCount}',
                                }),
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
                Text(
                    'teacher.teacher_upload_idle_view.recommendedCount'
                        .tr(namedArgs: {'min': '$minRecommended'}),
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic)),
                if (!hasFiles && kIsWeb) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.mouse_rounded, size: 14, color: Colors.grey[400]),
                    const SizedBox(width: AppSpacing.xs),
                    Text('teacher.teacher_upload_idle_view.dragDropHint'.tr(),
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w500)),
                  ]),
                ],
                if (hasFiles) ...[
                  const SizedBox(height: 28),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(
                      onPressed: onPreview,
                      icon: const Icon(Icons.preview_rounded, size: 18),
                      label: Text('teacher.teacher_upload_idle_view.preview'.tr(), style: const TextStyle(fontWeight: FontWeight.w600)),
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
                      label: Text('teacher.teacher_upload_idle_view.clear'.tr(), style: const TextStyle(fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md - 3),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md))),
                    )),
                  ]),
                ] else ...[
                  const SizedBox(height: AppSpacing.md),
                  Text('teacher.teacher_upload_idle_view.onlyPngSvg'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[400])),
                ],
                const SizedBox(height: 100),
              ]),
        ),
      );
  }
}