// admin_upload_image_screen.dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/image_service.dart';

class AdminUploadImageScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const AdminUploadImageScreen(
      {super.key, required this.categoryId, required this.categoryName});

  @override
  State<AdminUploadImageScreen> createState() =>
      _AdminUploadImageScreenState();
}

class _AdminUploadImageScreenState extends State<AdminUploadImageScreen> {
  final _imageService   = ImageService();
  final _db             = Database();
  static const int _minRec = 15;

  List<Map<String, dynamic>> _selectedFiles = [];
  bool _isUploading    = false;
  int  _uploadedCount  = 0;
  int  _totalCount     = 0;

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _selectImages() async {
    try {
      final picked = await _imageService.pickMultipleImages();
      if (picked == null || picked.isEmpty) return;
      setState(() {
        _selectedFiles = picked
            .map((f) => {
                  'file':  f,
                  'name':  f.name.replaceAll(RegExp(r'\.[^.]*$'), ''),
                  'isSvg': f.name.toLowerCase().endsWith('.svg'),
                })
            .toList();
      });
      if (mounted) _showPreviewSheet();
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(context, 'Error: $e');
      }
    }
  }

  // Agrega más imágenes a la selección existente (no la reemplaza).
  // Evita duplicados comparando por nombre de archivo original.
  Future<void> _selectMoreImages() async {
    try {
      final picked = await _imageService.pickMultipleImages();
      if (picked == null || picked.isEmpty) return;

      final existingNames = _selectedFiles
          .map((entry) => (entry['file'] as PlatformFile).name)
          .toSet();

      final newEntries = picked
          .where((f) => !existingNames.contains(f.name))
          .map((f) => {
                'file':  f,
                'name':  f.name.replaceAll(RegExp(r'\.[^.]*$'), ''),
                'isSvg': f.name.toLowerCase().endsWith('.svg'),
              })
          .toList();

      setState(() {
        _selectedFiles = [..._selectedFiles, ...newEntries];
      });

      if (mounted) {
        Navigator.pop(context);
        _showPreviewSheet();
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(context, 'Error: $e');
      }
    }
  }

  void _showPreviewSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PreviewSheet(
        selectedFiles: _selectedFiles,
        onSelectMore: _selectMoreImages,
        onRemove: (i) {
          setState(() => _selectedFiles.removeAt(i));
          Navigator.pop(context);
          if (_selectedFiles.isNotEmpty) _showPreviewSheet();
        },
        onClearAll: () {
          setState(() => _selectedFiles = []);
          Navigator.pop(context);
        },
        onUpload: () {
          Navigator.pop(context);
          _confirmAndUpload();
        },
      ),
    );
  }

  void _confirmAndUpload() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: const Row(children: [
          Icon(Icons.cloud_upload_rounded,
              color: AppColors.primary, size: 24),
          SizedBox(width: AppSpacing.sm + 2),
          Text('Confirm Upload',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 17)),
        ]),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                  text: TextSpan(
                      style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                          height: 1.5),
                      children: [
                    TextSpan(
                        text:
                            '${_selectedFiles.length} image${_selectedFiles.length != 1 ? "s" : ""}'),
                    const TextSpan(
                        text:
                            ' will be scanned before uploading.'),
                  ])),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm + 2),
                decoration: BoxDecoration(
                    color: AppColors.primarySoft(0.06),
                    borderRadius:
                        BorderRadius.circular(AppRadii.sm),
                    border: Border.all(
                        color: AppColors.primarySoft(0.2))),
                child: Row(children: [
                  const Icon(Icons.folder_rounded,
                      color: AppColors.primary, size: 16),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                      child: Text('To: ${widget.categoryName}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary))),
                ]),
              ),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.muted))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _uploadImages();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppRadii.sm)),
                elevation: 0),
            child: const Text('Upload Now',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadImages() async {
    if (_selectedFiles.isEmpty) return;
    setState(() {
      _isUploading   = true;
      _uploadedCount = 0;
      _totalCount    = _selectedFiles.length;
    });

    int success = 0;
    int rejectedContent = 0;
    int failedTechnical  = 0;

    for (final entry in _selectedFiles) {
      final file      = entry['file'];
      final imageName = entry['name'] as String;
      final ext       = file.name.split('.').last;
      try {
        final result = await _imageService.uploadToCloudinary(
            file, categoryName: widget.categoryName);
        if (result['success'] != true) {
          if (result['reason'] == 'REJECT_INAPPROPRIATE_IMAGE') {
            rejectedContent++;
          } else {
            failedTechnical++;
          }
        } else {
          await _db.saveImageMetadata(
            categoryId:         widget.categoryId,
            name:               imageName,
            imageUrl:           result['secure_url'] as String,
            cloudinaryPublicId: result['public_id'] as String,
            fileExtension:      ext,
          );
          success++;
        }
      } catch (_) {
        failedTechnical++;
      }
      if (mounted) setState(() => _uploadedCount++);
    }

    setState(() {
      _isUploading   = false;
      _selectedFiles = [];
    });
    if (!mounted) return;

    // El snackbar se muestra en la pantalla anterior (mismo patrón que teacher).
    Navigator.pop(context, {
      'success': success,
      'rejectedContent': rejectedContent,
      'failedTechnical': failedTechnical,
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasFiles      = _selectedFiles.isNotEmpty;
    final isRecommended = _selectedFiles.length >= _minRec;
    final progress =
        _totalCount > 0 ? _uploadedCount / _totalCount : 0.0;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.categoryName,
                  style: const TextStyle(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              const Text('Upload Images',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 11)),
            ]),
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme:
            const IconThemeData(color: AppColors.onPrimary),
      ),
      body: _isUploading
          ? _UploadingView(
              progress: progress,
              uploaded: _uploadedCount,
              total: _totalCount)
          : _IdleView(
              selectedCount: _selectedFiles.length,
              minRecommended: _minRec,
              isRecommended: isRecommended,
              hasFiles: hasFiles,
              onPreview: _showPreviewSheet,
              onClear: () =>
                  setState(() => _selectedFiles = []),
            ),
      // ✅ Un solo FAB con heroTag null — mismo patrón que teacher, evita
      // colisión de Hero cuando coexisten dos FABs condicionales.
      floatingActionButton: _isUploading
          ? null
          : FloatingActionButton.extended(
              heroTag: null,
              onPressed: hasFiles ? _confirmAndUpload : _selectImages,
              backgroundColor: hasFiles
                  ? (isRecommended ? const Color(0xFF2196F3) : Colors.orange)
                  : AppColors.primary,
              elevation: 3,
              icon: Icon(
                hasFiles ? Icons.cloud_upload_rounded : Icons.add_photo_alternate_rounded,
                color: AppColors.onPrimary,
              ),
              label: Text(
                hasFiles
                    ? 'Upload ${_selectedFiles.length}${isRecommended ? " ✅" : ""}'
                    : 'Select Images',
                style: const TextStyle(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
    );
  }
}

// ── Idle view ─────────────────────────────────────────────────────────────────

class _IdleView extends StatelessWidget {
  final int selectedCount, minRecommended;
  final bool isRecommended, hasFiles;
  final VoidCallback onPreview, onClear;

  const _IdleView({
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
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                Text(
                    'Recommended: $minRecommended+ images per category',
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
                      label: const Text('Preview',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          side: const BorderSide(
                              color: Colors.orange, width: 1.5),
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.md - 3),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppRadii.md))),
                    )),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: OutlinedButton.icon(
                      onPressed: onClear,
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      label: const Text('Clear',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(
                              color: AppColors.danger, width: 1.5),
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.md - 3),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppRadii.md))),
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

// ── Uploading view ────────────────────────────────────────────────────────────

class _UploadingView extends StatelessWidget {
  final double progress;
  final int uploaded, total;

  const _UploadingView(
      {required this.progress,
      required this.uploaded,
      required this.total});

  @override
  Widget build(BuildContext context) => Center(
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
                const Text('Uploading Images…',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: AppSpacing.xs + 2),
                Text('$uploaded of $total processed',
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
                Text('Scanning each image for content safety…',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[400])),
              ]),
        ),
      );
}

// ── Preview sheet ─────────────────────────────────────────────────────────────

class _PreviewSheet extends StatelessWidget {
  final List<Map<String, dynamic>> selectedFiles;
  final void Function(int) onRemove;
  final VoidCallback onClearAll, onUpload, onSelectMore;

  const _PreviewSheet({
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
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (ctx, ctrl) => Container(
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppRadii.lg + 4))),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                AppSpacing.md, AppSpacing.lg, 0),
            child: Column(children: [
              Center(
                  child: Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius:
                              BorderRadius.circular(2)))),
              const SizedBox(height: AppSpacing.md),
              Row(children: [
                Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                        color: AppColors.primarySoft(0.1),
                        borderRadius:
                            BorderRadius.circular(AppRadii.sm)),
                    child: const Icon(
                        Icons.photo_library_rounded,
                        color: AppColors.primary,
                        size: 20)),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'Preview — ${selectedFiles.length} image${selectedFiles.length != 1 ? "s" : ""}',
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                      const Text('Tap × to remove',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.muted)),
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
              controller: ctrl,
              padding: const EdgeInsets.all(AppSpacing.md),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10),
              itemCount: selectedFiles.length,
              itemBuilder: (_, i) {
                final file  = selectedFiles[i]['file'];
                final isSvg = selectedFiles[i]['isSvg'] as bool;
                final name  = selectedFiles[i]['name'] as String;
                return Stack(fit: StackFit.expand, children: [
                  ClipRRect(
                    borderRadius:
                        BorderRadius.circular(AppRadii.md),
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
                                        fontWeight:
                                            FontWeight.bold,
                                        color: Colors.blue)),
                              ])
                          : Image.memory(file.bytes!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(
                                      Icons.broken_image,
                                      color:
                                          AppColors.muted)),
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
                      onTap: () => onRemove(i),
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
                    'Upload ${selectedFiles.length} Image${selectedFiles.length != 1 ? "s" : ""}',
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