import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';

// ── Image tile ────────────────────────────────────────────────────────────────

class TeacherImageTile extends StatefulWidget {
  final Map<String, dynamic> image;
  final VoidCallback onDelete;

  const TeacherImageTile(
      {super.key, required this.image, required this.onDelete});

  @override
  State<TeacherImageTile> createState() => _TeacherImageTileState();
}

class _TeacherImageTileState extends State<TeacherImageTile> {
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