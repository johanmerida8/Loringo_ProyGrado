// teacher_image_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/image_service.dart';

// ── TeacherImageScreen ────────────────────────────────────────────────────────

class TeacherImageScreen extends StatelessWidget {
  const TeacherImageScreen({super.key});

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  Future<void> _showCreateDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final db   = Database();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
                color: AppColors.primarySoft(0.1),
                borderRadius: BorderRadius.circular(AppRadii.sm)),
            child: const Icon(Icons.create_new_folder_rounded,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          const Text('New Category',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Category name',
              hintText: 'e.g. "Animals"',
              prefixIcon: const Icon(Icons.folder_rounded,
                  color: AppColors.primary),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 2)),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            const Icon(Icons.info_outline, size: 13, color: AppColors.muted),
            const SizedBox(width: AppSpacing.xs),
            Text('Spaces → underscores, lowercase',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ]),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.muted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.sm)),
                elevation: 0),
            onPressed: () async {
              final raw = ctrl.text.trim();
              if (raw.isEmpty) return;
              final sanitized = raw
                  .replaceAll(' ', '_')
                  .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '')
                  .toLowerCase();
              if (sanitized.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await db.createCategory(
                    categoryName: sanitized,
                    ownerId:      FirebaseAuth.instance.currentUser!.uid,
                    ownerRole:    'teacher');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Row(children: [
                        const Icon(Icons.check_circle,
                            color: AppColors.onPrimary, size: 18),
                        const SizedBox(width: AppSpacing.sm),
                        Text('Category "$sanitized" created'),
                      ]),
                      backgroundColor: AppColors.primary,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadii.md))));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: AppColors.danger));
                }
              }
            },
            child: const Text('Create',
                style: TextStyle(fontWeight: FontWeight.bold)),
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Row(children: [
          Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppRadii.sm)),
              child: Icon(Icons.delete_outline,
                  color: AppColors.danger, size: 22)),
          const SizedBox(width: AppSpacing.md),
          const Text('Delete Category',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: RichText(
            text: TextSpan(
                style: const TextStyle(
                    fontSize: 14, color: Colors.black87, height: 1.5),
                children: [
              const TextSpan(text: 'Delete '),
              TextSpan(
                  text: '"$categoryName"',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const TextSpan(text: ' and all its images?\n'),
              TextSpan(
                  text: 'This cannot be undone.',
                  style: TextStyle(
                      color: Colors.red[400], fontSize: 12)),
            ])),
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('"$categoryName" deleted'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md))));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.danger));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final db  = Database();
    final uid = _uid;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Image Categories', style: AppText.appBarTitle),
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.onPrimary),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.getTeacherCategoriesStream(uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child:
                    CircularProgressIndicator(color: AppColors.primary));
          }
          final docs = snap.data?.docs ?? [];

          if (docs.isEmpty) {
            return _TeacherEmptyState(
                onTap: () => _showCreateDialog(context));
          }

          return CustomScrollView(
            slivers: [
              // ── Summary band ───────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.md,
                      AppSpacing.md, AppSpacing.xs),
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.md - 4),
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
                    const Icon(Icons.folder_special_rounded,
                        color: AppColors.onPrimary, size: 28),
                    const SizedBox(width: AppSpacing.md),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${docs.length} '
                              'categor${docs.length != 1 ? 'ies' : 'y'}',
                              style: const TextStyle(
                                  color: AppColors.onPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17)),
                          const Text('Tap a category to view images',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12)),
                        ]),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _showCreateDialog(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md - 4,
                            vertical: AppSpacing.xs + 3),
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius:
                                BorderRadius.circular(AppRadii.pill),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.4))),
                        child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add,
                                  color: AppColors.onPrimary, size: 16),
                              SizedBox(width: AppSpacing.xs),
                              Text('New',
                                  style: TextStyle(
                                      color: AppColors.onPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                            ]),
                      ),
                    ),
                  ]),
                ),
              ),

              // ── Category list ──────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.sm,
                    AppSpacing.md, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _TeacherCategoryCard(
                      doc:      docs[i],
                      db:       db,
                      onDelete: (id, name) =>
                          _deleteCategory(context, db, id, name),
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
        backgroundColor: AppColors.primary,
        elevation: 3,
        icon: const Icon(Icons.create_new_folder_rounded,
            color: AppColors.onPrimary),
        label: const Text('New Category',
            style: TextStyle(
                color: AppColors.onPrimary,
                fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ── Teacher category card ─────────────────────────────────────────────────────

class _TeacherCategoryCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final Database db;
  final void Function(String id, String name) onDelete;

  const _TeacherCategoryCard(
      {required this.doc, required this.db, required this.onDelete});

  Color _accentFor(String name) {
    const palette = [
      AppColors.primary,
      Color(0xFF2196F3), Color(0xFF9C27B0),
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
    final initial =
        categoryName.isNotEmpty ? categoryName[0].toUpperCase() : '#';

    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => TeacherViewImagesScreen(
                  categoryId:   categoryId,
                  categoryName: categoryName))),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.md),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(children: [
          // Icon
          Container(
            width: 64, height: 64,
            margin: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [accent, accent.withOpacity(0.6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(AppRadii.md - 2),
              boxShadow: [
                BoxShadow(
                    color: accent.withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3))
              ],
            ),
            child: Center(
                child: Text(initial,
                    style: const TextStyle(
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 24))),
          ),
          // Info
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(categoryName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.black87)),
              const SizedBox(height: AppSpacing.xs),
              StreamBuilder<int>(
                stream: db.getImagesCountStream(categoryId),
                builder: (_, snap) {
                  final count = snap.data ?? 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs - 1),
                    decoration: BoxDecoration(
                        color: accent.withOpacity(0.1),
                        borderRadius:
                            BorderRadius.circular(AppRadii.pill)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.image_rounded, size: 12, color: accent),
                      const SizedBox(width: AppSpacing.xs),
                      Text('$count image${count != 1 ? 's' : ''}',
                          style: TextStyle(
                              fontSize: 11,
                              color: accent,
                              fontWeight: FontWeight.w600)),
                    ]),
                  );
                },
              ),
            ],
          )),
          // Actions
          Row(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: () => onDelete(categoryId, categoryName),
              child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  margin: const EdgeInsets.only(right: AppSpacing.xs),
                  decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(AppRadii.sm)),
                  child: Icon(Icons.delete_outline,
                      size: 18, color: AppColors.danger)),
            ),
            Container(
              margin:
                  const EdgeInsets.only(right: AppSpacing.md - 2),
              child: Icon(Icons.chevron_right_rounded,
                  color: Colors.grey[400], size: 22),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _TeacherEmptyState extends StatelessWidget {
  final VoidCallback onTap;
  const _TeacherEmptyState({required this.onTap});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                    gradient: AppDecorations.primaryGradient,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.primarySoft(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8))
                    ],
                  ),
                  child: const Icon(Icons.photo_library_rounded,
                      size: 52, color: AppColors.onPrimary),
                ),
                const SizedBox(height: 28),
                const Text('No Image Categories Yet',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                const SizedBox(height: AppSpacing.sm + 2),
                Text(
                    'Create categories to organize\nyour educational image library',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[500],
                        height: 1.5)),
                const SizedBox(height: AppSpacing.xl),
                ElevatedButton.icon(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: AppSpacing.md - 2),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadii.md)),
                      elevation: 3),
                  icon: const Icon(Icons.create_new_folder_rounded),
                  label: const Text('Create First Category',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ]),
        ),
      );
}

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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Failed to delete from Cloudinary'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating));
      }
      return;
    }
    await _db.deleteImage(widget.categoryId, imageId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Image deleted'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating));
      _loadImages();
    }
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
              ? _TeacherEmptyGalleryState(
                  onAdd: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => TeacherUploadImageScreen(
                                  categoryId:   widget.categoryId,
                                  categoryName: widget.categoryName)))
                      .then((_) => _loadImages()))
              : CustomScrollView(
                  controller: _scrollCtrl,
                  slivers: [
                    // Summary band
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
                    // Grid
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
                          (_, i) => _TeacherImageTile(
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
        onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => TeacherUploadImageScreen(
                        categoryId:   widget.categoryId,
                        categoryName: widget.categoryName)))
            .then((_) => _loadImages()),
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

class _TeacherImageTile extends StatefulWidget {
  final Map<String, dynamic> image;
  final VoidCallback onDelete;

  const _TeacherImageTile(
      {required this.image, required this.onDelete});

  @override
  State<_TeacherImageTile> createState() => _TeacherImageTileState();
}

class _TeacherImageTileState extends State<_TeacherImageTile> {
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
              widget.image['displayUrl'] ?? widget.image['imageUrl'],
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

// ── Empty gallery state ───────────────────────────────────────────────────────

class _TeacherEmptyGalleryState extends StatelessWidget {
  final VoidCallback onAdd;
  const _TeacherEmptyGalleryState({required this.onAdd});

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating));
      }
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
    int success = 0, rejected = 0, failed = 0;
    for (final entry in _selectedFiles) {
      final file      = entry['file'];
      final imageName = entry['name'] as String;
      final ext       = file.name.split('.').last;
      try {
        final result = await _imageService.uploadToCloudinary(
            file,
            categoryName: widget.categoryName);
        if (result['success'] != true) {
          rejected++;
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
        failed++;
      }
      if (mounted) setState(() => _uploadedCount++);
    }
    setState(() {
      _isUploading   = false;
      _selectedFiles = [];
    });
    if (!mounted) return;
    final allGood = rejected == 0 && failed == 0;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
            allGood
                ? Icons.check_circle
                : Icons.warning_rounded,
            color: AppColors.onPrimary,
            size: 18),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
            child: Text([
          if (success > 0)  '$success uploaded',
          if (rejected > 0) '$rejected rejected',
          if (failed > 0)   '$failed failed',
        ].join(' · '))),
      ]),
      backgroundColor: allGood ? AppColors.primary : Colors.orange,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md)),
      duration: const Duration(seconds: 4),
    ));
    if (success > 0) Navigator.pop(context);
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
          ? _TeacherUploadingView(
              progress: progress,
              uploaded: _uploadedCount,
              total:    _totalCount)
          : _TeacherIdleView(
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
          : Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 't_select',
                  onPressed: _selectImages,
                  backgroundColor: AppColors.primary,
                  elevation: 3,
                  icon: const Icon(
                      Icons.add_photo_alternate_rounded,
                      color: AppColors.onPrimary),
                  label: const Text('Select Images',
                      style: TextStyle(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.bold)),
                ),
                if (hasFiles) ...[
                  const SizedBox(height: AppSpacing.md),
                  FloatingActionButton.extended(
                    heroTag: 't_upload',
                    onPressed: _confirmAndUpload,
                    backgroundColor: isRecommended
                        ? Colors.blue
                        : Colors.orange,
                    elevation: 3,
                    icon: const Icon(Icons.cloud_upload_rounded,
                        color: AppColors.onPrimary),
                    label: Text('Upload ${_selectedFiles.length}',
                        style: const TextStyle(
                            color: AppColors.onPrimary,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
    );
  }
}

// ── Idle view ─────────────────────────────────────────────────────────────────

class _TeacherIdleView extends StatelessWidget {
  final int selectedCount, minRecommended;
  final bool isRecommended, hasFiles;
  final VoidCallback onPreview, onClear;

  const _TeacherIdleView({
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
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
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
                Text('Recommended: $minRecommended+ images per category',
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
                      label: const Text('Preview', style: TextStyle(fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          side: const BorderSide(color: Colors.orange, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md - 3),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md))),
                    )),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: OutlinedButton.icon(
                      onPressed: onClear,
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      label: const Text('Clear', style: TextStyle(fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md - 3),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md))),
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

class _TeacherUploadingView extends StatelessWidget {
  final double progress;
  final int uploaded, total;

  const _TeacherUploadingView(
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

class _TeacherPreviewSheet extends StatelessWidget {
  final List<Map<String, dynamic>> selectedFiles;
  final void Function(int) onRemove;
  final VoidCallback onClearAll, onUpload;

  const _TeacherPreviewSheet({
    required this.selectedFiles,
    required this.onRemove,
    required this.onClearAll,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize:     0.95,
      minChildSize:     0.5,
      builder: (ctx, controller) => Container(
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppRadii.lg + 4))),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
            child: Column(children: [
              Center(
                  child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: AppSpacing.md),
              Row(children: [
                Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                        color: AppColors.primarySoft(0.1),
                        borderRadius:
                            BorderRadius.circular(AppRadii.sm)),
                    child: const Icon(Icons.photo_library_rounded,
                        color: AppColors.primary, size: 20)),
                const SizedBox(width: AppSpacing.md),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      'Preview — ${selectedFiles.length} '
                      'image${selectedFiles.length != 1 ? "s" : ""}',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                  const Text('Tap × to remove',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.muted)),
                ]),
                const Spacer(),
                TextButton.icon(
                  onPressed: onClearAll,
                  icon: Icon(Icons.delete_sweep,
                      size: 16, color: AppColors.danger),
                  label: Text('Clear all',
                      style: TextStyle(
                          color: AppColors.danger, fontSize: 12)),
                ),
              ]),
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
            ]),
          ),
          Expanded(
            child: GridView.builder(
              controller: controller,
              padding: const EdgeInsets.all(AppSpacing.md),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10),
              itemCount: selectedFiles.length,
              itemBuilder: (_, index) {
                final file  = selectedFiles[index]['file'];
                final isSvg = selectedFiles[index]['isSvg'] as bool;
                final name  = selectedFiles[index]['name'] as String;
                return Stack(fit: StackFit.expand, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.md),
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
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue)),
                              ])
                          : Image.memory(file.bytes!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.broken_image,
                                      color: AppColors.muted)),
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
                      onTap: () => onRemove(index),
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
                    'Upload ${selectedFiles.length} '
                    'Image${selectedFiles.length != 1 ? "s" : ""}',
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