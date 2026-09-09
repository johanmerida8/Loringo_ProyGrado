// admin_navigation_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/app_bottom_nav_bar.dart';
import 'package:loringo_app/components/responsive_scaffold.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/admin/admin_dashboard_screen.dart';
import 'package:loringo_app/screens/admin/admin_images_screen.dart';
import 'package:loringo_app/screens/admin/admin_profile_screen.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/widget/secured_screen.dart';

class AdminNavigationScreen extends StatefulWidget {
  const AdminNavigationScreen({super.key});

  @override
  State<AdminNavigationScreen> createState() => _AdminNavigationScreenState();
}

class _AdminNavigationScreenState extends State<AdminNavigationScreen> {
  int _currentIndex = 0;
  String _name = '';

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!mounted) return;
    setState(() {
      _name = (doc.data()?['name'] as String?) ?? '';
    });
  }

  // Rebuilt fresh on every build (not cached) so each tab always reflects
  // current state (e.g. _name once loaded) — same pattern student/parent
  // main screens use. Flutter's element reconciliation keeps each tab's
  // own State alive across rebuilds since type + position stay the same.
  List<Widget> _buildTabs() => [
        AdminDashboardScreen(name: _name),
        const AdminImagesScreen(),
        const AdminProfileScreen(),
      ];

  List<Widget> _buildNavItems(bool isWide) {
    return [
      const SizedBox(height: AppSpacing.sm),
      ListTile(
        leading: const Icon(Icons.dashboard_rounded, color: AppColors.primary),
        title: Text('admin.admin_navigation_screen.dashboard'.tr()),
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
        title: Text('admin.admin_navigation_screen.images'.tr()),
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
    context.watch<LocaleProvider>();
    return SecuredScreen(
      child: ResponsiveScaffold(
        headerIcon: Icons.admin_panel_settings,
        drawerTitle: 'admin.admin_navigation_screen.imageManagerTitle'.tr(),
        drawerSubtitle:
            _name.isNotEmpty ? _name : 'admin.admin_profile_screen.notSet'.tr(),
        hideBottomNavOnWide: true,
        navItemsBuilder: (context, isWide) => _buildNavItems(isWide),
        bottomNavigationBar: AppBottomNavBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          showLabels: false,
          items: [
            AppNavItem(
                icon: Icons.dashboard_rounded,
                label: 'admin.admin_navigation_screen.dashboard'.tr()),
            AppNavItem(
                icon: Icons.image, label: 'admin.admin_navigation_screen.images'.tr()),
            AppNavItem(icon: Icons.person_rounded, label: 'common.myProfile'.tr()),
          ],
        ),
        bodyBuilder: (context, isWide) => IndexedStack(
          index: _currentIndex,
          children: _buildTabs(),
        ),
      ),
    );
  }
}
