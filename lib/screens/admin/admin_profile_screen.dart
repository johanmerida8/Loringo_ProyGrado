// admin_profile_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/edit_text_dialog.dart';
import 'package:loringo_app/providers/biometric_provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/admin/widgets/admin_screen_header.dart';
import 'package:loringo_app/screens/initials/reset_in_app_screen.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class AdminProfileScreen extends StatefulWidget {
  final bool showBackButton;

  const AdminProfileScreen({super.key, this.showBackButton = false});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  String _name = '';
  String _email = '';
  bool _loadingUser = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // BUGFIX: same root cause as TeacherProfileScreen. The existing
    // `if (mounted)` guard here did NOT fix the "setState() or
    // markNeedsBuild() called during build" crash — the widget WAS
    // mounted, that was never the problem. The problem is timing:
    // BiometricProvider.initialize() calls notifyListeners()
    // synchronously on entry (before its own first await), and this was
    // being called from _loadUser(), which runs from initState() — i.e.
    // still inside this widget's very first build. Provider then tries
    // to mark its InheritedWidget dirty mid-build, which Flutter
    // disallows.
    //
    // addPostFrameCallback defers the call until the first frame has
    // fully finished, which is the actual fix — not an additional
    // mounted check.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<BiometricProvider>().initialize(uid);
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

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final biometricProvider = context.watch<BiometricProvider>();
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFEFF6EE),
      body: SafeArea(
        child: _loadingUser
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : SingleChildScrollView(
                child: Column(children: [
                  _buildHeader(),
                  const SizedBox(height: AppSpacing.md),
                  _buildHeaderCard(),
                  const SizedBox(height: AppSpacing.md),
                  _buildMenuCard(biometricProvider, userId),
                  const SizedBox(height: AppSpacing.xl),
                ]),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
      child: Row(children: [
        if (widget.showBackButton) ...[
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
        ],
        Text('common.myProfile'.tr(), style: AppText.h1),
      ]),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
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
            child: const Icon(Icons.admin_panel_settings_rounded,
                color: Colors.white, size: 40),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
            _name.isNotEmpty
                ? _name
                : 'admin.admin_dashboard_screen.imageManager'.tr(),
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
          child: Text('admin.admin_dashboard_screen.imageManager'.tr(),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _buildMenuCard(BiometricProvider biometricProvider, String userId) {
    return Container(
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
          children: [
            _buildMenuItem(
              icon: Icons.person_outline_rounded,
              title: 'common.personalData'.tr(),
              subtitle: 'admin.admin_profile_screen.viewManageInfo'.tr(),
              onTap: () => _navigateToPersonalData(),
            ),
            const Divider(height: 1, indent: 56, endIndent: 16),
            _buildMenuItem(
              icon: Icons.security_rounded,
              title: 'common.security'.tr(),
              subtitle: 'admin.admin_profile_screen.biometricPasswordSettings'.tr(),
              onTap: () => _navigateToSecurity(),
            ),
            const Divider(height: 1, indent: 56, endIndent: 16),
            // _buildBiometricToggle(biometricProvider, userId),
            // const Divider(height: 1, indent: 56, endIndent: 16),
            _buildMenuItem(
              icon: Icons.logout_rounded,
              title: 'common.logout'.tr(),
              subtitle: 'common.signOut'.tr(),
              onTap: _showLogoutConfirmation,
              isDestructive: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: isDestructive ? Colors.red.shade50 : AppColors.primarySoft(0.1),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Icon(icon,
            color: isDestructive ? Colors.red : AppColors.primary, size: 22),
      ),
      title: Text(title,
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDestructive ? Colors.red : Colors.black87)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      onTap: onTap,
    );
  }

  // Widget _buildBiometricToggle(BiometricProvider provider, String userId) {
  //   if (provider.isLoading) {
  //     return const ListTile(
  //       leading: Icon(Icons.fingerprint, color: AppColors.primary),
  //       title: Text('Biometric Authentication'),
  //       trailing: SizedBox(
  //         width: 24,
  //         height: 24,
  //         child: CircularProgressIndicator(strokeWidth: 2),
  //       ),
  //     );
  //   }
    
  //   return SwitchListTile(
  //     secondary: const Icon(Icons.fingerprint, color: AppColors.primary),
  //     title: const Text('Biometric Authentication'),
  //     subtitle: Text(
  //       provider.isSupported
  //           ? 'Use ${provider.biometricTypeName} to verify your identity'
  //           : 'No biometrics enrolled on this device',
  //       style: const TextStyle(fontSize: 12),
  //     ),
  //     value: provider.isEnabled,
  //     activeColor: AppColors.primary,
  //     onChanged: provider.isSupported ? (value) => provider.toggle(context, userId) : null,
  //   );
  // }

  void _navigateToPersonalData() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          context.watch<LocaleProvider>();
          return StatefulBuilder(
            builder: (context, setLocalState) {
              _personalDataRefresh = setLocalState;
              return Scaffold(
                backgroundColor: const Color(0xFFEFF6EE),
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPersonalDataHeader(context),
                        const SizedBox(height: AppSpacing.lg),
                        _buildPersonalDataCard(),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    ).then((_) => _personalDataRefresh = null);
  }

  /// Forces the currently-pushed personal-data route to rebuild instantly
  /// when the name is edited — that route lives outside this widget's own
  /// subtree (it's a sibling under the Navigator), so setState() here alone
  /// doesn't reach it.
  void Function(void Function())? _personalDataRefresh;

  Widget _buildPersonalDataHeader(BuildContext context) {
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
      Text('common.personalData'.tr(), style: AppText.h1),
    ]);
  }

  Widget _buildPersonalDataCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        children: [
          _buildInfoRow(
              icon: Icons.badge_outlined,
              label: 'common.displayName'.tr(),
              value: _name.isNotEmpty
                  ? _name
                  : 'admin.admin_profile_screen.notSet'.tr(),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined,
                    size: 18, color: AppColors.primary),
                onPressed: _editName,
              )),
          const Divider(height: 1, indent: 40),
          _buildInfoRow(
              icon: Icons.email_outlined,
              label: 'common.emailAddress'.tr(),
              value: _email),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md - 2),
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
            ],
          ),
        ),
        if (trailing != null) trailing,
      ]),
    );
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
      _name = newName;
      _personalDataRefresh?.call(() {});
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('common.displayNameUpdate'.tr())),
      );
    }
  }

  void _navigateToSecurity() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const _AdminSecurityScreen(),
      ),
    );
  }
}

// Admin Security Screen
class _AdminSecurityScreen extends StatelessWidget {
  const _AdminSecurityScreen();

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
              _buildHeader(context),
              const SizedBox(height: AppSpacing.md),
              _buildPasswordCard(context),
              const SizedBox(height: AppSpacing.lg),
              _buildBiometricCard(context, biometricProvider, userId),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
      Text('common.security'.tr(), style: AppText.h1),
    ]);
  }

  Widget _buildPasswordCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('common.password'.tr(),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.lock_reset_outlined,
                    color: AppColors.primary, size: 22),
              ),
              title: Text('common.changePassword'.tr(),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              subtitle: Text('admin.admin_profile_screen.updateYourPassword'.tr(),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ResetInAppScreen(
                        header: AdminScreenHeader(
                            title: 'common.changePassword'.tr()))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBiometricCard(BuildContext context, BiometricProvider provider, String userId) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('common.biometricAuth'.tr(),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: provider.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary))
                  : provider.isSupported
                      ? SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(provider.biometricTypeName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 15)),
                          subtitle: Text('common.biometricSignIn'.tr()),
                          value: provider.isEnabled,
                          activeColor: AppColors.primary,
                          onChanged: (value) => provider.toggle(context, userId),
                        )
                      : Row(children: [
                          const Icon(Icons.fingerprint_outlined, size: 24, color: Colors.grey),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text('common.biometricsNotAvailable'.tr(),
                                style: const TextStyle(fontSize: 14, color: Colors.grey)),
                          ),
                        ]),
            ),
          ],
        ),
      ),
    );
  }
}