import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/image_service.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_preview_sheet.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_upload_idle_view.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_uploading_view.dart';

// ── TeacherUploadImageScreen ──────────────────────────────────────────────────

class TeacherUploadImageScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const TeacherUploadImageScreen(
      {super.key,
      required this.categoryId,
      required this.categoryName});

  @override
  State<TeacherUploadImageScreen> createState() =>
      _TeacherUploadImageScreenState();
}

class _TeacherUploadImageScreenState
    extends State<TeacherUploadImageScreen> {
  final ImageService _imageService = ImageService();
  final Database     _db           = Database();
  static const int   _minRec       = 15;

  List<Map<String, dynamic>> _selectedFiles = [];
  bool _isUploading   = false;
  int  _uploadedCount = 0;
  int  _totalCount    = 0;

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
                  'file': f,
                  'name': f.name.replaceAll(RegExp(r'\.[^.]*$'), ''),
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
                'file': f,
                'name': f.name.replaceAll(RegExp(r'\.[^.]*$'), ''),
                'isSvg': f.name.toLowerCase().endsWith('.svg'),
              })
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
        _showErrorSnackBar(context, 'Error: $e');
      }
    }
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
                        text: ' will be scanned before uploading.'),
                  ])),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm + 2),
                decoration: BoxDecoration(
                    color: AppColors.primarySoft(0.06),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
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
                    borderRadius: BorderRadius.circular(AppRadii.sm)),
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
            file,
            categoryName: widget.categoryName);
        if (result['success'] != true) {
          if (result['reason'] == 'REJECT_INAPPROPRIATE_IMAGE') {
            rejectedContent++;
          } else {
            failedTechnical++;
          }
        } else {
          await _db.saveImageMetadata(
            categoryId:          widget.categoryId,
            name:                imageName,
            imageUrl:            result['secure_url'] as String,
            cloudinaryPublicId:  result['public_id'] as String,
            fileExtension:       ext,
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
    final progress      =
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
          ? TeacherUploadingView(
              progress: progress,
              uploaded: _uploadedCount,
              total:    _totalCount)
          : TeacherIdleView(
              selectedCount:  _selectedFiles.length,
              minRecommended: _minRec,
              isRecommended:  isRecommended,
              hasFiles:       hasFiles,
              onPreview:      _showPreviewSheet,
              onClear:        () =>
                  setState(() => _selectedFiles = []),
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