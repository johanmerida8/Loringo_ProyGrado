// admin_images_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/admin/admin_view_images_screen.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/image_service.dart';

class AdminImagesScreen extends StatelessWidget {
  const AdminImagesScreen({super.key});

  Future<void> _showCreateDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final db   = Database();
    final uid  = FirebaseAuth.instance.currentUser!.uid;

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
          Text('admin.admin_images_screen.newCategory'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'admin.admin_images_screen.categoryNameLabel'.tr(),
              hintText: 'admin.admin_images_screen.categoryNameHint'.tr(),
              prefixIcon:
                  const Icon(Icons.folder_rounded, color: AppColors.primary),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 2)),
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('common.cancel'.tr(),
                  style: const TextStyle(color: AppColors.muted))),
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
              // Shown to the user exactly as typed; Database.createCategory
              // derives the folder-safe categoryName from it internally.
              if (Database.sanitizeCategoryName(raw).isEmpty) return;
              Navigator.pop(ctx);
              try {
                await db.createCategory(
                    displayName: raw,
                    ownerId: uid,
                    ownerRole: 'image_manager');
                if (context.mounted) {
                  _showSuccessSnackBar(context,
                      'admin.admin_images_screen.categoryCreated'
                          .tr(namedArgs: {'name': raw}));
                }
              } catch (e) {
                if (context.mounted) {
                  _showErrorSnackBar(context,
                      'common.errorWithMessage'.tr(namedArgs: {'error': '$e'}));
                }
              }
            },
            child: Text('common.create'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── SnackBar helpers ──────────────────────────────────────────────────────

  void _showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle, color: AppColors.onPrimary, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message)),
        ]),
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

  Future<void> _deleteCategory(BuildContext context, Database db,
      String ownerId, String categoryId, String categoryName) async {
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
          Text('admin.admin_images_screen.deleteCategory'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: RichText(
            text: TextSpan(
                style: const TextStyle(
                    fontSize: 14, color: Colors.black87, height: 1.5),
                children: [
              TextSpan(text: 'admin.admin_images_screen.deletePrefix'.tr()),
              TextSpan(
                  text: '"$categoryName"',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: 'admin.admin_images_screen.deleteSuffix'.tr()),
              TextSpan(
                  text: 'admin.admin_images_screen.cannotBeUndone'.tr(),
                  style: TextStyle(
                      color: Colors.red[400], fontSize: 12)),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr(),
                  style: const TextStyle(color: AppColors.muted))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: AppColors.onPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.sm)),
                elevation: 0),
            child: Text('common.delete'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      final imageService = ImageService();
      final images = await db.getImagesByCategory(ownerId, categoryId);
      for (final img in images) {
        final pid = img['cloudinaryPublicId'] as String? ?? '';
        if (pid.isNotEmpty) await imageService.deleteImage(pid);
        await db.deleteImage(ownerId, categoryId, img['id'] as String);
      }
      await db.deleteCategory(ownerId, categoryId);
      if (context.mounted) {
        _showSuccessSnackBar(context,
            'admin.admin_images_screen.categoryDeleted'
                .tr(namedArgs: {'name': categoryName}));
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackBar(context,
            'common.errorWithMessage'.tr(namedArgs: {'error': '$e'}));
      }
    }
  }

  // Deterministic accent per category name
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
    context.watch<LocaleProvider>();
    final db = Database();
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: StreamBuilder<QuerySnapshot>(
        stream: db.getAdminCategoriesStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final docs = snap.data?.docs ?? [];

          if (docs.isEmpty) {
            return _EmptyCategories(
                onTap: () => _showCreateDialog(context));
          }

          return CustomScrollView(
            slivers: [
              // ── Summary band ──────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.md, AppSpacing.md,
                      AppSpacing.sm),
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.md - 2),
                  decoration: BoxDecoration(
                    gradient: AppDecorations.primaryGradient,
                    borderRadius: BorderRadius.circular(AppRadii.md),
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
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'admin.admin_images_screen.categoryCount'
                                    .plural(docs.length),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: AppColors.onPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17)),
                            Text('admin.admin_images_screen.tapCategoryHint'.tr(),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                          ]),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    GestureDetector(
                      onTap: () => _showCreateDialog(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md - 2,
                            vertical: AppSpacing.xs + 3),
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius:
                                BorderRadius.circular(AppRadii.pill),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.4))),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.add,
                                  color: AppColors.onPrimary, size: 16),
                              const SizedBox(width: AppSpacing.xs),
                              Text('common.newLabel'.tr(),
                                  style: const TextStyle(
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
                    AppSpacing.md, AppSpacing.xs, AppSpacing.md, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final data =
                          docs[i].data() as Map<String, dynamic>;
                      // displayName is what the user typed (e.g. "Sea
                      // Animals"); categoryName is the folder-safe form
                      // (e.g. "sea_animals") used as the actual Cloudinary
                      // folder — see Database.createCategory. Falls back to
                      // categoryName for categories created before
                      // displayName existed.
                      final folderName = data['categoryName'] as String? ??
                          'admin.admin_images_screen.unnamed'.tr();
                      final name =
                          data['displayName'] as String? ?? folderName;
                      final ownerId = data['ownerId'] as String? ?? '';
                      final accent = _accentFor(name);
                      final initial =
                          name.isNotEmpty ? name[0].toUpperCase() : '#';

                      return GestureDetector(
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => AdminViewImagesScreen(
                                    ownerId: ownerId,
                                    categoryId: docs[i].id,
                                    categoryName: folderName,
                                    categoryDisplayName: name))),
                        child: Container(
                          margin: const EdgeInsets.only(
                              bottom: AppSpacing.sm + 2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                                BorderRadius.circular(AppRadii.md),
                            boxShadow: [
                              BoxShadow(
                                  color:
                                      Colors.black.withOpacity(0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2))
                            ],
                          ),
                          child: Row(children: [
                            Container(
                              width: 64, height: 64,
                              margin: const EdgeInsets.all(AppSpacing.md),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                    colors: [
                                      accent,
                                      accent.withOpacity(0.6)
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight),
                                borderRadius:
                                    BorderRadius.circular(AppRadii.md - 2),
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
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                  Text(name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: Colors.black87)),
                                  const SizedBox(height: 4),
                                  StreamBuilder<int>(
                                    stream: db.getImagesCountStream(
                                        ownerId, docs[i].id),
                                    builder: (_, snap) {
                                      final count = snap.data ?? 0;
                                      return Container(
                                        padding: const EdgeInsets
                                            .symmetric(
                                            horizontal: AppSpacing.sm,
                                            vertical:
                                                AppSpacing.xs - 1),
                                        decoration: BoxDecoration(
                                            color: accent.withOpacity(
                                                0.1),
                                            borderRadius:
                                                BorderRadius.circular(
                                                    AppRadii.pill)),
                                        child: Row(
                                            mainAxisSize:
                                                MainAxisSize.min,
                                            children: [
                                              Icon(
                                                  Icons.image_rounded,
                                                  size: 12,
                                                  color: accent),
                                              const SizedBox(
                                                  width: AppSpacing.xs),
                                              Text(
                                                  'admin.admin_images_screen.imageCount'
                                                      .plural(count),
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: accent,
                                                      fontWeight:
                                                          FontWeight
                                                              .w600)),
                                            ]),
                                      );
                                    },
                                  ),
                                ])),
                            GestureDetector(
                              onTap: () => _deleteCategory(
                                  context, db, ownerId, docs[i].id, name),
                              child: Container(
                                  padding: const EdgeInsets.all(
                                      AppSpacing.sm),
                                  margin: const EdgeInsets.only(
                                      right: AppSpacing.xs),
                                  decoration: BoxDecoration(
                                      color: AppColors.danger
                                          .withOpacity(0.06),
                                      borderRadius:
                                          BorderRadius.circular(
                                              AppRadii.sm)),
                                  child: Icon(Icons.delete_outline,
                                      size: 18,
                                      color: AppColors.danger)),
                            ),
                            Container(
                              margin: const EdgeInsets.only(
                                  right: AppSpacing.md - 2),
                              child: Icon(Icons.chevron_right_rounded,
                                  color: Colors.grey[400], size: 22),
                            ),
                          ]),
                        ),
                      );
                    },
                    childCount: docs.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
      // ✅ heroTag único explícito — evita "multiple heroes share the same tag"
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin_categories_fab',
        onPressed: () => _showCreateDialog(context),
        backgroundColor: AppColors.primary,
        elevation: 3,
        icon: const Icon(Icons.create_new_folder_rounded,
            color: AppColors.onPrimary),
        label: Text('admin.admin_images_screen.newCategory'.tr(),
            style: const TextStyle(
                color: AppColors.onPrimary, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _EmptyCategories extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyCategories({required this.onTap});

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
                Text('admin.admin_images_screen.noCategoriesTitle'.tr(),
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                const SizedBox(height: AppSpacing.sm + 2),
                Text(
                    'admin.admin_images_screen.noCategoriesSubtitle'.tr(),
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
                  label: Text('admin.admin_images_screen.createFirstCategory'.tr(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ]),
        ),
      );
}