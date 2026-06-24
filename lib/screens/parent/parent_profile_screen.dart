import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/biometric_provider.dart';
import 'package:loringo_app/providers/notification_provider.dart';
import 'package:loringo_app/screens/initials/reset_in_app_screen.dart';
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

class _ParentProfileScreenState extends State<ParentProfileScreen> {
  @override
  void initState() {
    super.initState();
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
            const Text(
              'Log Out',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to log out?',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('Cancel'),
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
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          const Text('My Profile', style: AppText.h1),
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
            child: Text(widget.parentName.isNotEmpty ? widget.parentName[0].toUpperCase() : 'P', style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          Text(widget.parentName.isNotEmpty ? widget.parentName : 'Parent', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
            child: const Text('Parent', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          _buildMenuItem(
            icon: Icons.person_outline_rounded,
            title: 'Personal Data',
            subtitle: 'View and manage your information',
            onTap: () => _navigateToPersonalData(),
          ),
          _buildDivider(),
          _buildMenuItem(
            icon: Icons.security_rounded,
            title: 'Security',
            subtitle: 'Password & biometric settings',
            onTap: _navigateToSecurity,
          ),
          _buildDivider(),
          // Notification toggle using Provider
          Consumer<NotificationProvider>(
            builder: (context, notificationProvider, child) {
              return _buildMenuItem(
                icon: Icons.notifications_active_rounded,
                title: 'Notifications',
                subtitle: "Get notified about your child's progress",
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
            title: 'Log Out',
            subtitle: 'Sign out from your account',
            isDestructive: true,
            onTap: _showLogoutConfirmation,
          ),
        ],
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
        builder: (_) => Scaffold(
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
                    const Text('Personal Data', style: AppText.h1),
                  ]),
                  const SizedBox(height: 24),
                  _buildInfoCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          _buildInfoRow(icon: Icons.badge_outlined, label: 'Display Name', value: widget.parentName.isNotEmpty ? widget.parentName : 'Not set'),
          const Divider(height: 1, indent: 40),
          _buildInfoRow(icon: Icons.email_outlined, label: 'Email Address', value: widget.parentEmail),
          const Divider(height: 1, indent: 40),
          _buildDeleteAccountRow(),
        ],
      ),
    );
  }

  Widget _buildInfoRow({required IconData icon, required String label, required String value}) {
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
        ],
      ),
    );
  }

  Widget _buildDeleteAccountRow() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.delete_outline, color: Colors.red, size: 22)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Delete Account', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)), Text('Permanently remove account and all data', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))])),
          TextButton(onPressed: widget.onDeleteAccount, style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold))),
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
      MaterialPageRoute(builder: (_) => const ResetInAppScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                const Text('Security', style: AppText.h1),
              ]),
              const SizedBox(height: 16),
              // Change Password Card
              Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text('Password', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary)),
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
                      title: const Text(
                        'Change Password',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Update your password',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                      onTap: () => _navigateToChangePassword(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Biometric Authentication Card
              Consumer<BiometricProvider>(
                builder: (context, biometricProvider, child) {
                  final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
                  
                  return Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text('Biometric Authentication', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary)),
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
                                      subtitle: const Text('Use biometrics to sign in quickly'),
                                      value: biometricProvider.isEnabled,
                                      activeColor: AppColors.primary,
                                      onChanged: (value) => biometricProvider.toggle(context, userId),
                                    )
                                  : const Row(children: [
                                      Icon(Icons.fingerprint_outlined, color: Colors.grey),
                                      SizedBox(width: 16),
                                      Expanded(child: Text('Biometrics not available on this device', style: TextStyle(color: Colors.grey))),
                                    ]),
                        ),
                      ],
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