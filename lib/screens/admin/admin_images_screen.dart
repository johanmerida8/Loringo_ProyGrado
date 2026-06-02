import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/admin/admin_view_images_screen.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/utils/image_service.dart';

// ── AdminImagesScreen ─────────────────────────────────────────────────────────
// Redesigned: category grid with image-count badges, gradient cards, hero empty state.

class AdminImagesScreen extends StatelessWidget {
  const AdminImagesScreen({super.key});
  static const Color _green  = Color(0xFF4CAF50);
  static const Color _green2 = Color(0xFF2E7D32);

  Future<void> _showCreateCategoryDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final db   = Database();
    final uid  = FirebaseAuth.instance.currentUser!.uid;

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
                    categoryName: sanitized, ownerId: uid, ownerRole: 'admin');
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
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('"$categoryName" deleted'),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F0),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.getAdminCategoriesStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _green));
          }
          final docs = snap.data?.docs ?? [];

          if (docs.isEmpty) return _EmptyState(onTap: () => _showCreateCategoryDialog(context));

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
                      onTap: () => _showCreateCategoryDialog(context),
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
                    (ctx, i) => _CategoryCard(
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
        onPressed: () => _showCreateCategoryDialog(context),
        backgroundColor: _green,
        elevation: 4,
        icon: const Icon(Icons.create_new_folder_rounded, color: Colors.white),
        label: const Text('New Category',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ── Category card ─────────────────────────────────────────────────────────────

class _CategoryCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final Database db;
  final void Function(String id, String name) onDelete;

  const _CategoryCard({required this.doc, required this.db, required this.onDelete});

  static const Color _green = Color(0xFF4CAF50);

  // Pick a folder accent color based on name hash for visual variety
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
          builder: (_) => AdminViewImagesScreen(
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
          // ── Color accent strip + letter ─────────────────────────────
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

          // ── Name + image count ──────────────────────────────────────
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

          // ── Actions ─────────────────────────────────────────────────
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

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyState({required this.onTap});
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