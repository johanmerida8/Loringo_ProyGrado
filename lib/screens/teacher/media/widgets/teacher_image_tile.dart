import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/models/image_pending_op.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/theme/app_theme.dart';

// ── Image tile ────────────────────────────────────────────────────────────────
//
// Long-press opens the options sheet in TeacherViewImagesScreen; the tile
// only renders the staged state (marked for deletion / replacement preview).

class TeacherImageTile extends StatelessWidget {
  final Map<String, dynamic> image;
  final ImagePendingOp? pendingOp;
  final VoidCallback onLongPress;

  const TeacherImageTile({
    super.key,
    required this.image,
    required this.pendingOp,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final replacement =
        pendingOp?.kind == ImagePendingKind.replace ? pendingOp!.file : null;
    final markedForDelete = pendingOp?.kind == ImagePendingKind.delete;

    return GestureDetector(
      onLongPress: onLongPress,
      child: Stack(fit: StackFit.expand, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.md - 2),
          child: Container(
            decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border.all(
                  color: replacement != null
                      ? AppColors.primary
                      : AppColors.divider,
                  width: replacement != null ? 2 : 1,
                )),
            child: replacement != null
                ? _ReplacementPreview(file: replacement)
                : Image.network(
                    image['displayUrl'] ?? image['imageUrl'],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[300],
                        child: const Icon(Icons.broken_image,
                            color: AppColors.muted, size: 32)),
                  ),
          ),
        ),
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xs + 2),
            decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(AppRadii.md - 2),
                    bottomRight: Radius.circular(AppRadii.md - 2))),
            child: Text(
              image['name'] ?? 'teacher.teacher_image_tile.untitled'.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.onPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
        if (replacement != null)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: const BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.edit_rounded,
                  color: AppColors.onPrimary, size: 14),
            ),
          ),
        if (markedForDelete)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(AppRadii.md - 2)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.delete_rounded,
                      color: AppColors.onPrimary, size: 28),
                  const SizedBox(height: AppSpacing.xs),
                  Text('teacher.teacher_image_tile.markedForDelete'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.onPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
      ]),
    );
  }
}

class _ReplacementPreview extends StatelessWidget {
  final PlatformFile file;
  const _ReplacementPreview({required this.file});

  @override
  Widget build(BuildContext context) {
    // Image.memory can't rasterize SVG, so SVG replacements show a
    // generic icon until they're uploaded (Cloudinary renders them then).
    if (file.name.toLowerCase().endsWith('.svg') || file.bytes == null) {
      return Container(
        color: AppColors.primarySoft(0.1),
        child: const Icon(Icons.image_rounded,
            color: AppColors.primary, size: 32),
      );
    }
    return Image.memory(file.bytes!, fit: BoxFit.cover);
  }
}
