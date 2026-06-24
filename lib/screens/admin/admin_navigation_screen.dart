// admin_navigation_screen.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/components/app_drawer.dart';
import 'package:loringo_app/screens/admin/admin_dashboard_screen.dart';
import 'package:loringo_app/screens/admin/admin_images_screen.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/widget/secured_screen.dart';

class AdminNavigationScreen extends StatefulWidget {
  const AdminNavigationScreen({super.key});

  @override
  State<AdminNavigationScreen> createState() => _AdminNavigationScreenState();
}

class _AdminNavigationScreenState extends State<AdminNavigationScreen> {
  int _currentIndex = 0;

  final List<Map<String, dynamic>> _navigationItems = [
    {
      'icon': Icons.dashboard_rounded,
      'label': 'Dashboard',
      'title': 'Admin Dashboard',
    },
    {
      'icon': Icons.image,
      'label': 'Images',
      'title': 'Manage Images',
    },
  ];

  Widget _getCurrentScreen() {
    switch (_currentIndex) {
      case 0:
        return const AdminDashboardScreen();
      case 1:
        return const AdminImagesScreen();
      default:
        return const AdminDashboardScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTitle = _navigationItems[_currentIndex]['title'] as String;

    return SecuredScreen(
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBackground,
        drawer: AppDrawer(
          headerIcon: Icons.admin_panel_settings,
          title: 'Image Manager',
          subtitle: 'Manage Educational Images',
          navItems: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: const [
                  Icon(Icons.dashboard, size: 16, color: AppColors.primary),
                  SizedBox(width: 6),
                  Text(
                    'ADMIN TOOLS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_rounded,
                  color: AppColors.primary),
              title: const Text('Dashboard'),
              trailing: _currentIndex == 0
                  ? const Icon(Icons.check_circle, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _currentIndex = 0);
                if (Navigator.canPop(context)) Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image, color: AppColors.primary),
              title: const Text('Images'),
              trailing: _currentIndex == 1
                  ? const Icon(Icons.check_circle, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _currentIndex = 1);
                if (Navigator.canPop(context)) Navigator.pop(context);
              },
            ),
          ],
        ),
        body: Builder(
          builder: (ctx) => SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Inline header ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Scaffold.of(ctx).openDrawer(),
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft(0.1),
                            borderRadius: BorderRadius.circular(AppRadii.md),
                          ),
                          child: const Icon(Icons.menu_rounded,
                              color: AppColors.primary, size: 22),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text(currentTitle, style: AppText.h1),
                    ],
                  ),
                ),
                Expanded(child: _getCurrentScreen()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}