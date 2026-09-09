import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// A nav item descriptor for [AppBottomNavBar].
class AppNavItem {
  const AppNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// Pill-shaped floating bottom navigation bar used across the whole app
/// (teacher, student, admin). Styling matches the original teacher design.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.color = AppColors.primary,
    this.showLabels = true,
  });

  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Background fill colour of the pill. Defaults to [AppColors.primary].
  final Color color;

  /// Whether the selected tab shows its label under the icon. Defaults to
  /// true (existing behavior). Set false for an icon-only bar.
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      height: 70,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(35),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            offset: const Offset(0, 8),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < items.length; i++)
            _NavItemView(
              item: items[i],
              isSelected: i == currentIndex,
              onTap: () => onTap(i),
              showLabel: showLabels,
            ),
        ],
      ),
    );
  }
}

class _NavItemView extends StatelessWidget {
  const _NavItemView({
    required this.item,
    required this.isSelected,
    required this.onTap,
    this.showLabel = true,
  });

  final AppNavItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16 : 8,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.icon,
              color: Colors.white,
              size: isSelected ? 28 : 24,
            ),
            if (isSelected && showLabel) ...[
              const SizedBox(height: 2),
              Text(
                item.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
