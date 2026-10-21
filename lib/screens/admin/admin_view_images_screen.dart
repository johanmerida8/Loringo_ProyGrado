// admin_view_images_screen.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/models/image_pending_op.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/admin/admin_upload_image_screen.dart';
import 'package:loringo_app/screens/admin/widgets/admin_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/image_service.dart';

class AdminViewImagesScreen extends StatefulWidget {
  final String ownerId;
  final String categoryId;
  // Folder-safe form (e.g. "sea_animals") — used as the Cloudinary folder,
  // never shown to the user. See Database.createCategory.
  final String categoryName;
  // What the user actually typed (e.g. "Sea Animals") — shown in the UI.
  final String categoryDisplayName;

  const AdminViewImagesScreen({
    super.key,
    required this.ownerId,
    required this.categoryId,
    required this.categoryName,
    required this.categoryDisplayName,
  });

  @override
  State<AdminViewImagesScreen> createState() => _AdminViewImagesScreenState();
}

class _AdminViewImagesScreenState extends State<AdminViewImagesScreen> {
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

  // ✅ Guarda anti-doble-tap: evita dos instancias de AdminUploadImageScreen
  // coexistiendo (mismo bug de Hero tag duplicado que en teacher).
  Future<void> _openUploadScreen() async {
    if (_isNavigatingToUpload) return;
    _isNavigatingToUpload = true;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminUploadImageScreen(
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
      // Espera a que la animación de transición de ruta termine antes de
      // insertar el SnackBar, evitando "Floating SnackBar off screen".
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
              title: Text('admin.admin_view_images_screen.markForDelete'.tr()),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            ListTile(
              leading: const Icon(
                Icons.swap_horiz_rounded,
                color: AppColors.primary,
              ),
              title: Text('admin.admin_view_images_screen.replaceImage'.tr()),
              onTap: () => Navigator.pop(ctx, 'replace'),
            ),
            if (hasPending)
              ListTile(
                leading: const Icon(Icons.undo_rounded, color: AppColors.muted),
                title: Text('admin.admin_view_images_screen.undoChange'.tr()),
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
      final file = await _imageService.pickImage();
      if (!mounted || file == null) return;
      if (file.bytes == null) {
        _showErrorSnackBar(
            context, 'admin.admin_view_images_screen.fileReadError'.tr());
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
          'admin.admin_view_images_screen.confirmChangesTitle'.tr(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'admin.admin_view_images_screen.confirmChangesMsg'.tr(namedArgs: {
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

    // Sequential, like the upload loop in AdminUploadImageScreen. Both
    // paths remove the Cloudinary file too, so storage doesn't pile up —
    // tasks that copied the old image URL will show it as broken (accepted
    // trade-off). Ops that fail stay staged so the admin can retry or undo.
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
        'admin.admin_view_images_screen.deletedCount'
            .tr(namedArgs: {'count': '$deleted'}),
      if (replaced > 0)
        'admin.admin_view_images_screen.replacedCount'
            .tr(namedArgs: {'count': '$replaced'}),
      if (rejectedContent > 0)
        'admin.admin_view_images_screen.flaggedCount'
            .tr(namedArgs: {'count': '$rejectedContent'}),
      if (failedTechnical > 0)
        'admin.admin_view_images_screen.failedCount'
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
          'admin.admin_view_images_screen.discardChangesTitle'.tr(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'admin.admin_view_images_screen.discardChangesMsg'.tr(),
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
              'admin.admin_view_images_screen.discard'.tr(),
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

  // ✅ Snackbar diferenciado: distingue rechazo por contenido de error técnico.
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
                    'admin.admin_view_images_screen.uploadedCount'
                        .tr(namedArgs: {'count': '$success'}),
                  if (rejectedContent > 0)
                    'admin.admin_view_images_screen.flaggedCount'
                        .tr(namedArgs: {'count': '$rejectedContent'}),
                  if (failedTechnical > 0)
                    'admin.admin_view_images_screen.failedCount'
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
          AdminScreenHeader(
            title: widget.categoryDisplayName,
            subtitle: 'admin.admin_view_images_screen.imageCount'
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
                      'admin.admin_view_images_screen.confirmChangesButton'
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
                ? _EmptyGallery(onAdd: _openUploadScreen)
                : CustomScrollView(
                    controller: _scrollCtrl,
                    slivers: [
                      // Stats header
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
                                    'admin.admin_view_images_screen.imagesCountLabel'
                                        .plural(images.length),
                                    style: const TextStyle(
                                      color: AppColors.onPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'admin.admin_view_images_screen.scrollToLoadMore'
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

                      // Image grid
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
                            (_, i) => _ImageTile(
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
      // ✅ heroTag único explícito — evita "multiple heroes share the same tag"
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin_view_images_fab',
        onPressed: _openUploadScreen,
        backgroundColor: AppColors.primary,
        elevation: 3,
        icon: const Icon(
          Icons.add_photo_alternate_rounded,
          color: AppColors.onPrimary,
        ),
        label: Text(
          'admin.admin_view_images_screen.addImages'.tr(),
          style: const TextStyle(
            color: AppColors.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ── Image tile ────────────────────────────────────────────────────────────────

class _ImageTile extends StatelessWidget {
  final Map<String, dynamic> image;
  final ImagePendingOp? pendingOp;
  final VoidCallback onLongPress;

  const _ImageTile({
    required this.image,
    required this.pendingOp,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final replacement =
        pendingOp?.kind == ImagePendingKind.replace ? pendingOp!.file : null;
    final markedForDelete = pendingOp?.kind == ImagePendingKind.delete;

    return GestureDetector(
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
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
                ),
              ),
              child: replacement != null
                  ? _ReplacementPreview(file: replacement)
                  : Image.network(
                      image['displayUrl'] ?? image['imageUrl'],
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[300],
                        child: const Icon(
                          Icons.broken_image,
                          color: AppColors.muted,
                          size: 32,
                        ),
                      ),
                    ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs + 2,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(AppRadii.md - 2),
                  bottomRight: Radius.circular(AppRadii.md - 2),
                ),
              ),
              child: Text(
                image['name'] ?? 'common.untitled'.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.onPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
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
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.edit_rounded,
                  color: AppColors.onPrimary,
                  size: 14,
                ),
              ),
            ),
          if (markedForDelete)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(AppRadii.md - 2),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.delete_rounded,
                      color: AppColors.onPrimary,
                      size: 28,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'admin.admin_view_images_screen.markedForDelete'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.onPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
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
        child: const Icon(
          Icons.image_rounded,
          color: AppColors.primary,
          size: 32,
        ),
      );
    }
    return Image.memory(file.bytes!, fit: BoxFit.cover);
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
                  'admin.admin_view_images_screen.applyingChanges'.tr(),
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

// ── Empty gallery ─────────────────────────────────────────────────────────────

class _EmptyGallery extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyGallery({required this.onAdd});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: AppDecorations.primaryGradient,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primarySoft(0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.image_not_supported_outlined,
              size: 48,
              color: AppColors.onPrimary,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'admin.admin_view_images_screen.noImagesYet'.tr(),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          Text(
            'admin.admin_view_images_screen.uploadImagesToCategoryMsg'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[500],
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          ElevatedButton.icon(
            onPressed: onAdd,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(
                horizontal: 28,
                vertical: AppSpacing.md - 2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              elevation: 3,
            ),
            icon: const Icon(Icons.add_photo_alternate_rounded),
            label: Text(
              'admin.admin_view_images_screen.uploadImages'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ],
      ),
    ),
  );
}
