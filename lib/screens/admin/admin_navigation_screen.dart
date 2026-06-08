// import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/components/adaptive_navigation_scaffold.dart';
import 'package:loringo_app/components/app_bottom_nav_bar.dart';
import 'package:loringo_app/components/app_drawer.dart';
import 'package:loringo_app/screens/admin/admin_approval_content_screen.dart';
import 'package:loringo_app/screens/admin/admin_dashboard_screen.dart';
import 'package:loringo_app/screens/admin/admin_images_screen.dart';
// import 'package:loringo_app/services/auth/auth_gate.dart';
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
      'icon': Icons.approval_rounded,
      'label': 'Approvals',
      'title': 'Content Approvals',
    },
    {
      'icon': Icons.image,
      'label': 'Images',
      'title': 'Manage Images',
    },
    // {
    //   'icon': Icons.settings_rounded,
    //   'label': 'Settings',
    //   'title': 'Settings',
    // },
  ];

  Widget _getCurrentScreen() {
    switch (_currentIndex) {
      case 0:
        return const AdminDashboardScreen();
      case 1:
        return const ContentApprovalScreen();
      case 2:
        return AdminImagesScreen();
      // case 3:
      //   return _buildSettingsScreen();
      default:
        return const AdminDashboardScreen();
    }
  }

  Widget _buildSidebarContent() {
    return AppDrawer(
      wrapInDrawer: false,
      headerIcon: Icons.admin_panel_settings,
      title: 'Admin Panel',
      subtitle: 'System Oversight',
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
          leading: const Icon(Icons.approval_rounded,
              color: AppColors.primary),
          title: const Text('Content Approvals'),
          trailing: _currentIndex == 1
              ? const Icon(Icons.check_circle, color: AppColors.primary)
              : null,
          onTap: () {
            setState(() => _currentIndex = 1);
            if (Navigator.canPop(context)) Navigator.pop(context);
          },
        ),
        ListTile(
          leading: const Icon(Icons.image, color: AppColors.primary),
          title: const Text('Images'),
          trailing: _currentIndex == 2
              ? const Icon(Icons.check_circle, color: AppColors.primary)
              : null,
          onTap: () {
            setState(() => _currentIndex = 2);
            if (Navigator.canPop(context)) Navigator.pop(context);
          },
        ),
      ],
    );
  }

  Widget _buildBottomNavigationBar() {
    return AppBottomNavBar(
      currentIndex: _currentIndex,
      onTap: (index) => setState(() => _currentIndex = index),
      items: _navigationItems
          .map((e) => AppNavItem(
                icon: e['icon'] as IconData,
                label: e['label'] as String,
              ))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentTitle = _navigationItems[_currentIndex]['title'] as String;

    return SecuredScreen(
      child: AdaptiveNavigationScaffold(
        title: currentTitle,
        appBarColor: AppColors.primary,
        sidebarContent: _buildSidebarContent(),
        body: _getCurrentScreen(),
        floatingActionButton: null,
        bottomNavigatorBar: _buildBottomNavigationBar(),
      ),
    );
  }
}