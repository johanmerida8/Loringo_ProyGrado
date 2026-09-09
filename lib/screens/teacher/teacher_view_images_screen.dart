import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/image_service.dart';
import 'package:loringo_app/screens/teacher/teacher_upload_image_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_empty_state.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_image_tile.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';

// ── TeacherViewImagesScreen ───────────────────────────────────────────────────

class TeacherViewImagesScreen extends StatefulWidget {
  final String ownerId;
  final String categoryId;
  // Folder-safe form — used as the Cloudinary folder, never shown to the
  // user. See Database.createCategory.
  final String categoryName;
  // What the user actually typed — shown in the UI.
  final String categoryDisplayName;

  const TeacherViewImagesScreen({
    super.key,
    required this.ownerId,
    required this.categoryId,
    required this.categoryName,
    required this.categoryDisplayName,
  });

  @override
  State<TeacherViewImagesScreen> createState() =>
      _TeacherViewImagesScreenState();
}

class _TeacherViewImagesScreenState extends State<TeacherViewImagesScreen> {
  final Database _db = Database();
  final ImageService _imageService = ImageService();

  List<Map<String, dynamic>> images = [];
  bool isLoading = false;
  int _perPage = 15;
  late ScrollController _scrollCtrl;
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
    if (_scrollCtrl.position.pixels == _scrollCtrl.position.maxScrollExtent) {
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
          ownerId: widget.ownerId,
          categoryId: widget.categoryId,
          categoryName: widget.categoryName,
          categoryDisplayName: widget.categoryDisplayName,
        ),
      ),
    );

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
      final fetched = await _db.getImagesByCategory(
        widget.ownerId,
        widget.categoryId,
      );
      setState(() {
        images = fetched;
        isLoading = false;
        _perPage = 15;
      });
    } catch (_) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _deleteImage(String imageId, String cloudinaryPublicId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        title: Row(
          children: [
            const Icon(Icons.delete_outline, color: AppColors.danger, size: 24),
            const SizedBox(width: AppSpacing.sm + 2),
            Text('teacher.teacher_view_images_screen.deleteImage'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
            'teacher.teacher_view_images_screen.imageRemovedConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'common.cancel'.tr(),
              style: const TextStyle(color: AppColors.muted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: AppColors.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              elevation: 0,
            ),
            child: Text(
              'common.delete'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted = await _imageService.deleteImage(cloudinaryPublicId);
    if (!deleted) {
      if (mounted) {
        _showErrorSnackBar(context,
            'teacher.teacher_view_images_screen.failedDeleteCloudinary'.tr());
      }
      return;
    }
    await _db.deleteImage(widget.ownerId, widget.categoryId, imageId);
    if (mounted) {
      _showSuccessSnackBar(
          context, 'teacher.teacher_view_images_screen.imageDeleted'.tr());
      _loadImages();
    }
  }

  void _showUploadResultSnackbar(Map result) {
    final success = result['success'] as int? ?? 0;
    final rejectedContent = result['rejectedContent'] as int? ?? 0;
    final failedTechnical = result['failedTechnical'] as int? ?? 0;
    final allGood = rejectedContent == 0 && failedTechnical == 0;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              allGood ? Icons.check_circle : Icons.warning_rounded,
              color: AppColors.onPrimary,
              size: 18,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                [
                  if (success > 0)
                    'teacher.teacher_view_images_screen.uploadedCount'
                        .tr(namedArgs: {'count': '$success'}),
                  if (rejectedContent > 0)
                    'teacher.teacher_view_images_screen.flaggedCount'
                        .tr(namedArgs: {'count': '$rejectedContent'}),
                  if (failedTechnical > 0)
                    'teacher.teacher_view_images_screen.failedCount'
                        .tr(namedArgs: {'count': '$failedTechnical'}),
                ].join(' · '),
              ),
            ),
          ],
        ),
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
    context.watch<LocaleProvider>();
    final displayed = images.take(_perPage).toList();
    final hasMore = _perPage < images.length;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: widget.categoryDisplayName,
            subtitle: 'teacher.teacher_view_images_screen.imageCount'
                .plural(images.length),
          ),
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : displayed.isEmpty
                ? TeacherEmptyGalleryState(onAdd: _openUploadScreen)
                : CustomScrollView(
                    controller: _scrollCtrl,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            AppSpacing.md,
                            AppSpacing.md,
                            AppSpacing.sm,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.md - 2,
                          ),
                          decoration: BoxDecoration(
                            gradient: AppDecorations.primaryGradient,
                            borderRadius: BorderRadius.circular(AppRadii.md),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primarySoft(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(
                                  AppSpacing.sm + 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.md,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.image_rounded,
                                  color: AppColors.onPrimary,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'teacher.teacher_view_images_screen.imagesCountLabel'
                                        .plural(images.length),
                                    style: const TextStyle(
                                      color: AppColors.onPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'teacher.teacher_view_images_screen.scrollToLoadMore'
                                        .tr(),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.xs,
                          AppSpacing.md,
                          100,
                        ),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                              ),
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => TeacherImageTile(
                              image: displayed[i],
                              onDelete: () => _deleteImage(
                                displayed[i]['id'],
                                displayed[i]['cloudinaryPublicId'] ?? '',
                              ),
                            ),
                            childCount: displayed.length,
                          ),
                        ),
                      ),
                      if (hasMore)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: SizedBox(
                                height: 40,
                                width: 40,
                                child: CircularProgressIndicator(
                                  color: AppColors.primarySoft(0.5),
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'view_images_fab',
        onPressed: _openUploadScreen,
        backgroundColor: AppColors.primary,
        elevation: 3,
        icon: const Icon(
          Icons.add_photo_alternate_rounded,
          color: AppColors.onPrimary,
        ),
        label: Text(
          'teacher.teacher_view_images_screen.addImages'.tr(),
          style: const TextStyle(
            color: AppColors.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
