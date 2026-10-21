import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/models/image_pending_op.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/image_service.dart';
import 'package:loringo_app/screens/teacher/media/teacher_upload_image_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_empty_state.dart';
import 'package:loringo_app/screens/teacher/media/widgets/teacher_image_tile.dart';
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

  // Staged changes (imageId → op), applied together from the header's
  // Confirm button instead of one-by-one on long-press.
  final Map<String, ImagePendingOp> _pending = {};
  bool _isApplying = false;

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

  // ── Staged edits (mark for delete / replace) ──────────────────────────────

  Future<void> _showImageOptions(Map<String, dynamic> image) async {
    if (_isApplying) return;
    final id = image['id'] as String;
    final hasPending = _pending.containsKey(id);

    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Text(
                image['name'] ?? 'common.untitled'.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.danger),
              title: Text('teacher.teacher_view_images_screen.markForDelete'.tr()),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            ListTile(
              leading: const Icon(
                Icons.swap_horiz_rounded,
                color: AppColors.primary,
              ),
              title: Text('teacher.teacher_view_images_screen.replaceImage'.tr()),
              onTap: () => Navigator.pop(ctx, 'replace'),
            ),
            if (hasPending)
              ListTile(
                leading: const Icon(Icons.undo_rounded, color: AppColors.muted),
                title: Text('teacher.teacher_view_images_screen.undoChange'.tr()),
                onTap: () => Navigator.pop(ctx, 'undo'),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;

    if (choice == 'delete') {
      setState(() => _pending[id] = ImagePendingOp.delete());
    } else if (choice == 'undo') {
      setState(() => _pending.remove(id));
    } else if (choice == 'replace') {
      final file = await _imageService.pickImage(allowSvg: false);
      if (!mounted || file == null) return;
      if (file.bytes == null) {
        _showErrorSnackBar(
            context, 'teacher.teacher_view_images_screen.fileReadError'.tr());
        return;
      }
      setState(() => _pending[id] = ImagePendingOp.replace(file));
    }
  }

  Future<void> _applyPending() async {
    if (_pending.isEmpty || _isApplying) return;

    final toDelete =
        _pending.values.where((op) => op.kind == ImagePendingKind.delete).length;
    final toReplace = _pending.length - toDelete;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        title: Text(
          'teacher.teacher_view_images_screen.confirmChangesTitle'.tr(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'teacher.teacher_view_images_screen.confirmChangesMsg'.tr(namedArgs: {
            'deleted': '$toDelete',
            'replaced': '$toReplace',
          }),
        ),
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
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              elevation: 0,
            ),
            child: Text(
              'common.confirm'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isApplying = true);

    int deleted = 0;
    int replaced = 0;
    int rejectedContent = 0;
    int failedTechnical = 0;

    // Sequential, like the upload loop in TeacherUploadImageScreen. Both
    // paths remove the Cloudinary file too, so storage doesn't pile up —
    // tasks that copied the old image URL will show it as broken (accepted
    // trade-off). Ops that fail stay staged so the teacher can retry or undo.
    for (final entry in Map.of(_pending).entries) {
      final imageId = entry.key;
      final op = entry.value;
      final oldPublicId = (images.firstWhere(
                (img) => img['id'] == imageId,
                orElse: () => const {},
              )['cloudinaryPublicId'] as String?) ??
          '';
      try {
        if (op.kind == ImagePendingKind.delete) {
          // Cloudinary first: if it fails, the Firestore doc stays so the
          // file is never left orphaned without a record pointing at it.
          if (oldPublicId.isNotEmpty &&
              !await _imageService.deleteImage(oldPublicId)) {
            failedTechnical++;
            continue;
          }
          await _db.deleteImage(widget.ownerId, widget.categoryId, imageId);
          deleted++;
        } else {
          final file = op.file!;
          final result = await _imageService.uploadToCloudinary(
            file,
            categoryName: widget.categoryName,
          allowSvg: false,
          );
          if (result['success'] != true) {
            if (result['reason'] == 'REJECT_INAPPROPRIATE_IMAGE') {
              rejectedContent++;
            } else {
              failedTechnical++;
            }
            continue;
          }
          await _db.replaceImage(
            ownerId: widget.ownerId,
            categoryId: widget.categoryId,
            imageId: imageId,
            imageUrl: result['secure_url'] as String,
            cloudinaryPublicId: result['public_id'] as String,
            fileExtension: file.name.split('.').last,
            isModerated: result['moderationApplied'] == true,
          );
          replaced++;
          // The new image is already saved; a failed cleanup only leaves an
          // orphaned old file, so it isn't reported as a failure.
          if (oldPublicId.isNotEmpty &&
              !await _imageService.deleteImage(oldPublicId)) {
            debugPrint('Replace: old Cloudinary file not deleted: $oldPublicId');
          }
        }
        _pending.remove(imageId);
      } catch (_) {
        failedTechnical++;
      }
    }

    if (!mounted) return;
    setState(() => _isApplying = false);
    _showApplyResultSnackbar(
      deleted: deleted,
      replaced: replaced,
      rejectedContent: rejectedContent,
      failedTechnical: failedTechnical,
    );
    _loadImages();
  }

  void _showApplyResultSnackbar({
    required int deleted,
    required int replaced,
    required int rejectedContent,
    required int failedTechnical,
  }) {
    final allGood = rejectedContent == 0 && failedTechnical == 0;
    final message = [
      if (deleted > 0)
        'teacher.teacher_view_images_screen.deletedCount'
            .tr(namedArgs: {'count': '$deleted'}),
      if (replaced > 0)
        'teacher.teacher_view_images_screen.replacedCount'
            .tr(namedArgs: {'count': '$replaced'}),
      if (rejectedContent > 0)
        'teacher.teacher_view_images_screen.flaggedCount'
            .tr(namedArgs: {'count': '$rejectedContent'}),
      if (failedTechnical > 0)
        'teacher.teacher_view_images_screen.failedCount'
            .tr(namedArgs: {'count': '$failedTechnical'}),
    ].join(' · ');

    if (allGood) {
      _showSuccessSnackBar(context, message);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<bool> _confirmDiscardChanges() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        title: Text(
          'teacher.teacher_view_images_screen.discardChangesTitle'.tr(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'teacher.teacher_view_images_screen.discardChangesMsg'.tr(),
        ),
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
              'teacher.teacher_view_images_screen.discard'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _handleBlockedPop() async {
    if (_isApplying) return;
    if (await _confirmDiscardChanges() && mounted) {
      setState(() => _pending.clear());
      Navigator.pop(context);
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

    return PopScope(
      canPop: _pending.isEmpty && !_isApplying,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBlockedPop();
      },
      child: Stack(
        children: [
          _buildScaffold(displayed, hasMore),
          if (_isApplying) const _ApplyingOverlay(),
        ],
      ),
    );
  }

  Widget _buildScaffold(List<Map<String, dynamic>> displayed, bool hasMore) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
            title: widget.categoryDisplayName,
            subtitle: 'teacher.teacher_view_images_screen.imageCount'
                .plural(images.length),
            // maybePop routes through the PopScope above, so pending
            // changes get the same discard prompt as the system back.
            onBack: () => Navigator.maybePop(context),
            trailing: _pending.isEmpty
                ? null
                : ElevatedButton.icon(
                    onPressed: _isApplying ? null : _applyPending,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md - 2,
                        vertical: AppSpacing.sm,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(
                      'teacher.teacher_view_images_screen.confirmChangesButton'
                          .tr(namedArgs: {'count': '${_pending.length}'}),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
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
                              pendingOp: _pending[displayed[i]['id']],
                              onLongPress: () =>
                                  _showImageOptions(displayed[i]),
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

// ── Applying overlay ──────────────────────────────────────────────────────────

class _ApplyingOverlay extends StatelessWidget {
  const _ApplyingOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withOpacity(0.35),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppColors.primary),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'teacher.teacher_view_images_screen.applyingChanges'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
