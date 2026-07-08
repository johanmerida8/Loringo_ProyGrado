// lib/screens/teacher/widgets/hierarchy_breadcrumb.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// Persistent trail shown under a hierarchy list screen's AppBar so the
/// teacher always knows which Content > Unit > Lesson > Activity they're
/// inside, and can jump back to any ancestor in one tap instead of
/// retracing every screen.
class HierarchyBreadcrumb extends StatelessWidget {
  const HierarchyBreadcrumb({
    super.key,
    required this.items,
    required this.color,
  });

  /// Full trail from the top-level Content title down to the current
  /// screen's own title. The last item is the current screen and is
  /// rendered as non-tappable.
  final List<String> items;
  final Color color;

  void _jumpTo(BuildContext context, int levelsUp) {
    if (levelsUp <= 0) return;
    var popped = 0;
    Navigator.of(context).popUntil((route) {
      if (popped == levelsUp) return true;
      popped++;
      return false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (items.length <= 1) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: color.withOpacity(0.85),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(items.length * 2 - 1, (i) {
            if (i.isOdd) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.chevron_right, size: 16, color: Colors.white60),
              );
            }
            final index = i ~/ 2;
            final isCurrent = index == items.length - 1;
            final levelsUp = (items.length - 1) - index;
            return GestureDetector(
              onTap: isCurrent ? null : () => _jumpTo(context, levelsUp),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  items[index],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isCurrent ? Colors.white : Colors.white70,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                    fontSize: 12.5,
                    decoration: isCurrent ? null : TextDecoration.underline,
                    decorationColor: Colors.white54,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}