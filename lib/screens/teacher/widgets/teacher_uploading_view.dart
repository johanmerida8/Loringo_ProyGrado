import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/theme/app_theme.dart';

// ── Uploading view ────────────────────────────────────────────────────────────

class TeacherUploadingView extends StatelessWidget {
  final double progress;
  final int uploaded, total;

  const TeacherUploadingView(
      {super.key,
      required this.progress,
      required this.uploaded,
      required this.total});

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    gradient: AppDecorations.primaryGradient,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.primarySoft(0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 6))
                    ],
                  ),
                  child: const Icon(Icons.cloud_upload_rounded,
                      size: 44, color: AppColors.onPrimary),
                ),
                const SizedBox(height: 28),
                Text('teacher.teacher_uploading_view.uploadingImages'.tr(),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: AppSpacing.xs + 2),
                Text(
                    'teacher.teacher_uploading_view.processedCount'.tr(
                        namedArgs: {
                          'uploaded': '$uploaded',
                          'total': '$total',
                        }),
                    style: TextStyle(
                        fontSize: 14, color: Colors.grey[600])),
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(AppRadii.sm),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: AppColors.divider,
                    valueColor: const AlwaysStoppedAnimation(
                        AppColors.primary),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('${(progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
                const SizedBox(height: 20),
                Text('teacher.teacher_uploading_view.scanningImages'.tr(),
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[400])),
              ]),
        ),
      );
  }
}