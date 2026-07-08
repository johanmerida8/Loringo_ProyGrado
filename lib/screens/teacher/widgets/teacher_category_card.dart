import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/screens/teacher/teacher_view_images_screen.dart';

// ── Teacher category card ─────────────────────────────────────────────────────

class TeacherCategoryCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final Database db;
  final void Function(String id, String name) onDelete;

  const TeacherCategoryCard(
      {super.key, required this.doc, required this.db, required this.onDelete});

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