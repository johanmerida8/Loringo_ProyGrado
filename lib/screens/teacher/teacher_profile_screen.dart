// teacher_profile_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/edit_text_dialog.dart';
import 'package:loringo_app/providers/biometric_provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/providers/notification_provider.dart';
import 'package:loringo_app/screens/initials/reset_in_app_screen.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:loringo_app/services/auth/identity_confirmation.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class TeacherProfileScreen extends StatefulWidget {
  const TeacherProfileScreen({super.key});

  @override
  State<TeacherProfileScreen> createState() => _TeacherProfileScreenState();
}

class _TeacherProfileScreenState extends State<TeacherProfileScreen>
    with WidgetsBindingObserver {
  String _name = '';
  String _email = '';
  bool _loadingUser = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUser();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<NotificationProvider>().refresh();
    }
  }

  Future<void> _loadUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // BUGFIX: BiometricProvider.initialize() and
    // NotificationProvider.initialize() each call notifyListeners()
    // immediately on entry (before their own first `await`), to flip
    // isLoading to true right away. Calling them directly here — inside
    // initState()'s synchronous call chain via _loadUser() — means that
    // first notifyListeners() fires WHILE this widget's very first build
    // is still in progress. Provider's InheritedWidget then tries to
    // mark itself dirty mid-build, which throws "setState() or
    // markNeedsBuild() called during build" (this is the exact crash in
    // the logs, with the stack trace running straight through
    // initState -> _loadUser -> BiometricProvider.initialize ->
    // notifyListeners).
    //
    // addPostFrameCallback defers both calls until after the first frame
    // has finished building, which is the standard fix for "notify a
    // listener as a side effect of initState" — by then Flutter is no
    // longer in the build phase, so notifyListeners() can safely mark
    // dependents dirty for the *next* frame instead of the current one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<BiometricProvider>().initialize(uid);
      context.read<NotificationProvider>().initialize(uid);
    });

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    
    if (!mounted) return;
    setState(() {
      _name = (doc.data()?['name'] as String?) ?? '';
      _email = (doc.data()?['email'] as String?) ??
          FirebaseAuth.instance.currentUser?.email ?? '';
      _loadingUser = false;
    });
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text('common.logout'.tr()),
        content: Text('common.logoutMsg'.tr()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('common.cancel'.tr(),
                  style: const TextStyle(color: AppColors.muted))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthGate()),
                  (r) => false,
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.warning),
            child: Text('common.logout'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToPersonalData() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PersonalDataScreen(name: _name, email: _email),
      ),
    );
    _loadUser();
  }

  void _navigateToSecurity() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SecurityScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final biometricProvider = context.watch<BiometricProvider>();
    final notificationProvider = context.watch<NotificationProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFEFF6EE),
      body: SafeArea(
        child: _loadingUser
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : SingleChildScrollView(
                child: Column(
                  children: [
                    _buildHeader(),
                    const SizedBox(height: AppSpacing.md),
                    _ProfileHeader(
                        name: _name,
                        role: 'common.teacher'.tr(),
                        icon: Icons.school_rounded),
                    const SizedBox(height: AppSpacing.md),
                    _MenuCard(
                      children: [
                        _MenuTile(
                          item: _MenuItem(
                            icon: Icons.person_outline_rounded,
                            title: 'common.personalData'.tr(),
                            subtitle: 'teacher.teacher_profile_screen.viewManageInfo'.tr(),
                            onTap: _navigateToPersonalData,
                          ),
                        ),
                        _MenuTile(
                          item: _MenuItem(
                            icon: Icons.security_rounded,
                            title: 'common.security'.tr(),
                            subtitle: 'teacher.teacher_profile_screen.biometricPasswordSettings'.tr(),
                            onTap: _navigateToSecurity,
                          ),
                        ),
                        _MenuTile(
                          item: _MenuItem(
                            icon: Icons.notifications_active_rounded,
                            title: 'common.notifications'.tr(),
                            subtitle: 'teacher.teacher_profile_screen.notifSubtitle'.tr(),
                            trailing: notificationProvider.isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.primary))
                                : Switch(
                                    value: notificationProvider.isEnabled,
                                    onChanged: (value) async {
                                      if (value) {
                                        await notificationProvider
                                            .enableNotifications(context);
                                      } else {
                                        await notificationProvider
                                            .disableNotifications(context);
                                      }
                                      if (mounted) {
                                        setState(() {});
                                      }
                                    },
                                    activeColor: AppColors.primary,
                                  ),
                            onTap: () async {
                              if (notificationProvider.isEnabled) {
                                await notificationProvider
                                    .disableNotifications(context);
                              } else {
                                await notificationProvider
                                    .enableNotifications(context);
                              }
                              if (mounted) {
                                setState(() {});
                              }
                            },
                          ),
                        ),
                        _MenuTile(
                          item: _MenuItem(
                            icon: Icons.logout_rounded,
                            title: 'common.logout'.tr(),
                            subtitle: 'common.signOut'.tr(),
                            onTap: _showLogoutConfirmation,
                            isDestructive: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.primarySoft(0.1),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.primary, size: 18),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Text('common.myProfile'.tr(), style: AppText.h1),
      ]),
    );
  }
}

// Profile Header Widget
class _ProfileHeader extends StatelessWidget {
  final String name;
  final String role;
  final IconData icon;
  const _ProfileHeader(
      {required this.name, required this.role, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.xl, horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: AppDecorations.primaryGradient,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.25),
              offset: const Offset(0, 6),
              blurRadius: 16,
            ),
          ],
        ),
        child: Column(children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: CircleAvatar(
              radius: 44,
              backgroundColor: Colors.white.withOpacity(0.25),
              child: Icon(icon, color: Colors.white, size: 40),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(name.isNotEmpty ? name : role,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(role,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

// Menu Card Widget
class _MenuCard extends StatelessWidget {
  final List<Widget> children;
  const _MenuCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: List.generate(children.length, (i) {
              final isLast = i == children.length - 1;
              return Column(children: [
                children[i],
                if (!isLast) const Divider(height: 1, indent: 56, endIndent: 16),
              ]);
            }),
          ),
        ),
      );
}

class _MenuItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;
  final Widget? trailing;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
    this.trailing,
  });
}

class _MenuTile extends StatelessWidget {
  final _MenuItem item;
  const _MenuTile({required this.item});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: item.isDestructive
                ? Colors.red.shade50
                : AppColors.primarySoft(0.1),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Icon(item.icon,
              color: item.isDestructive ? Colors.red : AppColors.primary,
              size: 22),
        ),
        title: Text(item.title,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: item.isDestructive ? Colors.red : Colors.black87)),
        subtitle: Text(item.subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: item.trailing ??
            const Icon(Icons.chevron_right_rounded, color: Colors.grey),
        onTap: item.onTap,
      );
}

// Personal Data Screen
class _PersonalDataScreen extends StatefulWidget {
  final String name;
  final String email;
  const _PersonalDataScreen({required this.name, required this.email});

  @override
  State<_PersonalDataScreen> createState() => _PersonalDataScreenState();
}

class _PersonalDataScreenState extends State<_PersonalDataScreen> {
  late String _name = widget.name;

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Scaffold(
      backgroundColor: const Color(0xFFEFF6EE),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildHeader(context, 'common.personalData'.tr()),
            const SizedBox(height: AppSpacing.lg),
            _SectionCard(
              title: 'common.accountInfo'.tr(),
              children: [
                _InfoRow(
                    icon: Icons.badge_outlined,
                    label: 'common.displayName'.tr(),
                    value: _name.isNotEmpty
                        ? _name
                        : 'teacher.teacher_profile_screen.notSet'.tr(),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          size: 18, color: AppColors.primary),
                      onPressed: _editName,
                    )),
                const Divider(height: 1, indent: 40),
                _InfoRow(
                    icon: Icons.email_outlined,
                    label: 'common.emailAddress'.tr(),
                    value: widget.email),
                const Divider(height: 1, indent: 40),
                _buildDeleteAccountRow(),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildDeleteAccountRow() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('common.deleteAccount'.tr(),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                Text('common.deletePermAcc'.tr(),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          TextButton(
            onPressed: _deleteAccount,
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('common.delete'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Deletes the teacher's account. Blocked while any of their groups is
  /// still active (not archived) — a teacher must archive every group
  /// first, since deleting cascades the group itself and every student's
  /// progress/reports under it (see Database.deleteTeacherOwnedData),
  /// unlike a parent's cascade which only ever touches their own
  /// children. Student profiles themselves are never deleted here — only
  /// their history under this teacher's groups.
  Future<void> _deleteAccount() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final groupsSnap = await FirebaseFirestore.instance
        .collection('teacherGroups')
        .where('teacherId', isEqualTo: uid)
        .get();
    final hasActiveGroup =
        groupsSnap.docs.any((doc) => doc.data()['archived'] != true);
    if (hasActiveGroup) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.lg)),
            title: Text(
                'teacher.teacher_profile_screen.activeGroupsBlockTitle'.tr()),
            content: Text(
                'teacher.teacher_profile_screen.activeGroupsBlockMsg'.tr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('common.ok'.tr()),
              ),
            ],
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('common.deleteAccount'.tr()),
        content: Text('teacher.teacher_profile_screen.deleteAccMsg'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('common.delete'.tr(),
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Confirm a genuinely fresh sign-in BEFORE touching any data — see
    // the matching comment in parent_navigation_screen.dart::_deleteAccount.
    if (!mounted) return;
    final reauthenticated = await reauthenticateWithPassword(context);
    if (!reauthenticated || !mounted) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await Database().deleteTeacherOwnedData(uid);
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      await user.delete();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.code == 'requires-recent-login'
                  ? 'common.requiresRecentLogin'.tr()
                  : 'common.errorWithMessage'.tr(namedArgs: {'error': e.message ?? e.code})),
              backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('common.errorWithMessage'.tr(namedArgs: {'error': '$e'})),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildHeader(BuildContext context, String title) {
    return Row(children: [
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.primarySoft(0.1),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.primary, size: 18),
        ),
      ),
      const SizedBox(width: AppSpacing.md),
      Text(title, style: AppText.h1),
    ]);
  }

  Future<void> _editName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final newName = await showEditTextDialog(
      context,
      title: 'common.displayName'.tr(),
      initialValue: _name,
      onSave: (value) => Database().updateUser(uid: uid, name: value),
    );

    if (newName != null && mounted) {
      setState(() => _name = newName);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('common.displayNameUpdate'.tr())),
      );
    }
  }
}

// Security Screen
class _SecurityScreen extends StatelessWidget {
  const _SecurityScreen();

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final biometricProvider = context.watch<BiometricProvider>();
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFEFF6EE),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, 'common.security'.tr()),
              const SizedBox(height: AppSpacing.md),
              // Password Section
              _SectionCard(
                title: 'common.password'.tr(),
                children: [
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft(0.1),
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: const Icon(Icons.lock_reset_outlined,
                          color: AppColors.primary, size: 22),
                    ),
                    title: Text('common.changePassword'.tr(),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    subtitle: Text('teacher.teacher_profile_screen.updateYourPassword'.tr(),
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: Colors.grey),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ResetInAppScreen(
                                header: TeacherScreenHeader(
                                    title: 'common.changePassword'.tr())))),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              // Biometric Section
              _SectionCard(
                title: 'common.biometricAuth'.tr(),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: biometricProvider.isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.primary))
                        : biometricProvider.isSupported
                            ? SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(biometricProvider.biometricTypeName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15)),
                                subtitle: Text('common.biometricSignIn'.tr()),
                                value: biometricProvider.isEnabled,
                                activeColor: AppColors.primary,
                                onChanged: (value) =>
                                    biometricProvider.toggle(context, userId),
                              )
                            : Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Row(children: [
                                  const Icon(Icons.fingerprint_outlined,
                                      size: 24, color: Colors.grey),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      'common.biometricsNotAvailable'.tr(),
                                      style: const TextStyle(
                                          fontSize: 14, color: Colors.grey),
                                    ),
                                  ),
                                ]),
                              ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String title) {
    return Row(children: [
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.primarySoft(0.1),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.primary, size: 18),
        ),
      ),
      const SizedBox(width: AppSpacing.md),
      Text(title, style: AppText.h1),
    ]);
  }
}

// Section Card Widget
class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ...children,
          ]),
        ),
      );
}

// Info Row Widget
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;
  const _InfoRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md - 2),
        child: Row(children: [
          Icon(icon, size: 20, color: AppColors.primarySoft(0.7)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87)),
                ]),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}