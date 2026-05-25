import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/teacher_theme.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_confirm_dialog.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';

class GroupDetailsDrawer extends StatelessWidget {
  const GroupDetailsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          const _Header(),
          const Divider(),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ListTile(
                  leading: const Icon(Icons.group, color: TeacherColors.primary),
                  title: const Text('My Groups'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
          const _SignOutTile(),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
      decoration: const BoxDecoration(
        gradient: TeacherDecorations.primaryGradient,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 35,
            backgroundColor: Colors.white,
            child: Icon(Icons.school, size: 40, color: TeacherColors.primary),
          ),
          const SizedBox(height: 12),
          const Text(
            'Teacher Panel',
            style: TextStyle(
              color: TeacherColors.onPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            email ?? 'No email',
            style: TextStyle(
              color: TeacherColors.onPrimary.withOpacity(0.8),
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _SignOutTile extends StatelessWidget {
  const _SignOutTile();

  Future<void> _signOut(BuildContext context) async {
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
        onTap: () => _signOut(context),
      ),
    );
  }
}
