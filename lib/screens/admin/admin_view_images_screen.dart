import 'package:flutter/material.dart';
import 'package:loringo_app/screens/admin/admin_upload_image_screen.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/image_service.dart';

// ── AdminViewImagesScreen ─────────────────────────────────────────────────────
// Gallery view with stats header, improved grid, and polished empty state.

class AdminViewImagesScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;
  const AdminViewImagesScreen(
      {super.key, required this.categoryId, required this.categoryName});

  @override
  State<AdminViewImagesScreen> createState() => _AdminViewImagesScreenState();
}

class _AdminViewImagesScreenState extends State<AdminViewImagesScreen> {
  final Database _db = Database();
  final ImageService _imageService = ImageService();
  List<Map<String, dynamic>> images = [];
  bool isLoading = false;
  int _imagesPerPage = 15;
  late ScrollController _scrollController;
  static const Color _green = Color(0xFF4CAF50);
  static const Color _green2 = Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    _loadImages();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      setState(() => _imagesPerPage += 10);
    }
  }

  Future<void> _loadImages() async {
    setState(() => isLoading = true);
    try {
      final fetched = await _db.getImagesByCategory(widget.categoryId);
      setState(() {
        images = fetched;
        isLoading = false;
        _imagesPerPage = 15;
      });
    } catch (_) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _deleteImage(String imageId, String cloudinaryPublicId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.delete_outline, color: Colors.red, size: 24),
          SizedBox(width: 10),
          Text('Delete Image', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: const Text('This image will be permanently removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted = await _imageService.deleteImage(cloudinaryPublicId);
    if (!deleted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete from Cloudinary'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10)))));
      return;
    }
    await _db.deleteImage(widget.categoryId, imageId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image deleted'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10)))));
      _loadImages();
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayed = images.take(_imagesPerPage).toList();
    final hasMore = _imagesPerPage < images.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F0),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.categoryName,
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.bold, fontSize: 16)),
            Text('${images.length} image${images.length != 1 ? 's' : ''}',
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
        backgroundColor: _green,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : displayed.isEmpty
              ? _EmptyGalleryState(onAdd: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => AdminUploadImageScreen(
                            categoryId: widget.categoryId,
                            categoryName: widget.categoryName)))
                  .then((_) => _loadImages()))
              : CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    // ── Stats header ──────────────────────────────────────
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [_green, _green2],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                                color: _green.withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4))
                          ],
                        ),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.image_rounded,
                                color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${images.length} Images',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                const Text('Scroll to load more',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 11)),
                              ]),
                        ]),
                      ),
                    ),

                    // ── Image grid ───────────────────────────────────────
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12),
                        delegate: SliverChildBuilderDelegate(
                          (_, index) {
                            final image = displayed[index];
                            return _ImageTile(
                              image: image,
                              onDelete: () => _deleteImage(
                                  image['id'],
                                  image['cloudinaryPublicId'] ?? ''),
                            );
                          },
                          childCount: displayed.length,
                        ),
                      ),
                    ),

                    // ── Load more indicator ───────────────────────────────
                    if (hasMore)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: SizedBox(
                              height: 40,
                              width: 40,
                              child: CircularProgressIndicator(
                                color: _green.withOpacity(0.5),
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AdminUploadImageScreen(
                        categoryId: widget.categoryId,
                        categoryName: widget.categoryName)))
            .then((_) => _loadImages()),
        backgroundColor: _green,
        elevation: 4,
        icon: const Icon(Icons.add_photo_alternate_rounded, color: Colors.white),
        label: const Text('Add Images',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ── Image tile with delete action ─────────────────────────────────────────────

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
      onLongPress: () => setState(() => _showDelete = !_showDelete),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Image
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                  color: Colors.grey[100],
                  border: Border.all(color: Colors.grey[200]!)),
              child: Image.network(
                widget.image['displayUrl'] ?? widget.image['imageUrl'],
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.broken_image,
                        color: Colors.grey, size: 32)),
              ),
            ),
          ),
          // Name overlay
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(14),
                      bottomRight: Radius.circular(14))),
              child: Text(
                widget.image['name'] ?? 'Untitled',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
          // Delete button (on long press)
          if (_showDelete)
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.onDelete,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_rounded,
                          color: Colors.white, size: 28),
                      SizedBox(height: 4),
                      Text('Delete',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Empty gallery state ───────────────────────────────────────────────────────

class _EmptyGalleryState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyGalleryState({required this.onAdd});
  static const Color _green = Color(0xFF4CAF50);

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [_green, Color(0xFF2E7D32)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                  color: _green.withOpacity(0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8))
            ],
          ),
          child: const Icon(Icons.image_not_supported_outlined,
              size: 48, color: Colors.white),
        ),
        const SizedBox(height: 28),
        const Text('No Images Yet',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
        const SizedBox(height: 10),
        Text('Upload images to this category\nto get started',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, color: Colors.grey[500], height: 1.5)),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: onAdd,
          style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 3),
          icon: const Icon(Icons.add_photo_alternate_rounded),
          label: const Text('Upload Images',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      ]),
    ),
  );
}