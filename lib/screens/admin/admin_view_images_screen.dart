// admin_view_images_screen.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/admin/admin_upload_image_screen.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/image_service.dart';

class AdminViewImagesScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const AdminViewImagesScreen(
      {super.key, required this.categoryId, required this.categoryName});

  @override
  State<AdminViewImagesScreen> createState() => _AdminViewImagesScreenState();
}

class _AdminViewImagesScreenState extends State<AdminViewImagesScreen> {
  final Database      _db             = Database();
  final ImageService  _imageService   = ImageService();
  List<Map<String, dynamic>> images   = [];
  bool                isLoading       = false;
  int                 _perPage        = 15;
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

  // ✅ Guarda anti-doble-tap: evita dos instancias de AdminUploadImageScreen
  // coexistiendo (mismo bug de Hero tag duplicado que en teacher).
  Future<void> _openUploadScreen() async {
    if (_isNavigatingToUpload) return;
    _isNavigatingToUpload = true;

    final result = await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => AdminUploadImageScreen(
                categoryId:   widget.categoryId,
                categoryName: widget.categoryName)));

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
      final fetched = await _db.getImagesByCategory(widget.categoryId);
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

  // ✅ Snackbar diferenciado: distingue rechazo por contenido de error técnico.
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
                '${images.length} image${images.length != 1 ? 's' : ''}',
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
              ? _EmptyGallery(onAdd: _openUploadScreen)
              : CustomScrollView(
                  controller: _scrollCtrl,
                  slivers: [
                    // Stats header
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
                            padding: const EdgeInsets.all(
                                AppSpacing.sm + 2),
                            decoration: BoxDecoration(
                                color:
                                    Colors.white.withOpacity(0.2),
                                borderRadius:
                                    BorderRadius.circular(
                                        AppRadii.md)),
                            child: const Icon(
                                Icons.image_rounded,
                                color: AppColors.onPrimary,
                                size: 24),
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

                    // Image grid
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
                          (_, i) => _ImageTile(
                            image: displayed[i],
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
                          padding:
                              const EdgeInsets.symmetric(vertical: 20),
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
      // ✅ heroTag único explícito — evita "multiple heroes share the same tag"
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin_view_images_fab',
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

// ── Image tile ────────────────────────────────────────────────────────────────

class _ImageTile extends StatefulWidget {
  final Map<String, dynamic> image;
  final VoidCallback onDelete;

  const _ImageTile({required this.image, required this.onDelete});

  @override
  State<_ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<_ImageTile> {
  bool _showDelete = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () =>
          setState(() => _showDelete = !_showDelete),
      child: Stack(fit: StackFit.expand, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.md - 2),
          child: Container(
            decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border.all(color: AppColors.divider)),
            child: Image.network(
              widget.image['displayUrl'] ??
                  widget.image['imageUrl'],
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
              widget.image['name'] ?? 'Untitled',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.onPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
        if (_showDelete)
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.onDelete,
              child: Container(
                decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.9),
                    borderRadius:
                        BorderRadius.circular(AppRadii.md - 2)),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.delete_rounded,
                        color: AppColors.onPrimary, size: 28),
                    SizedBox(height: AppSpacing.xs),
                    Text('Delete',
                        style: TextStyle(
                            color: AppColors.onPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
      ]),
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
                const Text('No Images Yet',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                const SizedBox(height: AppSpacing.sm + 2),
                Text('Upload images to this category to get started',
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
                  label: const Text('Upload Images',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                ),
              ]),
        ),
      );
}