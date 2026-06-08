import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/teacher_theme.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_confirm_dialog.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';

class TeacherAppDrawer extends StatelessWidget {
  const TeacherAppDrawer({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          const _DrawerHeader(),
          const Divider(),
          const _NavSectionLabel(label: 'Navigation'),
          _DrawerNavTile(
            icon: Icons.group,
            title: 'My Groups',
            selected: currentIndex == 0,
            onTap: () => _selectTab(context, 0),
          ),
          _DrawerNavTile(
            icon: Icons.assignment,
            title: 'Assign Units',
            selected: currentIndex == 1,
            onTap: () => _selectTab(context, 1),
          ),
          _DrawerNavTile(
            icon: Icons.analytics,
            title: 'Student Progress',
            selected: currentIndex == 2,
            onTap: () => _selectTab(context, 2),
          ),
          _DrawerNavTile(
            icon: Icons.settings,
            title: 'Settings',
            selected: currentIndex == 3,
            onTap: () => _selectTab(context, 3),
          ),
          const Spacer(),
          const _SignOutTile(),
        ],
      ),
    );
  }

  void _selectTab(BuildContext context, int index) {
    onTabSelected(index);
    Navigator.pop(context);
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
      decoration: const BoxDecoration(
        gradient: TeacherDecorations.primaryGradient,
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 35,
            backgroundColor: Colors.white,
            child: Icon(Icons.school, size: 40, color: TeacherColors.primary),
          ),
          SizedBox(height: TeacherSpacing.md - 4),
          Text(
            'Teacher Panel',
            style: TextStyle(
              color: TeacherColors.onPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: TeacherSpacing.xs),
          Text(
            'Classroom Management',
            style: TextStyle(
              color: TeacherColors.onPrimary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavSectionLabel extends StatelessWidget {
  const _NavSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: [
          const Icon(Icons.dashboard, size: 18, color: TeacherColors.primary),
          const SizedBox(width: TeacherSpacing.sm),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: TeacherColors.primary,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerNavTile extends StatelessWidget {
  const _DrawerNavTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: TeacherColors.primary),
      title: Text(title),
      trailing: selected
          ? const Icon(Icons.check_circle, color: TeacherColors.primary)
          : null,
      onTap: onTap,
    );
  }
}

class _SignOutTile extends StatelessWidget {
  const _SignOutTile();

  Future<void> _handleSignOut(BuildContext context) async {
    final confirmed = await showTeacherConfirmDialog(
      context: context,
      title: 'Sign Out',
      message: 'Are you sure you want to sign out?',
      confirmLabel: 'Sign Out',
      cancelLabel: 'Cancel',
    );

    if (!confirmed) return;

    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: TeacherColors.divider)),
      ),
      child: ListTile(
        leading: const Icon(Icons.logout, color: TeacherColors.danger),
        title: const Text('Sign Out'),
        onTap: () => _handleSignOut(context),
      ),
    );
  }
}