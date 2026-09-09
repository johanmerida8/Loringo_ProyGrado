import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/image_service.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_preview_sheet.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_upload_idle_view.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_uploading_view.dart';

// ── TeacherUploadImageScreen ──────────────────────────────────────────────────

class TeacherUploadImageScreen extends StatefulWidget {
  final String ownerId;
  final String categoryId;
  // Folder-safe form — used as the Cloudinary folder, never shown to the
  // user. See Database.createCategory.
  final String categoryName;
  // What the user actually typed — shown in the UI.
  final String categoryDisplayName;

  const TeacherUploadImageScreen({
    super.key,
    required this.ownerId,
    required this.categoryId,
    required this.categoryName,
    required this.categoryDisplayName,
  });

  @override
  State<TeacherUploadImageScreen> createState() =>
      _TeacherUploadImageScreenState();
}

class _TeacherUploadImageScreenState extends State<TeacherUploadImageScreen> {
  final ImageService _imageService = ImageService();
  final Database _db = Database();
  static const int _minRec = 15;
  // Matches ImageService.pickMultipleImages()'s own allowedExtensions --
  // desktop_drop bypasses file_picker's type filter, so it has to be
  // re-checked here.
  static const Set<String> _allowedExtensions = {'png', 'svg', 'webp'};

  List<Map<String, dynamic>> _selectedFiles = [];
  bool _isUploading = false;
  int _uploadedCount = 0;
  int _totalCount = 0;
  bool _isDragging = false;

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
            .map(
              (f) => {
                'file': f,
                'name': f.name.replaceAll(RegExp(r'\.[^.]*$'), ''),
                'isSvg': f.name.toLowerCase().endsWith('.svg'),
              },
            )
            .toList();
      });
      if (mounted) _showPreviewSheet();
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(
            context, 'common.errorWithMessage'.tr(namedArgs: {'error': '$e'}));
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
          .map(
            (f) => {
              'file': f,
              'name': f.name.replaceAll(RegExp(r'\.[^.]*$'), ''),
              'isSvg': f.name.toLowerCase().endsWith('.svg'),
            },
          )
          .toList();

      setState(() {
        _selectedFiles = [..._selectedFiles, ...newEntries];
      });

      // Cierra y reabre el sheet para reflejar la lista actualizada.
      if (mounted) {
        Navigator.pop(context);
        _showPreviewSheet();
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(
            context, 'common.errorWithMessage'.tr(namedArgs: {'error': '$e'}));
      }
    }
  }

  // ── Drag & drop (web/desktop) ─────────────────────────────────────────
  // Bypasses the file_picker's own type filter, so extension checking
  // happens here instead. Same dedup-by-name as _selectMoreImages, since
  // dropping is just another way to add to the existing selection rather
  // than replacing it. Mirrors admin_upload_image_screen.dart's
  // _handleDroppedFiles.
  Future<void> _handleDroppedFiles(DropDoneDetails detail) async {
    setState(() => _isDragging = false);
    if (detail.files.isEmpty) return;

    final existingNames = _selectedFiles
        .map((entry) => (entry['file'] as PlatformFile).name)
        .toSet();

    final newEntries = <Map<String, dynamic>>[];
    var rejectedType = 0;

    for (final xfile in detail.files) {
      final ext = xfile.name.split('.').last.toLowerCase();
      if (!_allowedExtensions.contains(ext)) {
        rejectedType++;
        continue;
      }
      if (existingNames.contains(xfile.name)) continue;

      final bytes = await xfile.readAsBytes();
      final platformFile = PlatformFile(
        name: xfile.name,
        size: bytes.length,
        bytes: bytes,
      );
      newEntries.add({
        'file': platformFile,
        'name': xfile.name.replaceAll(RegExp(r'\.[^.]*$'), ''),
        'isSvg': ext == 'svg',
      });
      existingNames.add(xfile.name);
    }

    if (newEntries.isEmpty) {
      if (rejectedType > 0 && mounted) {
        _showErrorSnackBar(
          context,
          'teacher.teacher_upload_image_screen.onlyPngSvgWebp'.tr(),
        );
      }
      return;
    }

    setState(() {
      _selectedFiles = [..._selectedFiles, ...newEntries];
    });

    if (!mounted) return;
    if (rejectedType > 0) {
      _showErrorSnackBar(
        context,
        'teacher.teacher_upload_image_screen.filesSkippedMsg'
            .tr(namedArgs: {'count': '$rejectedType'}),
      );
    }
    _showPreviewSheet();
  }

  void _showPreviewSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TeacherPreviewSheet(
        selectedFiles: _selectedFiles,
        onSelectMore: _selectMoreImages,
        onRemove: (index) {
          setState(() => _selectedFiles.removeAt(index));
          Navigator.pop(ctx);
          if (_selectedFiles.isNotEmpty) _showPreviewSheet();
        },
        onClearAll: () {
          setState(() => _selectedFiles = []);
          Navigator.pop(ctx);
        },
        onUpload: () {
          Navigator.pop(ctx);
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
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.cloud_upload_rounded,
              color: AppColors.primary,
              size: 24,
            ),
            const SizedBox(width: AppSpacing.sm + 2),
            Text(
              'teacher.teacher_upload_image_screen.confirmUpload'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  height: 1.5,
                ),
                children: [
                  TextSpan(
                    text: 'teacher.teacher_upload_image_screen.imageCount'
                        .plural(_selectedFiles.length),
                  ),
                  TextSpan(
                      text: 'teacher.teacher_upload_image_screen.willBeScannedSuffix'
                          .tr()),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm + 2),
              decoration: BoxDecoration(
                color: AppColors.primarySoft(0.06),
                borderRadius: BorderRadius.circular(AppRadii.sm),
                border: Border.all(color: AppColors.primarySoft(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.folder_rounded,
                    color: AppColors.primary,
                    size: 16,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'teacher.teacher_upload_image_screen.toCategory'
                          .tr(namedArgs: {'category': widget.categoryDisplayName}),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'common.cancel'.tr(),
              style: const TextStyle(color: AppColors.muted),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _uploadImages();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              elevation: 0,
            ),
            child: Text(
              'teacher.teacher_upload_image_screen.uploadNow'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadImages() async {
    if (_selectedFiles.isEmpty) return;
    setState(() {
      _isUploading = true;
      _uploadedCount = 0;
      _totalCount = _selectedFiles.length;
    });

    int success = 0;
    int rejectedContent = 0;
    int failedTechnical = 0;

    for (final entry in _selectedFiles) {
      final file = entry['file'];
      final imageName = entry['name'] as String;
      final ext = file.name.split('.').last;
      try {
        final result = await _imageService.uploadToCloudinary(
          file,
          categoryName: widget.categoryName,
        );
        if (result['success'] != true) {
          if (result['reason'] == 'REJECT_INAPPROPRIATE_IMAGE') {
            rejectedContent++;
          } else {
            failedTechnical++;
          }
        } else {
          await _db.saveImageMetadata(
            ownerId: widget.ownerId,
            categoryId: widget.categoryId,
            name: imageName,
            imageUrl: result['secure_url'] as String,
            cloudinaryPublicId: result['public_id'] as String,
            fileExtension: ext,
          );
          success++;
        }
      } catch (_) {
        failedTechnical++;
      }
      if (mounted) setState(() => _uploadedCount++);
    }

    setState(() {
      _isUploading = false;
      _selectedFiles = [];
    });
    if (!mounted) return;

    Navigator.pop(context, {
      'success': success,
      'rejectedContent': rejectedContent,
      'failedTechnical': failedTechnical,
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final hasFiles = _selectedFiles.isNotEmpty;
    final isRecommended = _selectedFiles.length >= _minRec;
    final progress = _totalCount > 0 ? _uploadedCount / _totalCount : 0.0;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: widget.categoryDisplayName,
            subtitle: 'teacher.teacher_upload_image_screen.uploadImages'.tr(),
          ),
          Expanded(
            child: DropTarget(
              onDragEntered: (_) => setState(() => _isDragging = true),
              onDragExited: (_) => setState(() => _isDragging = false),
              onDragDone: _handleDroppedFiles,
              child: Stack(
                children: [
                  _isUploading
                      ? TeacherUploadingView(
                          progress: progress,
                          uploaded: _uploadedCount,
                          total: _totalCount,
                        )
                      : TeacherIdleView(
                          selectedCount: _selectedFiles.length,
                          minRecommended: _minRec,
                          isRecommended: isRecommended,
                          hasFiles: hasFiles,
                          onPreview: _showPreviewSheet,
                          onClear: () => setState(() => _selectedFiles = []),
                        ),
                  if (_isDragging && !_isUploading) const _DragOverlay(),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _isUploading
          ? null
          : FloatingActionButton.extended(
              heroTag: null,
              onPressed: hasFiles ? _confirmAndUpload : _selectImages,
              backgroundColor: hasFiles
                  ? (isRecommended ? Colors.blue : Colors.orange)
                  : AppColors.primary,
              elevation: 3,
              icon: Icon(
                hasFiles
                    ? Icons.cloud_upload_rounded
                    : Icons.add_photo_alternate_rounded,
                color: AppColors.onPrimary,
              ),
              label: Text(
                hasFiles
                    ? '${'teacher.teacher_upload_image_screen.uploadCount'.tr(namedArgs: {
                        'count': '${_selectedFiles.length}'
                      })}${isRecommended ? " ✅" : ""}'
                    : 'teacher.teacher_upload_image_screen.selectImages'.tr(),
                style: const TextStyle(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
    );
  }
}

// ── Drag overlay ──────────────────────────────────────────────────────────────
// Purely visual — DropTarget's onDragEntered/onDragExited already handle
// the actual drop mechanics, this just makes the target area obvious while
// a file is being dragged over it. IgnorePointer so it never intercepts
// taps once the drag ends. Mirrors admin_upload_image_screen.dart's.
class _DragOverlay extends StatelessWidget {
  const _DragOverlay();

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.primarySoft(0.08),
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.primary, width: 2.5),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.file_download_rounded,
                    size: 40,
                    color: AppColors.onPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'teacher.teacher_upload_image_screen.dropImagesToAdd'.tr(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
