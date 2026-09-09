import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/image_service.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_category_card.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_empty_state.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';

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
          Text('teacher.teacher_image_screen.newCategory'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'teacher.teacher_image_screen.categoryNameLabel'.tr(),
              hintText: 'teacher.teacher_image_screen.categoryNameHint'.tr(),
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
                    ownerId:      FirebaseAuth.instance.currentUser!.uid,
                    ownerRole:    'teacher');
                if (context.mounted) {
                  _showSuccessSnackBar(context,
                      'teacher.teacher_image_screen.categoryCreated'
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
          Text('teacher.teacher_image_screen.deleteCategory'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: RichText(
            text: TextSpan(
                style: const TextStyle(
                    fontSize: 14, color: Colors.black87, height: 1.5),
                children: [
              TextSpan(text: 'teacher.teacher_image_screen.deletePrefix'.tr()),
              TextSpan(
                  text: '"$categoryName"',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: 'teacher.teacher_image_screen.deleteSuffix'.tr()),
              TextSpan(
                  text: 'teacher.teacher_image_screen.cannotBeUndone'.tr(),
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
            'teacher.teacher_image_screen.categoryDeleted'
                .tr(namedArgs: {'name': categoryName}));
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackBar(context,
            'common.errorWithMessage'.tr(namedArgs: {'error': '$e'}));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final db  = Database();
    final uid = _uid;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
              title: 'teacher.teacher_image_screen.title'.tr()),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: db.getTeacherCategoriesStream(uid),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary));
                }
                final docs = snap.data?.docs ?? [];

                if (docs.isEmpty) {
                  return TeacherEmptyState(
                      onTap: () => _showCreateDialog(context));
                }

                return CustomScrollView(
                  slivers: [
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
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      'teacher.teacher_image_screen.categoryCount'
                                          .plural(docs.length),
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: AppColors.onPrimary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 17)),
                                  Text(
                                      'teacher.teacher_image_screen.tapCategoryHint'
                                          .tr(),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12)),
                                ]),
                          ),
                          const SizedBox(width: AppSpacing.sm),
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
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md, AppSpacing.sm,
                          AppSpacing.md, 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => TeacherCategoryCard(
                            doc:      docs[i],
                            db:       db,
                            onDelete: (id, name) =>
                                _deleteCategory(context, db, uid, id, name),
                          ),
                          childCount: docs.length,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'categories_fab',
        onPressed: () => _showCreateDialog(context),
        backgroundColor: AppColors.primary,
        elevation: 3,
        icon: const Icon(Icons.create_new_folder_rounded,
            color: AppColors.onPrimary),
        label: Text('teacher.teacher_image_screen.newCategory'.tr(),
            style: const TextStyle(
                color: AppColors.onPrimary,
                fontWeight: FontWeight.bold)),
      ),
    );
  }
}