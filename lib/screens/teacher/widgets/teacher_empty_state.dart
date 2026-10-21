import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/theme/app_theme.dart';

// ── Empty state (no categories) ─────────────────────────────────────────────

class TeacherEmptyState extends StatelessWidget {
  final VoidCallback onTap;
  const TeacherEmptyState({super.key, required this.onTap});

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
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                    gradient: AppDecorations.primaryGradient,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.primarySoft(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8))
                    ],
                  ),
                  child: const Icon(Icons.photo_library_rounded,
                      size: 52, color: AppColors.onPrimary),
                ),
                const SizedBox(height: 28),
                Text('teacher.teacher_empty_state.noCategoriesTitle'.tr(),
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                const SizedBox(height: AppSpacing.sm + 2),
                Text(
                    'teacher.teacher_empty_state.noCategoriesSubtitle'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[500],
                        height: 1.5)),
                const SizedBox(height: AppSpacing.xl),
                ElevatedButton.icon(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: AppSpacing.md - 2),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadii.md)),
                      elevation: 3),
                  icon: const Icon(Icons.create_new_folder_rounded),
                  label: Text('teacher.teacher_empty_state.createFirstCategory'.tr(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ]),
        ),
      );
  }
}

// ── Empty gallery state (no images in category) ─────────────────────────────

class TeacherEmptyGalleryState extends StatelessWidget {
  final VoidCallback onAdd;
  const TeacherEmptyGalleryState({super.key, required this.onAdd});

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
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    gradient: AppDecorations.primaryGradient,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.primarySoft(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8))
                    ],
                  ),
                  child: const Icon(
                      Icons.image_not_supported_outlined,
                      size: 48,
                      color: AppColors.onPrimary),
                ),
                const SizedBox(height: 28),
                Text('teacher.teacher_empty_state.noImagesTitle'.tr(),
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                const SizedBox(height: AppSpacing.sm + 2),
                Text('teacher.teacher_empty_state.noImagesSubtitle'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[500],
                        height: 1.5)),
                const SizedBox(height: AppSpacing.xl),
                ElevatedButton.icon(
                  onPressed: onAdd,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: AppSpacing.md - 2),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadii.md)),
                      elevation: 3),
                  icon: const Icon(
                      Icons.add_photo_alternate_rounded),
                  label: Text('teacher.teacher_empty_state.uploadImages'.tr(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                ),
              ]),
        ),
      );
  }
}