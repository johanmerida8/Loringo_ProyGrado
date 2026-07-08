import 'package:flutter/material.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/image_service.dart';
import 'package:loringo_app/screens/teacher/teacher_upload_image_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_empty_state.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_image_tile.dart';

// ── TeacherViewImagesScreen ───────────────────────────────────────────────────

class TeacherViewImagesScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const TeacherViewImagesScreen(
      {super.key,
      required this.categoryId,
      required this.categoryName});

  @override
  State<TeacherViewImagesScreen> createState() =>
      _TeacherViewImagesScreenState();
}

class _TeacherViewImagesScreenState
    extends State<TeacherViewImagesScreen> {
  final Database     _db           = Database();
  final ImageService _imageService = ImageService();

  List<Map<String, dynamic>> images      = [];
  bool                       isLoading   = false;
  int                        _perPage    = 15;
  late ScrollController      _scrollCtrl;
  bool _isNavigatingToUpload = false;

  @override
  void initState() {
    super.initState();
    _loadImages();
    _scrollCtrl = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels ==
        _scrollCtrl.position.maxScrollExtent) {
      setState(() => _perPage += 10);
    }
  }

  void _showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

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

  Future<void> _openUploadScreen() async {
    if (_isNavigatingToUpload) return;
    _isNavigatingToUpload = true;

    final result = await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => TeacherUploadImageScreen(
                categoryId:   widget.categoryId,
                categoryName: widget.categoryName)));

    _isNavigatingToUpload = false;

    _loadImages();

    if (result != null && result is Map && mounted) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        _showUploadResultSnackbar(result);
      }
    }
  }

  Future<void> _loadImages() async {
    setState(() => isLoading = true);
    try {
      final fetched =
          await _db.getImagesByCategory(widget.categoryId);
      setState(() {
        images    = fetched;
        isLoading = false;
        _perPage  = 15;
      });
    } catch (_) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _deleteImage(
      String imageId, String cloudinaryPublicId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: const Row(children: [
          Icon(Icons.delete_outline, color: AppColors.danger, size: 24),
          SizedBox(width: AppSpacing.sm + 2),
          Text('Delete Image',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: const Text(
            'This image will be permanently removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.muted))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: AppColors.onPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.sm)),
                elevation: 0),
            child: const Text('Delete',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted =
        await _imageService.deleteImage(cloudinaryPublicId);
    if (!deleted) {
      if (mounted) {
        _showErrorSnackBar(context, 'Failed to delete from Cloudinary');
      }
      return;
    }
    await _db.deleteImage(widget.categoryId, imageId);
    if (mounted) {
      _showSuccessSnackBar(context, 'Image deleted');
      _loadImages();
    }
  }

  void _showUploadResultSnackbar(Map result) {
    final success         = result['success'] as int? ?? 0;
    final rejectedContent = result['rejectedContent'] as int? ?? 0;
    final failedTechnical = result['failedTechnical'] as int? ?? 0;
    final allGood = rejectedContent == 0 && failedTechnical == 0;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(
            allGood ? Icons.check_circle : Icons.warning_rounded,
            color: AppColors.onPrimary,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text([
              if (success > 0) '$success uploaded',
              if (rejectedContent > 0) '$rejectedContent flagged as inappropriate',
              if (failedTechnical > 0) '$failedTechnical failed (technical error)',
            ].join(' · ')),
          ),
        ]),
        backgroundColor: allGood ? AppColors.primary : Colors.orange,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayed = images.take(_perPage).toList();
    final hasMore   = _perPage < images.length;

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
            Text(
                '${images.length} '
                'image${images.length != 1 ? 's' : ''}',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 11)),
          ],
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme:
            const IconThemeData(color: AppColors.onPrimary),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppColors.primary))
          : displayed.isEmpty
              ? TeacherEmptyGalleryState(
                  onAdd: _openUploadScreen)
              : CustomScrollView(
                  controller: _scrollCtrl,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(
                            AppSpacing.md, AppSpacing.md,
                            AppSpacing.md, AppSpacing.sm),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.md - 2),
                        decoration: BoxDecoration(
                          gradient: AppDecorations.primaryGradient,
                          borderRadius:
                              BorderRadius.circular(AppRadii.md),
                          boxShadow: [
                            BoxShadow(
                                color: AppColors.primarySoft(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4))
                          ],
                        ),
                        child: Row(children: [
                          Container(
                            padding:
                                const EdgeInsets.all(AppSpacing.sm + 2),
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius:
                                    BorderRadius.circular(AppRadii.md)),
                            child: const Icon(Icons.image_rounded,
                                color: AppColors.onPrimary, size: 24),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text('${images.length} Images',
                                    style: const TextStyle(
                                        color: AppColors.onPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                const Text('Scroll to load more',
                                    style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11)),
                              ]),
                        ]),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md, AppSpacing.xs,
                          AppSpacing.md, 100),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12),
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => TeacherImageTile(
                            image:    displayed[i],
                            onDelete: () => _deleteImage(
                                displayed[i]['id'],
                                displayed[i]['cloudinaryPublicId'] ??
                                    ''),
                          ),
                          childCount: displayed.length,
                        ),
                      ),
                    ),
                    if (hasMore)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 20),
                          child: Center(
                            child: SizedBox(
                              height: 40, width: 40,
                              child: CircularProgressIndicator(
                                  color: AppColors.primarySoft(0.5),
                                  strokeWidth: 2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'view_images_fab',
        onPressed: _openUploadScreen,
        backgroundColor: AppColors.primary,
        elevation: 3,
        icon: const Icon(Icons.add_photo_alternate_rounded,
            color: AppColors.onPrimary),
        label: const Text('Add Images',
            style: TextStyle(
                color: AppColors.onPrimary,
                fontWeight: FontWeight.bold)),
      ),
    );
  }
}