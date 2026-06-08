// import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:loringo_app/theme/app_theme.dart';

class ParentProfileScreen extends StatefulWidget {
  final String parentName;
  final String parentEmail;
  final bool isBiometricSupported;
  final bool isBiometricEnabled;
  final bool isBioLoading;
  final List<BiometricType> availableBiometrics;
  final String biometricTypeName;
  final Function(bool) onToggleBiometric;
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  const ParentProfileScreen({
    super.key,
    required this.parentName,
    required this.parentEmail,
    required this.isBiometricSupported,
    required this.isBiometricEnabled,
    required this.isBioLoading,
    required this.availableBiometrics,
    required this.biometricTypeName,
    required this.onToggleBiometric,
    required this.onLogout,
    required this.onDeleteAccount,
  });

  @override
  State<ParentProfileScreen> createState() => _ParentProfileScreenState();
}

class _ParentProfileScreenState extends State<ParentProfileScreen> {
  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onLogout();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text('Delete Account', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('This action is permanent and cannot be undone.', style: TextStyle(fontSize: 14)),
            SizedBox(height: 16),
            Text('This will delete:', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('• Your account information'),
            Text('• All registered children'),
            Text('• All associated data'),
            SizedBox(height: 16),
            Text('Are you sure you want to proceed?', style: TextStyle(color: Colors.red)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onDeleteAccount();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );
  }

  void _navigateToPersonalData() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _PersonalDataScreen(
          name: widget.parentName,
          email: widget.parentEmail,
          onDeleteAccount: _showDeleteAccountConfirmation,
        ),
      ),
    );
  }

  void _navigateToSecurity() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _SecurityScreen(
          isBioLoading: widget.isBioLoading,
          isBiometricSupported: widget.isBiometricSupported,
          biometricTypeName: widget.biometricTypeName,
          isBiometricEnabled: widget.isBiometricEnabled,
          onToggleBiometric: widget.onToggleBiometric,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAEDCA),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: const Text(
          'My Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Profile Header
            _ProfileHeader(
              name: widget.parentName,
              role: 'Parent',
            ),
            const SizedBox(height: 16),

            // Menu List
            _MenuCard(
              items: [
                _MenuItem(
                  icon: Icons.person_outline_rounded,
                  title: 'Personal Data',
                  subtitle: 'View and manage your personal information',
                  onTap: _navigateToPersonalData,
                ),
                _MenuItem(
                  icon: Icons.security_rounded,
                  title: 'Security',
                  subtitle: 'Biometric authentication settings',
                  onTap: _navigateToSecurity,
                ),
                _MenuItem(
                  icon: Icons.logout_rounded,
                  title: 'Log Out',
                  subtitle: 'Sign out from your account',
                  onTap: _showLogoutConfirmation,
                  isDestructive: false,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Profile Header Widget
// ============================================================================
class _ProfileHeader extends StatelessWidget {
  final String name;
  final String role;

  const _ProfileHeader({
    required this.name,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: CircleAvatar(
              radius: 50,
              backgroundColor: Colors.white.withOpacity(0.25),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'P',
                style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name.isNotEmpty ? name : 'Parent',
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              role,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Menu Card Widget
// ============================================================================
class _MenuCard extends StatelessWidget {
  final List<_MenuItem> items;

  const _MenuCard({
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isLast = index == items.length - 1;
          return Column(
            children: [
              _MenuTile(item: item),
              if (!isLast) const Divider(height: 1, indent: 56, endIndent: 16),
            ],
          );
        }),
      ),
    );
  }
}

// ============================================================================
// Menu Item Model
// ============================================================================
class _MenuItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });
}

// ============================================================================
// Menu Tile Widget
// ============================================================================
class _MenuTile extends StatelessWidget {
  final _MenuItem item;

  const _MenuTile({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: item.isDestructive 
              ? Colors.red.shade50 
              : AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          item.icon,
          color: item.isDestructive ? Colors.red : AppColors.primary,
          size: 22,
        ),
      ),
      title: Text(
        item.title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: item.isDestructive ? Colors.red : Colors.black87,
        ),
      ),
      subtitle: Text(
        item.subtitle,
        style: const TextStyle(fontSize: 13, color: Colors.grey),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: Colors.grey[400],
      ),
      onTap: item.onTap,
    );
  }
}

// ============================================================================
// Personal Data Screen
// ============================================================================
class _PersonalDataScreen extends StatelessWidget {
  final String name;
  final String email;
  final VoidCallback onDeleteAccount;

  const _PersonalDataScreen({
    required this.name,
    required this.email,
    required this.onDeleteAccount,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAEDCA),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: const Text(
          'Personal Data',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Info Card
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Text(
                      'Account Information',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ),
                  const Divider(height: 1, thickness: 1, indent: 20, endIndent: 20),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _InfoDetailRow(
                          icon: Icons.badge_outlined,
                          label: 'Display Name',
                          value: name.isNotEmpty ? name : 'Not set',
                        ),
                        const Divider(height: 1, indent: 56),
                        _InfoDetailRow(
                          icon: Icons.email_outlined,
                          label: 'Email Address',
                          value: email,
                        ),
                        // const Divider(height: 1, indent: 56),
                        // _InfoDetailRow(
                        //   icon: Icons.verified_user_outlined,
                        //   label: 'Account Type',
                        //   value: 'Parent Account',
                        // ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Delete Account Button
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Text(
                      'Danger Zone',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                  ),
                  const Divider(height: 1, thickness: 1, indent: 20, endIndent: 20),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Delete Account',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'Permanently remove your account and all data',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            onDeleteAccount();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Info Detail Row (for Personal Data screen)
// ============================================================================
class _InfoDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary.withOpacity(0.7)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Security Screen
// ============================================================================
class _SecurityScreen extends StatelessWidget {
  final bool isBioLoading;
  final bool isBiometricSupported;
  final String biometricTypeName;
  final bool isBiometricEnabled;
  final Function(bool) onToggleBiometric;

  const _SecurityScreen({
    required this.isBioLoading,
    required this.isBiometricSupported,
    required this.biometricTypeName,
    required this.isBiometricEnabled,
    required this.onToggleBiometric,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAEDCA),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: const Text(
          'Security',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Text(
                  'Biometric Authentication',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ),
              const Divider(height: 1, thickness: 1, indent: 20, endIndent: 20),
              Padding(
                padding: const EdgeInsets.all(16),
                child: isBioLoading
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : isBiometricSupported
                        ? SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              biometricTypeName,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                            ),
                            subtitle: const Text('Use biometrics to sign in quickly'),
                            value: isBiometricEnabled,
                            activeColor: AppColors.primary,
                            onChanged: onToggleBiometric,
                          )
                        : const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Row(
                              children: [
                                Icon(Icons.fingerprint_outlined, size: 24, color: Colors.grey),
                                SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    'Biometrics not available on this device',
                                    style: TextStyle(fontSize: 14, color: Colors.grey),
                                  ),
                                ),
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}