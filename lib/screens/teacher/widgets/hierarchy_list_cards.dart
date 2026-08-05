// hierarchy_widgets.dart
// Shared UI primitives used by content_details, lesson_list,
// activity_list and task_list screens.
import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';

// ── Generic list card ─────────────────────────────────────────────────────────

class HierarchyListCard extends StatelessWidget {
  final int          order;
  final String       title;
  final String?      subtitle;
  final Widget?      badge;
  final Color        color;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Optional widget shown on the title row, between the title/subtitle
  /// column and the "⋮" menu — e.g. the Quiz status chip on a Unit or
  /// Lesson row.
  ///
  /// Kept generic (plain Widget, not e.g. a hard-coded "quiz" param) so
  /// this stays a dumb primitive shared by every hierarchy screen
  /// (content/unit/lesson/activity), the same reasoning as
  /// TeacherScreenHeader.trailing. This is deliberately NOT part of the
  /// "⋮" menu (see HierarchyPopupActions below, which stays Edit/Delete
  /// only): Edit/Delete act on the row's own identity (rename/remove this
  /// unit or lesson); a Quiz is a separate piece of educational content
  /// tied to the row, not a property of the row itself, so it gets its
  /// own always-visible control instead of being buried one tap deeper
  /// inside a menu that conceptually means something else.
  final Widget? trailingChip;

  const HierarchyListCard({
    super.key,
    required this.order,
    required this.title,
    required this.color,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.subtitle,
    this.badge,
    this.trailingChip,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md - 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.md),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 3))
          ],
        ),
        child: Row(
          children: [
            // Order badge
            Container(
              width: 44, height: 44,
              margin: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Center(
                child: Text(
                  '$order',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: color),
                ),
              ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.md - 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    if (badge != null) ...[
                      const SizedBox(height: 4),
                      badge!,
                    ] else if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500])),
                    ],
                  ],
                ),
              ),
            ),
            // Quiz chip (or any other card-specific control) — sits
            // beside the "⋮", not inside it.
            if (trailingChip != null) ...[
              trailingChip!,
              const SizedBox(width: AppSpacing.sm),
            ],
            // Actions
            HierarchyPopupActions(onEdit: onEdit, onDelete: onDelete),
            const SizedBox(width: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

// ── Popup menu (edit / delete) ────────────────────────────────────────────────

class HierarchyPopupActions extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const HierarchyPopupActions(
      {super.key, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'edit')   onEdit();
        if (v == 'delete') onDelete();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_outlined, color: Colors.blue, size: 18),
            SizedBox(width: AppSpacing.sm),
            Text('Edit'),
          ]),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
            const SizedBox(width: AppSpacing.sm),
            const Text('Delete'),
          ]),
        ),
      ],
      icon: Icon(Icons.more_vert_rounded, color: Colors.grey[400], size: 20),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md)),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class HierarchyEmptyState extends StatelessWidget {
  final IconData     icon;
  final String       title;
  final String       subtitle;
  final Color        color;
  final String       actionLabel;
  final VoidCallback onAction;

  const HierarchyEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 72, color: Colors.grey[300]),
            const SizedBox(height: AppSpacing.md),
            Text(title,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700])),
            const SizedBox(height: AppSpacing.sm),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton.icon(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md - 2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md)),
                elevation: 0,
              ),
              icon: const Icon(Icons.add),
              label: Text(actionLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}