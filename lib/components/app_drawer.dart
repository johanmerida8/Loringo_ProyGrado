// lib/components/app_drawer.dart
//
// Reads the current user's Firestore role and routes the header tap to:
//   teacher → TeacherProfileScreen
//   admin   → AdminProfileScreen
//   parent  → ParentProfileScreen  (via its existing call-site in parent_home_screen)
//   other   → legacy ProfileScreen (fallback)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/admin/admin_profile_screen.dart';
import 'package:loringo_app/screens/teacher/teacher_profile_screen.dart' hide AdminProfileScreen;
import 'package:loringo_app/screens/initials/profile_screen.dart' hide TeacherProfileScreen, AdminProfileScreen;
import 'package:loringo_app/theme/app_theme.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    this.headerIcon = Icons.school,
    required this.title,
    this.subtitle,
    this.navItems = const [],
    this.wrapInDrawer = true,
  });

  final IconData headerIcon;
  final String title;
  final String? subtitle;
  final List<Widget> navItems;
  final bool wrapInDrawer;

  // ── Navigate to the role-appropriate profile screen ───────────────────────

  Future<void> _openProfile(BuildContext context) async {
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
    }
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
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
                  child: Icon(headerIcon, size: 40, color: AppColors.primary),
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
            Text('Tap to view profile',
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