import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/image_service.dart';

// ── TeacherImageScreen ────────────────────────────────────────────────────────
// List of teacher's private image categories.
// Mirrors AdminImagesScreen in layout and behavior.

class TeacherImageScreen extends StatelessWidget {
  const TeacherImageScreen({super.key});
  static const Color _green  = Color(0xFF4CAF50);
  static const Color _green2 = Color(0xFF2E7D32);
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  Future<void> _showCreateDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final db   = Database();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.create_new_folder_rounded, color: _green, size: 22),
          ),
          const SizedBox(width: 12),
          const Text('New Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctrl, autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Category name',
              hintText: 'e.g. "Animals"',
              prefixIcon: const Icon(Icons.folder_rounded, color: _green),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _green, width: 2)),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.info_outline, size: 13, color: Colors.grey),
            const SizedBox(width: 4),
            Text('Spaces → underscores, lowercase',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _green, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              final raw = ctrl.text.trim();
              if (raw.isEmpty) return;
              final sanitized = raw.replaceAll(' ', '_')
                  .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '').toLowerCase();
              if (sanitized.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await db.createCategory(
                    categoryName: sanitized,
                    ownerId: FirebaseAuth.instance.currentUser!.uid,
                    ownerRole: 'teacher');
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Row(children: [
                      const Icon(Icons.check_circle, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text('Category "$sanitized" created'),
                    ]),
                    backgroundColor: _green,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
              }
            },
            child: const Text('Create', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCategory(BuildContext context, Database db,
      String categoryId, String categoryName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.delete_outline, color: Colors.red, size: 22)),
          const SizedBox(width: 12),
          const Text('Delete Category', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: RichText(text: TextSpan(
            style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
            children: [
              const TextSpan(text: 'Delete '),
              TextSpan(text: '"$categoryName"',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const TextSpan(text: ' and all its images?\n'),
              TextSpan(text: 'This cannot be undone.',
                  style: TextStyle(color: Colors.red[400], fontSize: 12)),
            ])),
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
    if (confirm != true || !context.mounted) return;
    try {
      final imageService = ImageService();
      final images = await db.getImagesByCategory(categoryId);
      for (final img in images) {
        final pid = img['cloudinaryPublicId'] as String? ?? '';
        if (pid.isNotEmpty) await imageService.deleteImage(pid);
        await db.deleteImage(categoryId, img['id'] as String);
      }
      await db.deleteCategory(categoryId);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$categoryName" deleted'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = Database();
    final uid = _uid;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F0),
      appBar: AppBar(
        title: const Text('Image Category',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: _green,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.getTeacherCategoriesStream(uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _green));
          }
          final docs = snap.data?.docs ?? [];

          if (docs.isEmpty) return _TeacherEmptyState(onTap: () => _showCreateDialog(context));

          return CustomScrollView(
            slivers: [
              // ── Summary band ───────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [_green, _green2],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: _green.withOpacity(0.3),
                        blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Row(children: [
                    const Icon(Icons.folder_special_rounded, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${docs.length} categor${docs.length != 1 ? 'ies' : 'y'}',
                          style: const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.bold, fontSize: 17)),
                      const Text('Tap a category to view its images',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ]),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _showCreateDialog(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.4))),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.add, color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text('New', style: TextStyle(color: Colors.white,
                              fontWeight: FontWeight.bold, fontSize: 13)),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),

              // ── Category list ──────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _TeacherCategoryCard(
                      doc: docs[i],
                      db: db,
                      onDelete: (id, name) => _deleteCategory(context, db, id, name),
                    ),
                    childCount: docs.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context),
        backgroundColor: _green,
        elevation: 4,
        icon: const Icon(Icons.create_new_folder_rounded, color: Colors.white),
        label: const Text('New Category',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ── Teacher category card ──────────────────────────────────────────────────────

class _TeacherCategoryCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final Database db;
  final void Function(String id, String name) onDelete;

  const _TeacherCategoryCard({required this.doc, required this.db, required this.onDelete});

  static const Color _green = Color(0xFF4CAF50);

  Color _accentFor(String name) {
    const palette = [
      Color(0xFF4CAF50), Color(0xFF2196F3), Color(0xFF9C27B0),
      Color(0xFFFF9800), Color(0xFF00BCD4), Color(0xFFE91E63),
      Color(0xFF3F51B5), Color(0xFF009688),
    ];
    return palette[name.hashCode.abs() % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final data         = doc.data() as Map<String, dynamic>;
    final categoryName = data['categoryName'] as String? ?? 'Unnamed';
    final categoryId   = doc.id;
    final accent       = _accentFor(categoryName);
    final initial      = categoryName.isNotEmpty
        ? categoryName[0].toUpperCase() : '#';

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => TeacherViewImagesScreen(
              categoryId: categoryId, categoryName: categoryName))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Container(
            width: 64, height: 64,
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [accent, accent.withOpacity(0.6)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: accent.withOpacity(0.35),
                  blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: Center(
              child: Text(initial, style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
            ),
          ),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(categoryName, style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
              const SizedBox(height: 4),
              StreamBuilder<int>(
                stream: db.getImagesCountStream(categoryId),
                builder: (_, snap) {
                  final count = snap.data ?? 0;
                  return Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: accent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.image_rounded, size: 12, color: accent),
                        const SizedBox(width: 4),
                        Text('$count image${count != 1 ? 's' : ''}',
                            style: TextStyle(fontSize: 11, color: accent,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ]);
                },
              ),
            ],
          )),
          Row(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: () => onDelete(categoryId, categoryName),
              child: Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(right: 14),
              child: Icon(Icons.chevron_right_rounded,
                  color: Colors.grey[400], size: 22),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ── Teacher empty state ────────────────────────────────────────────────────────

class _TeacherEmptyState extends StatelessWidget {
  final VoidCallback onTap;
  const _TeacherEmptyState({required this.onTap});
  static const Color _green = Color(0xFF4CAF50);

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 110, height: 110,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: _green.withOpacity(0.4),
                blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: const Icon(Icons.photo_library_rounded,
              size: 52, color: Colors.white),
        ),
        const SizedBox(height: 28),
        const Text('No Image Categories Yet',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                color: Colors.black87)),
        const SizedBox(height: 10),
        Text('Create categories to organize your\neducational image library',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[500], height: 1.5)),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
              backgroundColor: _green, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 3),
          icon: const Icon(Icons.create_new_folder_rounded),
          label: const Text('Create First Category',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      ]),
    ),
  );
}

// ── TeacherViewImagesScreen ───────────────────────────────────────────────────
// Grid gallery of images in a category.
// Mirrors AdminViewImagesScreen — navigates to TeacherUploadImageScreen to add.

class TeacherViewImagesScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;
  const TeacherViewImagesScreen(
      {super.key, required this.categoryId, required this.categoryName});

  @override
  State<TeacherViewImagesScreen> createState() =>
      _TeacherViewImagesScreenState();
}

class _TeacherViewImagesScreenState extends State<TeacherViewImagesScreen> {
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
              ? _TeacherEmptyGalleryState(
                  onAdd: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => TeacherUploadImageScreen(
                                categoryId: widget.categoryId,
                                categoryName: widget.categoryName)))
                    .then((_) => _loadImages()))
              : CustomScrollView(
                  controller: _scrollController,
                  slivers: [
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
                            return _TeacherImageTile(
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
                    builder: (_) => TeacherUploadImageScreen(
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

// ── Teacher image tile ─────────────────────────────────────────────────────────

class _TeacherImageTile extends StatefulWidget {
  final Map<String, dynamic> image;
  final VoidCallback onDelete;
  const _TeacherImageTile({required this.image, required this.onDelete});

  @override
  State<_TeacherImageTile> createState() => _TeacherImageTileState();
}

class _TeacherImageTileState extends State<_TeacherImageTile> {
  bool _showDelete = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => setState(() => _showDelete = !_showDelete),
      child: Stack(
        fit: StackFit.expand,
        children: [
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

// ── Teacher empty gallery state ────────────────────────────────────────────────

class _TeacherEmptyGalleryState extends StatelessWidget {
  final VoidCallback onAdd;
  const _TeacherEmptyGalleryState({required this.onAdd});
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
        Text(
          'Upload images to this category to get started',
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

// ── TeacherUploadImageScreen ──────────────────────────────────────────────────
// Dedicated upload screen — same UX as AdminUploadImageScreen.
// Bottom sheet preview + progress bar during upload.

class TeacherUploadImageScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;
  const TeacherUploadImageScreen(
      {super.key, required this.categoryId, required this.categoryName});

  @override
  State<TeacherUploadImageScreen> createState() =>
      _TeacherUploadImageScreenState();
}

class _TeacherUploadImageScreenState extends State<TeacherUploadImageScreen> {
  final _imageService = ImageService();
  final _db = Database();
  static const int  _minRecommended = 15;
  static const Color _green = Color(0xFF4CAF50);
  List<Map<String, dynamic>> _selectedFiles = [];
  bool _isUploading   = false;
  int  _uploadedCount = 0;
  int  _totalCount    = 0;

  Future<void> _selectImages() async {
    try {
      final picked = await _imageService.pickMultipleImages();
      if (picked == null || picked.isEmpty) return;
      setState(() {
        _selectedFiles = picked.map((f) => {
          'file': f,
          'name': f.name.replaceAll(RegExp(r'\.[^.]*$'), ''),
          'isSvg': f.name.toLowerCase().endsWith('.svg'),
        }).toList();
      });
      if (mounted) _showPreviewSheet();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
    }
  }

  void _showPreviewSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TeacherPreviewSheet(
        selectedFiles: _selectedFiles,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.cloud_upload_rounded, color: Color(0xFF4CAF50), size: 24),
          SizedBox(width: 10),
          Text('Confirm Upload', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          RichText(text: TextSpan(
              style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
              children: [
                TextSpan(text: '${_selectedFiles.length} image${_selectedFiles.length != 1 ? "s" : ""}'),
                const TextSpan(text: ' will be scanned before uploading.'),
              ])),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.2))),
            child: Row(children: [
              const Icon(Icons.folder_rounded, color: Color(0xFF4CAF50), size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text('To: ${widget.categoryName}',
                  style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w600, color: Color(0xFF4CAF50)))),
            ]),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () { Navigator.pop(ctx); _uploadImages(); },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Upload Now', style: TextStyle(fontWeight: FontWeight.bold)),
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
    int success = 0, rejected = 0, failed = 0;
    for (final entry in _selectedFiles) {
      final file = entry['file'];
      final imageName = entry['name'] as String;
      final ext = file.name.split('.').last;
      try {
        final result = await _imageService.uploadToCloudinary(
            file, categoryName: widget.categoryName);
        if (result['success'] != true) { rejected++; }
        else {
          await _db.saveImageMetadata(
            categoryId: widget.categoryId, name: imageName,
            imageUrl: result['secure_url'] as String,
            cloudinaryPublicId: result['public_id'] as String,
            fileExtension: ext,
          );
          success++;
        }
      } catch (_) { failed++; }
      if (mounted) setState(() => _uploadedCount++);
    }
    setState(() { _isUploading = false; _selectedFiles = []; });
    if (!mounted) return;
    final allGood = rejected == 0 && failed == 0;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(allGood ? Icons.check_circle : Icons.warning_rounded,
            color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text([
          if (success > 0)  '$success uploaded',
          if (rejected > 0) '$rejected rejected',
          if (failed > 0)   '$failed failed',
        ].join(' · '))),
      ]),
      backgroundColor: allGood ? _green : Colors.orange,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 4),
    ));
    if (success > 0) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final hasFiles      = _selectedFiles.isNotEmpty;
    final isRecommended = _selectedFiles.length >= _minRecommended;
    final progress      = _totalCount > 0 ? _uploadedCount / _totalCount : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F0),
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, children: [
          Text(widget.categoryName,
              style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.bold, fontSize: 16)),
          const Text('Upload Images',
              style: TextStyle(color: Colors.white70, fontSize: 11)),
        ]),
        backgroundColor: _green, elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isUploading
          ? _TeacherUploadingView(
              progress: progress, uploaded: _uploadedCount, total: _totalCount)
          : _TeacherIdleView(
              selectedCount: _selectedFiles.length,
              minRecommended: _minRecommended,
              isRecommended: isRecommended,
              hasFiles: hasFiles,
              onPreview: _showPreviewSheet,
              onClear: () => setState(() => _selectedFiles = []),
            ),
      floatingActionButton: _isUploading ? null :
          Column(mainAxisAlignment: MainAxisAlignment.end, children: [
            FloatingActionButton.extended(
              heroTag: 't_select',
              onPressed: _selectImages,
              backgroundColor: _green,
              elevation: 3,
              icon: const Icon(Icons.add_photo_alternate_rounded, color: Colors.white),
              label: const Text('Select Images',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            if (hasFiles) ...[
              const SizedBox(height: 12),
              FloatingActionButton.extended(
                heroTag: 't_upload',
                onPressed: _confirmAndUpload,
                backgroundColor: isRecommended ? Colors.blue : Colors.orange,
                elevation: 3,
                icon: const Icon(Icons.cloud_upload_rounded, color: Colors.white),
                label: Text('Upload ${_selectedFiles.length}',
                    style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
    );
  }
}

// ── Teacher-specific idle / uploading / preview widgets ───────────────────────
// These mirror the admin versions but with teacher-prefixed names to avoid
// duplicate class errors if both files are imported in the same scope.

class _TeacherIdleView extends StatelessWidget {
  final int selectedCount, minRecommended;
  final bool isRecommended, hasFiles;
  final VoidCallback onPreview, onClear;
  const _TeacherIdleView({
    required this.selectedCount, required this.minRecommended,
    required this.isRecommended, required this.hasFiles,
    required this.onPreview, required this.onClear,
  });
  static const Color _green = Color(0xFF4CAF50);

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 100, height: 100,
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: hasFiles
                    ? [Colors.orange.shade400, Colors.orange.shade700]
                    : [_green, const Color(0xFF2E7D32)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [BoxShadow(
                color: (hasFiles ? Colors.orange : _green).withOpacity(0.4),
                blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: Icon(
              hasFiles ? Icons.photo_library_rounded
                       : Icons.add_photo_alternate_outlined,
              size: 46, color: Colors.white),
        ),
        const SizedBox(height: 24),
        Text(hasFiles ? 'Ready to Upload' : 'Select PNG or SVG images',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                color: Colors.black87),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
              color: (isRecommended ? _green : Colors.orange).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: (isRecommended ? _green : Colors.orange).withOpacity(0.3))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(isRecommended ? Icons.check_circle : Icons.info_outline,
                size: 16,
                color: isRecommended ? _green : Colors.orange),
            const SizedBox(width: 6),
            Text(
              selectedCount == 0
                  ? 'No images selected'
                  : '$selectedCount selected · ${isRecommended
                      ? "Ready!" : "${minRecommended - selectedCount} more recommended"}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: isRecommended ? _green : Colors.orange),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Text('Recommended: $minRecommended+ images per category',
            style: TextStyle(fontSize: 11, color: Colors.grey[500],
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
                  side: const BorderSide(color: Colors.orange, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            )),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.clear_rounded, size: 18),
              label: const Text('Clear',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            )),
          ]),
        ] else ...[
          const SizedBox(height: 16),
          Text('Only PNG and SVG files are accepted',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[400])),
        ],
        const SizedBox(height: 100),
      ]),
    ),
  );
}

class _TeacherUploadingView extends StatelessWidget {
  final double progress;
  final int uploaded, total;
  const _TeacherUploadingView(
      {required this.progress, required this.uploaded, required this.total});
  static const Color _green = Color(0xFF4CAF50);

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 90, height: 90,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [_green, Color(0xFF2E7D32)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: _green.withOpacity(0.4),
                blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: const Icon(Icons.cloud_upload_rounded, size: 44, color: Colors.white),
        ),
        const SizedBox(height: 28),
        const Text('Uploading Images…',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('$uploaded of $total processed',
            style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        const SizedBox(height: 24),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress, minHeight: 10,
            backgroundColor: Colors.grey[200],
            valueColor: const AlwaysStoppedAnimation(_green),
          ),
        ),
        const SizedBox(height: 12),
        Text('${(progress * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                color: _green)),
        const SizedBox(height: 20),
        Text('Scanning each image for content safety…',
            style: TextStyle(fontSize: 12, color: Colors.grey[400])),
      ]),
    ),
  );
}

class _TeacherPreviewSheet extends StatelessWidget {
  final List<Map<String, dynamic>> selectedFiles;
  final void Function(int index) onRemove;
  final VoidCallback onClearAll, onUpload;
  const _TeacherPreviewSheet({
    required this.selectedFiles, required this.onRemove,
    required this.onClearAll, required this.onUpload,
  });
  static const Color _green = Color(0xFF4CAF50);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5,
      builder: (ctx, controller) => Container(
        decoration: const BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(children: [
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Row(children: [
                Container(padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: _green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.photo_library_rounded,
                        color: _green, size: 20)),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Preview — ${selectedFiles.length} image${selectedFiles.length != 1 ? "s" : ""}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const Text('Tap × to remove',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
                const Spacer(),
                TextButton.icon(
                  onPressed: onClearAll,
                  icon: const Icon(Icons.delete_sweep, size: 16, color: Colors.red),
                  label: const Text('Clear all',
                      style: TextStyle(color: Colors.red, fontSize: 12)),
                ),
              ]),
              const SizedBox(height: 12),
              const Divider(height: 1),
            ]),
          ),
          Expanded(
            child: GridView.builder(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
              itemCount: selectedFiles.length,
              itemBuilder: (_, index) {
                final file  = selectedFiles[index]['file'];
                final isSvg = selectedFiles[index]['isSvg'] as bool;
                final name  = selectedFiles[index]['name'] as String;
                return Stack(fit: StackFit.expand, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[200]!)),
                      child: isSvg
                          ? Column(mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.image_aspect_ratio_rounded,
                                    color: Colors.blue[300], size: 32),
                                const Text('SVG', style: TextStyle(
                                    fontSize: 10, fontWeight: FontWeight.bold,
                                    color: Colors.blue)),
                              ])
                          : Image.memory(file.bytes!, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.broken_image, color: Colors.grey)),
                    ),
                  ),
                  Positioned(bottom: 0, left: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(12))),
                      child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 9,
                              fontWeight: FontWeight.w500)),
                    ),
                  ),
                  Positioned(top: 4, right: 4,
                    child: GestureDetector(
                      onTap: () => onRemove(index),
                      child: Container(width: 22, height: 22,
                          decoration: BoxDecoration(color: Colors.red.shade600,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.4),
                                  blurRadius: 4)]),
                          child: const Icon(Icons.close, color: Colors.white, size: 13)),
                    ),
                  ),
                ]);
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, MediaQuery.of(context).padding.bottom + 16),
            child: SizedBox(width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onUpload,
                icon: const Icon(Icons.cloud_upload_rounded,
                    color: Colors.white, size: 20),
                label: Text(
                    'Upload ${selectedFiles.length} Image${selectedFiles.length != 1 ? "s" : ""}',
                    style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 3),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}