import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/edit_text_dialog.dart';
import 'package:loringo_app/providers/biometric_provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/providers/notification_provider.dart';
import 'package:loringo_app/screens/initials/reset_in_app_screen.dart';
import 'package:loringo_app/screens/parent/widgets/parent_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

class ParentProfileScreen extends StatefulWidget {
  final String parentName;
  final String parentEmail;
  final String? parentId;
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  const ParentProfileScreen({
    super.key,
    required this.parentName,
    required this.parentEmail,
    required this.parentId,
    required this.onLogout,
    required this.onDeleteAccount,
  });

  @override
  State<ParentProfileScreen> createState() => _ParentProfileScreenState();
}

class _ParentProfileScreenState extends State<ParentProfileScreen>
    with WidgetsBindingObserver {
  late String _displayName = widget.parentName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-checks the live OS permission state when the app resumes — e.g.
    // after the user manually flips notifications on/off from device
    // Settings (reached via the "permanently denied" flow) and comes back.
    // Without this, the toggle stays stale until something else happens to
    // trigger a rebuild, since nothing else re-queries the OS on return.
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<NotificationProvider>().refresh();
    }
  }

  void _navigateToSecurity() {
    Navigator.push(
      context, 
      MaterialPageRoute(builder: (_) => const _SecurityScreen()),
    );
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        title: Row(
          children: [
            Icon(Icons.logout, color: AppColors.danger, size: 28),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'common.logout'.tr(),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'common.logoutMsg'.tr(),
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: Text('common.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onLogout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: AppColors.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              elevation: 0,
            ),
            child: Text('common.logout'.tr()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Scaffold(
      backgroundColor: const Color(0xFFEFF6EE),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildProfileHeader(),
              const SizedBox(height: 16),
              _buildMenuCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.primarySoft(0.1), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary, size: 18),
            ),
          ),
          const SizedBox(width: 16),
          Text('common.myProfile'.tr(), style: AppText.h1),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(gradient: AppDecorations.primaryGradient, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          CircleAvatar(
            radius: 44,
            backgroundColor: Colors.white.withOpacity(0.25),
            child: Text(_displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'P', style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          Text(_displayName.isNotEmpty ? _displayName : 'common.parent'.tr(), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
            child: Text('common.parent'.tr(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
          _buildMenuItem(
            icon: Icons.person_outline_rounded,
            title: 'common.personalData'.tr(),
            subtitle: 'common.personalDataSubtitleParent'.tr(),
            onTap: () => _navigateToPersonalData(),
          ),
          _buildDivider(),
          _buildMenuItem(
            icon: Icons.security_rounded,
            title: 'common.security'.tr(),
            subtitle: 'common.securitySubtitleParent'.tr(),
            onTap: _navigateToSecurity,
          ),
          _buildDivider(),
          // Notification toggle using Provider
          Consumer<NotificationProvider>(
            builder: (context, notificationProvider, child) {
              return _buildMenuItem(
                icon: Icons.notifications_active_rounded,
                title: 'common.notifications'.tr(),
                subtitle: 'common.notificationSubtitleParent'.tr(),
                trailing: notificationProvider.isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Switch(
                        value: notificationProvider.isEnabled,
                        onChanged: (value) async {
                          if (value) {
                            await notificationProvider.enableNotifications(context);
                          } else {
                            await notificationProvider.disableNotifications(context);
                          }
                          if (mounted) {
                            setState(() {});
                          }
                        },
                        activeColor: AppColors.primary,
                      ),
                onTap: () async {
                  final notificationProvider = context.read<NotificationProvider>();
                  if (notificationProvider.isEnabled) {
                    await notificationProvider.disableNotifications(context);
                  } else {
                    await notificationProvider.enableNotifications(context);
                  }
                  if (mounted) {
                    setState(() {});
                  }
                },
              );
            },
          ),
          _buildDivider(),
          _buildMenuItem(
            icon: Icons.logout_rounded,
            title: 'common.logout'.tr(),
            subtitle: 'common.signOut'.tr(),
            isDestructive: true,
            onTap: _showLogoutConfirmation,
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
    Widget? trailing,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDestructive ? Colors.red.shade50 : AppColors.primarySoft(0.1), 
          borderRadius: BorderRadius.circular(12)
        ),
        child: Icon(icon, color: isDestructive ? Colors.red : AppColors.primary, size: 22),
      ),
      title: Text(
        title, 
        style: TextStyle(
          color: isDestructive ? Colors.red : Colors.black87, 
          fontWeight: FontWeight.w600
        ),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      onTap: onTap,
    );
  }

  Widget _buildDivider() => const Divider(height: 1, indent: 56, endIndent: 16);

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
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.primarySoft(0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary, size: 18)),
                          ),
                          const SizedBox(width: 16),
                          Text('common.personalData'.tr(), style: AppText.h1),
                        ]),
                        const SizedBox(height: 24),
                        _buildInfoCard(),
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

  Widget _buildInfoCard() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          _buildInfoRow(
              icon: Icons.badge_outlined,
              label: 'common.displayName'.tr(),
              value: _displayName.isNotEmpty ? _displayName : 'parent.parent_profile_screen.notSet'.tr(),
              trailing: widget.parentId == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                      onPressed: _editName,
                    )),
          const Divider(height: 1, indent: 40),
          _buildInfoRow(icon: Icons.email_outlined, label: 'common.emailAddress'.tr(), value: widget.parentEmail),
          const Divider(height: 1, indent: 40),
          _buildDeleteAccountRow(),
        ],
      ),
    );
  }

  Widget _buildInfoRow({required IconData icon, required String label, required String value, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primarySoft(0.7)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ]),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Future<void> _editName() async {
    final parentId = widget.parentId;
    if (parentId == null) return;

    final newName = await showEditTextDialog(
      context,
      title: 'common.displayName'.tr(),
      initialValue: _displayName,
      onSave: (value) => Database().updateUser(uid: parentId, name: value),
    );

    if (newName != null && mounted) {
      _displayName = newName;
      _personalDataRefresh?.call(() {});
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('common.displayNameUpdate'.tr())),
      );
    }
  }

  Widget _buildDeleteAccountRow() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.delete_outline, color: Colors.red, size: 22)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('common.deleteAccount'.tr(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)), Text('common.deletePermAcc'.tr(), style: TextStyle(fontSize: 12, color: Colors.grey.shade600))])),
          TextButton(onPressed: widget.onDeleteAccount, style: TextButton.styleFrom(foregroundColor: Colors.red), child: Text('common.delete'.tr(), style: const TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}

// Security Screen - Contains Biometric + Change Password
class _SecurityScreen extends StatelessWidget {
  const _SecurityScreen();

  void _navigateToChangePassword(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ResetInAppScreen(
              header: ParentScreenHeader(title: 'common.changePassword'.tr()))),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Scaffold(
      backgroundColor: const Color(0xFFEFF6EE),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary, size: 18),
                  ),
                ),
                const SizedBox(width: 16),
                Text('common.security'.tr(), style: AppText.h1),
              ]),
              const SizedBox(height: 16),
              // Change Password Card
              Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Material(
                  type: MaterialType.transparency,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text('common.password'.tr(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary)),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.lock_reset_outlined, color: AppColors.primary, size: 22),
                        ),
                        title: Text(
                          'common.changePassword'.tr(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'parent.parent_profile_screen.updatePassword'.tr(),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                        onTap: () => _navigateToChangePassword(context),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Biometric Authentication Card
              Consumer<BiometricProvider>(
                builder: (context, biometricProvider, child) {
                  final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
                  
                  return Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: Material(
                      type: MaterialType.transparency,
                      borderRadius: BorderRadius.circular(20),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text('common.biometricAuth'.tr(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary)),
                          ),
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: biometricProvider.isLoading
                                ? const Center(child: CircularProgressIndicator())
                                : biometricProvider.isSupported
                                    ? SwitchListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(biometricProvider.biometricTypeName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                        subtitle: Text('common.biometricSignIn'.tr()),
                                        value: biometricProvider.isEnabled,
                                        activeColor: AppColors.primary,
                                        onChanged: (value) => biometricProvider.toggle(context, userId),
                                      )
                                    : Row(children: [
                                        const Icon(Icons.fingerprint_outlined, color: Colors.grey),
                                        const SizedBox(width: 16),
                                        Expanded(child: Text('common.biometricsNotAvailable'.tr(), style: const TextStyle(color: Colors.grey))),
                                      ]),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              
              // Info Card
              // Container(
              //   padding: const EdgeInsets.all(AppSpacing.md),
              //   decoration: BoxDecoration(
              //     color: AppColors.primarySoft(0.05),
              //     borderRadius: BorderRadius.circular(AppRadii.md),
              //     border: Border.all(
              //       color: AppColors.primarySoft(0.2),
              //     ),
              //   ),
              //   child: Row(
              //     children: [
              //       Icon(
              //         Icons.info_outline,
              //         size: 20,
              //         color: AppColors.primary,
              //       ),
              //       const SizedBox(width: AppSpacing.sm),
              //       Expanded(
              //         child: Text(
              //           'Keep your account secure by using a strong password',
              //           style: AppText.caption.copyWith(
              //             color: AppColors.textSecondary,
              //           ),
              //         ),
              //       ),
              //     ],
              //   ),
              // ),
            ],
          ),
        ),
      ),
    );
  }
}