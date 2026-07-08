// lib/components/app_drawer.dart
//
// Reads the current user's Firestore role and routes the header tap to:
//   teacher → TeacherProfileScreen
//   admin   → AdminProfileScreen
//   parent  → ParentProfileScreen
//   student → StudentSettingsTab (same full screen used on mobile's
//             bottom-nav Settings tab — avatar picker + logout together,
//             consistent between mobile and web instead of a cramped
//             dialog)
//   other   → legacy ProfileScreen (fallback)
//
// Note on the student branch: students authenticate via access code, not
// FirebaseAuth, so they have no `role` document to look up at all — that
// branch is checked first and is the one genuine exception to "resolve
// everything from the role field".

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/admin/admin_profile_screen.dart';
import 'package:loringo_app/screens/parent/parent_profile_screen.dart';
import 'package:loringo_app/screens/student/student_settings_screen.dart';
import 'package:loringo_app/screens/teacher/teacher_profile_screen.dart';
import 'package:loringo_app/theme/app_theme.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    this.headerIcon = Icons.school,
    required this.title,
    this.subtitle,
    this.navItems = const [],
    this.wrapInDrawer = true,
    this.isStudent = false,
    this.studentId,
    this.studentName,
    this.studentAvatar,
    this.onAvatarUpdated,
    this.parentName,
    this.parentEmail,
    this.onParentLogout,
    this.onParentDeleteAccount,
  });

  final IconData headerIcon;
  final String title;
  final String? subtitle;
  final List<Widget> navItems;
  final bool wrapInDrawer;

  // Student-specific: students have no FirebaseAuth uid/role at all, so
  // this is the one case that can't be resolved by reading `role` below
  // — it has to be told explicitly.
  final bool isStudent;
  final String? studentId;
  final String? studentName;
  final String? studentAvatar;
  final void Function(String newAvatar)? onAvatarUpdated;

  // Parent-specific data — NOT a flag for "is this a parent" (that's
  // resolved from the `role` field like teacher/admin are). These are
  // only here so that when the switch below finds role == 'parent', it
  // can build ParentProfileScreen with data ParentNavigationScreen
  // already has in memory, instead of this widget re-fetching it.
  final String? parentName;
  final String? parentEmail;
  final VoidCallback? onParentLogout;
  final VoidCallback? onParentDeleteAccount;

  // ── Navigate to the role-appropriate profile screen ───────────────────────

  Future<void> _openProfile(BuildContext context) async {
    if (isStudent && studentId != null) {
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => StudentSettingsTab(
            studentId: studentId!,
            studentName: studentName ?? '',
            studentAvatar: studentAvatar ?? '',
            showBackButton: true,
          ),
        ),
      );
      if (result != null && onAvatarUpdated != null) {
        onAvatarUpdated!(result);
      }
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Fetch role from Firestore (cached in memory by Firestore SDK).
    String role = '';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(uid).get();
      role = (doc.data()?['role'] as String?) ?? '';
    } catch (_) {}

    if (!context.mounted) return;

    switch (role) {
      case 'teacher':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const TeacherProfileScreen()));
        break;
      case 'admin':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AdminProfileScreen()));
        break;
      case 'parent':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ParentProfileScreen(
              parentName: parentName ?? '',
              parentEmail: parentEmail ?? '',
              parentId: uid,
              onLogout: onParentLogout ?? () {},
              onDeleteAccount: onParentDeleteAccount ?? () {},
            ),
          ),
        );
        break;
    }
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    final hasStudentAvatar =
        isStudent && studentAvatar != null && studentAvatar!.isNotEmpty;

    return GestureDetector(
      onTap: () => _openProfile(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primaryLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 35,
                  backgroundColor: Colors.white,
                  child: hasStudentAvatar
                      ? ClipOval(
                          child: Image.asset(
                            studentAvatar!,
                            width: 70,
                            height: 70,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                                headerIcon, size: 40, color: AppColors.primary),
                          ),
                        )
                      : Icon(headerIcon, size: 40, color: AppColors.primary),
                ),
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.edit,
                      size: 14, color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold)),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subtitle!,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 15,
                      fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 6),
            Text(
                isStudent ? 'Tap to view settings' : 'Tap to view profile',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.65), fontSize: 11)),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        _buildHeader(context),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: navItems,
          ),
        ),
      ],
    );

    return wrapInDrawer
        ? Drawer(backgroundColor: Colors.white, child: content)
        : content;
  }
}