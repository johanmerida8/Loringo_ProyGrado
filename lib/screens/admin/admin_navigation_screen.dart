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

// Breakpoint above which the drawer becomes a permanent side panel.
const double _kWideBreakpoint = 900;
const double _kSidePanelWidth = 280;

class _AdminNavigationScreenState extends State<AdminNavigationScreen> {
  int _currentIndex = 0;

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

  List<Widget> _buildNavItems(bool isWide) {
    return [
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
        leading: const Icon(Icons.dashboard_rounded, color: AppColors.primary),
        title: const Text('Dashboard'),
        selected: _currentIndex == 0,
        selectedTileColor: AppColors.primarySoft(0.08),
        trailing: _currentIndex == 0
            ? const Icon(Icons.check_circle, color: AppColors.primary)
            : null,
        onTap: () {
          setState(() => _currentIndex = 0);
          if (!isWide && Navigator.canPop(context)) Navigator.pop(context);
        },
      ),
      ListTile(
        leading: const Icon(Icons.image, color: AppColors.primary),
        title: const Text('Images'),
        selected: _currentIndex == 1,
        selectedTileColor: AppColors.primarySoft(0.08),
        trailing: _currentIndex == 1
            ? const Icon(Icons.check_circle, color: AppColors.primary)
            : null,
        onTap: () {
          setState(() => _currentIndex = 1);
          if (!isWide && Navigator.canPop(context)) Navigator.pop(context);
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final currentTitle = _currentIndex == 0 ? 'Admin Dashboard' : 'Manage Images';

    return SecuredScreen(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= _kWideBreakpoint;

          return Scaffold(
            backgroundColor: AppColors.scaffoldBackground,
            drawer: isWide
                ? null
                : AppDrawer(
                    headerIcon: Icons.admin_panel_settings,
                    title: 'Image Manager',
                    subtitle: 'Manage Educational Images',
                    navItems: _buildNavItems(false),
                  ),
            body: SafeArea(
              child: Row(
                children: [
                  if (isWide)
                    SizedBox(
                      width: _kSidePanelWidth,
                      child: Material(
                        elevation: 1,
                        color: Colors.white,
                        child: AppDrawer(
                          headerIcon: Icons.admin_panel_settings,
                          title: 'Image Manager',
                          subtitle: 'Manage Educational Images',
                          navItems: _buildNavItems(true),
                          wrapInDrawer: false,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
                          child: Row(
                            children: [
                              if (!isWide)
                                Builder(
                                  builder: (ctx) => GestureDetector(
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
                                ),
                              if (!isWide) const SizedBox(width: AppSpacing.md),
                              Text(currentTitle, style: AppText.h1),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1400),
                              child: SizedBox.expand(child: _getCurrentScreen()),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}