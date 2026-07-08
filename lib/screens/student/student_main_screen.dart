import 'package:flutter/material.dart';
import 'package:loringo_app/components/app_bottom_nav_bar.dart';
import 'package:loringo_app/components/responsive_scaffold.dart';
import 'package:loringo_app/screens/student/student_activities_screen.dart';
import 'package:loringo_app/screens/student/student_league_screen.dart';
import 'package:loringo_app/screens/student/student_settings_screen.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/widget/secured_screen.dart';

class StudentMainScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String? studentAvatar;

  const StudentMainScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    this.studentAvatar,
  });

  @override
  State<StudentMainScreen> createState() => _StudentMainScreenState();
}

class _StudentMainScreenState extends State<StudentMainScreen> {
  int _currentIndex = 0;

  // Source of truth for the avatar — needed so the drawer header (web)
  // and StudentSettingsTab (mobile bottom nav) both reflect the same
  // value no matter which one triggers a change.
  late String _currentAvatar;

  late final List<Widget> _tabs;

  static const int _settingsIndex = 2;

  @override
  void initState() {
    super.initState();
    _currentAvatar = widget.studentAvatar ?? '';
    _tabs = [
      StudentActivitiesTab(
        studentId: widget.studentId,
        studentName: widget.studentName,
        studentAvatar: _currentAvatar,
      ),
      StudentLeagueTab(
        studentId: widget.studentId,
        studentName: widget.studentName,
      ),
      StudentSettingsTab(
        studentId: widget.studentId,
        studentName: widget.studentName,
        studentAvatar: _currentAvatar,
        showBackButton: false,
      ),
    ];
  }

  void _onAvatarUpdated(String newAvatar) {
    setState(() => _currentAvatar = newAvatar);
  }

  @override
  Widget build(BuildContext context) {
    return SecuredScreen(
      isStudent: true,
      child: ResponsiveScaffold(
        headerIcon: Icons.emoji_people_rounded,
        drawerTitle: 'Loringo',
        drawerSubtitle: widget.studentName,
        hideBottomNavOnWide: true,
        isStudent: true,
        studentId: widget.studentId,
        studentAvatar: _currentAvatar,
        onAvatarUpdated: _onAvatarUpdated,
        // Web (isWide): Home + League only — Settings is reached via the
        // avatar tap in the drawer header instead.
        // Mobile (!isWide): this list isn't even used, since the drawer
        // itself is replaced by the bottom nav bar for narrow layouts —
        // kept here anyway for the rare case the OS-level drawer swipe
        // gesture opens it, so it still shows something sensible.
        navItemsBuilder: (context, isWide) => [
          ListTile(
            leading: const Icon(Icons.home_rounded, color: AppColors.primary),
            title: const Text('Home'),
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
            leading: const Icon(Icons.emoji_events_rounded, color: AppColors.primary),
            title: const Text('League'),
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
          // Settings intentionally omitted here — web users reach it via
          // the drawer's avatar tap (AppDrawer + isStudent handles this).
          if (!isWide) ...[
            ListTile(
              leading: const Icon(Icons.settings_rounded, color: AppColors.primary),
              title: const Text('Settings'),
              selected: _currentIndex == _settingsIndex,
              selectedTileColor: AppColors.primarySoft(0.08),
              trailing: _currentIndex == _settingsIndex
                  ? const Icon(Icons.check_circle, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _currentIndex = _settingsIndex);
                if (Navigator.canPop(context)) Navigator.pop(context);
              },
            ),
          ],
        ],
        // Mobile bottom bar — unchanged, still 3 tabs including Settings.
        bottomNavigationBar: AppBottomNavBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            AppNavItem(icon: Icons.home_rounded, label: 'Home'),
            AppNavItem(icon: Icons.emoji_events_rounded, label: 'League'),
            AppNavItem(icon: Icons.settings_rounded, label: 'Settings'),
          ],
        ),
        bodyBuilder: (context, isWide) => Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE8F5E9), Colors.white],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: IndexedStack(
            index: _currentIndex,
            children: _tabs,
          ),
        ),
      ),
    );
  }
}