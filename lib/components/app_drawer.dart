import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/initials/profile_screen.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// Reusable navigation drawer / sidebar shell.
///
/// Pass [navItems] to define all navigation options (ListTiles, Dividers, etc.).
/// Set [wrapInDrawer] to `false` for a plain Column used as a sidebar (admin).
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    this.headerIcon = Icons.school,
    required this.title,
    this.subtitle,
    this.navItems = const [],
    this.wrapInDrawer = true,
  });

  /// Icon inside the avatar circle.
  final IconData headerIcon;

  /// Bold title in the header (e.g. 'Teacher Panel').
  final String title;

  /// Optional subtitle shown below [title] (e.g. teacher name).
  final String? subtitle;

  /// Navigation content � any widgets: ListTiles, Dividers, section headers...
  final List<Widget> navItems;

  /// `true` ? Drawer wrapper (teacher); `false` ? raw Column (admin sidebar).
  final bool wrapInDrawer;

  // -- Header ----------------------------------------------------------------

  Widget _buildHeader(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      ),
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
                  child:
                      Icon(headerIcon, size: 40, color: AppColors.primary),
                ),
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit,
                      size: 14, color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'Tap to view profile',
              style: TextStyle(
                color: Colors.white.withOpacity(0.65),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -- Sign-out --------------------------------------------------------------

  Widget _buildSignOut(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey[300]!, width: 1)),
      ),
      child: ListTile(
        leading: const Icon(Icons.logout, color: Colors.red),
        title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
        onTap: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Sign Out'),
              content: const Text('Are you sure you want to sign out?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Sign Out'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await FirebaseAuth.instance.signOut();
            if (context.mounted) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const AuthGate()),
                (route) => false,
              );
            }
          }
        },
      ),
    );
  }

  // -- Build -----------------------------------------------------------------

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
        _buildSignOut(context),
      ],
    );

    return wrapInDrawer
        ? Drawer(backgroundColor: Colors.white, child: content)
        : content;
  }
}
