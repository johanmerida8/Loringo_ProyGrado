// lib/components/responsive_scaffold.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/components/app_drawer.dart';
import 'package:loringo_app/theme/app_theme.dart';

const double kWideBreakpoint = 900;
const double kSidePanelWidth = 280;

/// Scaffold that shows [AppDrawer] as a permanent side panel on wide
/// (web/desktop) layouts, and as a normal tap-to-open Drawer on narrow
/// (phone) layouts. Pass [navItems] built with the `isWide` flag so
/// on-tap behavior (auto-close) differs correctly between the two modes.
class ResponsiveScaffold extends StatelessWidget {
  final IconData headerIcon;
  final String drawerTitle;
  final String? drawerSubtitle;
  final List<Widget> Function(BuildContext context, bool isWide) navItemsBuilder;
  final Widget Function(BuildContext context, bool isWide) bodyBuilder;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final bool hideBottomNavOnWide;

  // Student-specific
  final bool isStudent;
  final String? studentId;
  final String? studentAvatar;
  final void Function(String newAvatar)? onAvatarUpdated;

  // Parent-specific
  // final bool isParent;
  final String? parentName;
  final String? parentEmail;
  final VoidCallback? onParentLogout;
  final VoidCallback? onParentDeleteAccount;

  const ResponsiveScaffold({
    super.key,
    required this.drawerTitle,
    required this.navItemsBuilder,
    required this.bodyBuilder,
    this.headerIcon = Icons.school,
    this.drawerSubtitle,
    this.floatingActionButton,
    this.appBar,
    this.bottomNavigationBar,
    this.hideBottomNavOnWide = true,
    this.isStudent = false,
    this.studentId,
    this.studentAvatar,
    this.onAvatarUpdated,
    // this.isParent = false,
    this.parentName,
    this.parentEmail,
    this.onParentLogout,
    this.onParentDeleteAccount,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= kWideBreakpoint;

        return Scaffold(
          backgroundColor: AppColors.scaffoldBackground,
          appBar: appBar,
          drawer: isWide
              ? null
              : AppDrawer(
                  headerIcon: headerIcon,
                  title: drawerTitle,
                  subtitle: drawerSubtitle,
                  navItems: navItemsBuilder(context, false),
                  isStudent: isStudent,
                  studentId: studentId,
                  studentAvatar: studentAvatar,
                  onAvatarUpdated: onAvatarUpdated,
                  // isParent: isParent,
                  parentName: parentName,
                  parentEmail: parentEmail,
                  onParentLogout: onParentLogout,
                  onParentDeleteAccount: onParentDeleteAccount,
                ),
          floatingActionButton: floatingActionButton,
          bottomNavigationBar:
              (isWide && hideBottomNavOnWide) ? null : bottomNavigationBar,
          body: SafeArea(
            child: Row(
              children: [
                if (isWide)
                  SizedBox(
                    width: kSidePanelWidth,
                    child: Material(
                      elevation: 1,
                      color: Colors.white,
                      child: AppDrawer(
                        headerIcon: headerIcon,
                        title: drawerTitle,
                        subtitle: drawerSubtitle,
                        navItems: navItemsBuilder(context, true),
                        wrapInDrawer: false,
                        isStudent: isStudent,
                        studentId: studentId,
                        studentAvatar: studentAvatar,
                        onAvatarUpdated: onAvatarUpdated,
                        // isParent: isParent,
                        parentName: parentName,
                        parentEmail: parentEmail,
                        onParentLogout: onParentLogout,
                        onParentDeleteAccount: onParentDeleteAccount,
                      ),
                    ),
                  ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1400),
                      child: SizedBox.expand(
                        child: bodyBuilder(context, isWide),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}