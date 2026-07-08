// admin_profile_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/biometric_provider.dart';
import 'package:loringo_app/screens/initials/reset_in_app_screen.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:loringo_app/theme/app_theme.dart';

class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

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
    
    // Initialize biometric provider
    if (mounted) {
      context.read<BiometricProvider>().initialize(uid);
    }
    
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
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.muted))),
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
            child: const Text('Log Out',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        const Text('My Profile', style: AppText.h1),
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
        Text(_name.isNotEmpty ? _name : 'Admin',
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
          child: const Text('Admin',
              style: TextStyle(
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
      child: Column(
        children: [
          _buildMenuItem(
            icon: Icons.person_outline_rounded,
            title: 'Personal Data',
            subtitle: 'View and manage your information',
            onTap: () => _navigateToPersonalData(),
          ),
          const Divider(height: 1, indent: 56, endIndent: 16),
          _buildMenuItem(
            icon: Icons.security_rounded,
            title: 'Security',
            subtitle: 'Biometric & password settings',
            onTap: () => _navigateToSecurity(),
          ),
          const Divider(height: 1, indent: 56, endIndent: 16),
          // _buildBiometricToggle(biometricProvider, userId),
          // const Divider(height: 1, indent: 56, endIndent: 16),
          _buildMenuItem(
            icon: Icons.logout_rounded,
            title: 'Log Out',
            subtitle: 'Sign out from your account',
            onTap: _showLogoutConfirmation,
            isDestructive: true,
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
        builder: (context) => Scaffold(
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
        ),
      ),
    );
  }

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
      const Text('Personal Data', style: AppText.h1),
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
              label: 'Display Name',
              value: _name.isNotEmpty ? _name : 'Not set'),
          const Divider(height: 1, indent: 40),
          _buildInfoRow(
              icon: Icons.email_outlined,
              label: 'Email Address',
              value: _email),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
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
      ]),
    );
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
      const Text('Security', style: AppText.h1),
    ]);
  }

  Widget _buildPasswordCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Password',
                style: TextStyle(
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
            title: const Text('Change Password',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            subtitle: const Text('Update your password',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ResetInAppScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricCard(BuildContext context, BiometricProvider provider, String userId) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Biometric Authentication',
                style: TextStyle(
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
                        subtitle: const Text('Use biometrics to sign in quickly'),
                        value: provider.isEnabled,
                        activeColor: AppColors.primary,
                        onChanged: (value) => provider.toggle(context, userId),
                      )
                    : const Row(children: [
                        Icon(Icons.fingerprint_outlined, size: 24, color: Colors.grey),
                        SizedBox(width: 16),
                        Expanded(
                          child: Text('Biometrics not available on this device',
                              style: TextStyle(fontSize: 14, color: Colors.grey)),
                        ),
                      ]),
          ),
        ],
      ),
    );
  }
}