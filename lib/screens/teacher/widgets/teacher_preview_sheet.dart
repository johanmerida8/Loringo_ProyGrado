import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';

// ── Preview sheet ─────────────────────────────────────────────────────────────

class TeacherPreviewSheet extends StatelessWidget {
  final List<Map<String, dynamic>> selectedFiles;
  final void Function(int) onRemove;
  final VoidCallback onClearAll, onUpload, onSelectMore;

  const TeacherPreviewSheet({
    super.key,
    required this.selectedFiles,
    required this.onRemove,
    required this.onClearAll,
    required this.onUpload,
    required this.onSelectMore,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize:     0.95,
      minChildSize:     0.5,
      builder: (ctx, controller) => Container(
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppRadii.lg + 4))),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
            child: Column(children: [
              Center(
                  child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: AppSpacing.md),
              Row(children: [
                Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                        color: AppColors.primarySoft(0.1),
                        borderRadius:
                            BorderRadius.circular(AppRadii.sm)),
                    child: const Icon(Icons.photo_library_rounded,
                        color: AppColors.primary, size: 20)),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'Preview — ${selectedFiles.length} '
                          'image${selectedFiles.length != 1 ? "s" : ""}',
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      const Text('Tap × to remove',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.muted)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: AppSpacing.sm),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSelectMore,
                    icon: const Icon(Icons.add_photo_alternate_outlined,
                        size: 16, color: AppColors.primary),
                    label: const Text('Select More',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.xs + 2),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadii.sm))),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onClearAll,
                    icon: Icon(Icons.delete_sweep,
                        size: 16, color: AppColors.danger),
                    label: Text('Clear all',
                        style: TextStyle(
                            color: AppColors.danger,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.danger),
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.xs + 2),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadii.sm))),
                  ),
                ),
              ]),
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
            ]),
          ),
          Expanded(
            child: GridView.builder(
              controller: controller,
              padding: const EdgeInsets.all(AppSpacing.md),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10),
              itemCount: selectedFiles.length,
              itemBuilder: (_, index) {
                final file  = selectedFiles[index]['file'];
                final isSvg = selectedFiles[index]['isSvg'] as bool;
                final name  = selectedFiles[index]['name'] as String;
                return Stack(fit: StackFit.expand, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: Container(
                      decoration: BoxDecoration(
                          color: Colors.grey[100],
                          border: Border.all(
                              color: AppColors.divider)),
                      child: isSvg
                          ? Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                Icon(
                                    Icons
                                        .image_aspect_ratio_rounded,
                                    color: Colors.blue[300],
                                    size: 32),
                                const Text('SVG',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue)),
                              ])
                          : Image.memory(file.bytes!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.broken_image,
                                      color: AppColors.muted)),
                    ),
                  ),
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs + 2,
                          vertical: AppSpacing.xs),
                      decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(
                                  AppRadii.md - 1))),
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.onPrimary,
                              fontSize: 9,
                              fontWeight: FontWeight.w500)),
                    ),
                  ),
                  Positioned(
                    top: AppSpacing.xs, right: AppSpacing.xs,
                    child: GestureDetector(
                      onTap: () => onRemove(index),
                      child: Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                              color: AppColors.danger,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                    color: AppColors.danger
                                        .withOpacity(0.4),
                                    blurRadius: 4)
                              ]),
                          child: const Icon(Icons.close,
                              color: AppColors.onPrimary,
                              size: 13)),
                    ),
                  ),
                ]);
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                MediaQuery.of(context).padding.bottom +
                    AppSpacing.md),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onUpload,
                icon: const Icon(Icons.cloud_upload_rounded,
                    color: AppColors.onPrimary, size: 20),
                label: Text(
                    'Upload ${selectedFiles.length} '
                    'Image${selectedFiles.length != 1 ? "s" : ""}',
                    style: const TextStyle(
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadii.md)),
                    elevation: 3),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}