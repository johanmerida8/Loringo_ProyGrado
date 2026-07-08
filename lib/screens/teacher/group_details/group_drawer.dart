import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_confirm_dialog.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:loringo_app/theme/app_theme.dart';

class GroupDetailsDrawer extends StatelessWidget {
  const GroupDetailsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: Column(
        children: [
          const _Header(),
          const Divider(height: 1, color: AppColors.divider),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ListTile(
                  leading: const Icon(Icons.group, color: AppColors.primary),
                  title: const Text('My Groups', style: AppText.listTitle),
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
      decoration: const BoxDecoration(gradient: AppDecorations.primaryGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                radius: 35,
                backgroundColor: AppColors.onPrimary,
                child: Icon(Icons.school, size: 40, color: AppColors.primary),
              ),
              const SizedBox(height: AppSpacing.md - 4),
              const Text('Teacher Panel', style: AppText.appBarTitle),
              const SizedBox(height: AppSpacing.xs),
              Text(
                email ?? 'No email',
                style: TextStyle(
                  color: AppColors.onPrimary.withOpacity(0.8),
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
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
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: ListTile(
        leading: const Icon(Icons.logout, color: AppColors.danger),
        title: const Text('Sign Out', style: AppText.listTitle),
        onTap: () => _signOut(context),
      ),
    );
  }
}