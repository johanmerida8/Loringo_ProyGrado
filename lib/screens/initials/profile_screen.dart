import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:loringo_app/services/auth/biometric_service.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _captchaKey = 'captcha_auth_enabled';

  final _nameController = TextEditingController();

  bool _biometricEnabled = false;
  bool _captchaEnabled = false;
  bool _isBiometricAvailable = false;
  bool _loadingPrefs = true;
  bool _editingName = false;
  bool _savingName = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    bool biometricAvailable = false;

    if (!kIsWeb) {
      biometricAvailable = await BiometricService.canCheckBiometrics() ||
          await BiometricService.isDeviceSupported();
    }

    final biometricEnabled =
        uid.isNotEmpty ? await BiometricService.isBiometricEnabled(uid) : false;

    if (mounted) {
      setState(() {
        _biometricEnabled = biometricEnabled;
        _captchaEnabled = prefs.getBool(_captchaKey) ?? false;
        _isBiometricAvailable = biometricAvailable;
        _loadingPrefs = false;
      });
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (value) {
      final ok = await BiometricService.authenticate(
        reason: 'Confirm your identity to enable biometric login',
      );
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Biometric verification failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }
    await BiometricService.setBiometricEnabled(userId: uid, enabled: value);
    if (mounted) setState(() => _biometricEnabled = value);
  }

  Future<void> _toggleCaptcha(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_captchaKey, value);
    if (mounted) setState(() => _captchaEnabled = value);
    if (value && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CAPTCHA will be required on your next login.'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  Future<void> _saveName(String uid) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _savingName = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'name': name});
      if (mounted) {
        setState(() => _editingName = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Display name updated'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _sendPasswordReset(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password reset email sent to $email'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _avatarPath(String uid) {
    const avatars = [
      'assets/avatars/avatar1.png',
      'assets/avatars/avatar2.png',
      'assets/avatars/avatar3.png',
      'assets/avatars/avatar4.png',
      'assets/avatars/avatar5.png',
    ];
    return avatars[uid.hashCode.abs() % avatars.length];
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() as Map<String, dynamic>?;
          final name = (data?['name'] as String?) ?? '';
          final email = (data?['email'] as String?) ?? user.email ?? '';
          final role = (data?['role'] as String?) ?? '';

          if (!_editingName &&
              name.isNotEmpty &&
              _nameController.text != name) {
            _nameController.text = name;
          }

          return CustomScrollView(
            slivers: [
              _buildAppBar(user, name, email, role),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionCard(
                        title: 'Profile Information',
                        icon: Icons.person_outline,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.badge_outlined,
                                color: AppColors.primary),
                            title: const Text('Display name',
                                style:
                                    TextStyle(fontSize: 12, color: Colors.grey)),
                            subtitle: _editingName
                                ? Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _nameController,
                                          autofocus: true,
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    vertical: 6),
                                          ),
                                        ),
                                      ),
                                      if (_savingName)
                                        const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      else ...[
                                        IconButton(
                                          icon: const Icon(Icons.check,
                                              color: AppColors.primary),
                                          onPressed: () => _saveName(user.uid),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.close),
                                          onPressed: () => setState(
                                              () => _editingName = false),
                                        ),
                                      ],
                                    ],
                                  )
                                : Text(
                                    name.isNotEmpty ? name : '—',
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500),
                                  ),
                            trailing: !_editingName
                                ? IconButton(
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 20),
                                    onPressed: () {
                                      _nameController.text = name;
                                      setState(() => _editingName = true);
                                    },
                                  )
                                : null,
                          ),
                          const Divider(height: 1, indent: 56),
                          ListTile(
                            leading: const Icon(Icons.email_outlined,
                                color: AppColors.primary),
                            title: const Text('Email',
                                style:
                                    TextStyle(fontSize: 12, color: Colors.grey)),
                            subtitle: Text(email,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w500)),
                          ),
                          const Divider(height: 1, indent: 56),
                          ListTile(
                            leading: const Icon(Icons.school_outlined,
                                color: AppColors.primary),
                            title: const Text('Role',
                                style:
                                    TextStyle(fontSize: 12, color: Colors.grey)),
                            subtitle: Text(
                              role.isNotEmpty
                                  ? '${role[0].toUpperCase()}${role.substring(1)}'
                                  : '—',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _sectionCard(
                        title: 'Security & Access',
                        icon: Icons.security_outlined,
                        children: [
                          if (!kIsWeb) ...[
                            _loadingPrefs
                                ? const ListTile(
                                    leading: Icon(Icons.fingerprint,
                                        color: AppColors.primary),
                                    title: Text('Biometric Authentication'),
                                    trailing: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : SwitchListTile(
                                    secondary: const Icon(Icons.fingerprint,
                                        color: AppColors.primary),
                                    title: const Text(
                                        'Biometric Authentication'),
                                    subtitle: Text(
                                      _isBiometricAvailable
                                          ? 'Use fingerprint or face ID to verify your identity'
                                          : 'No biometrics enrolled on this device',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    value: _biometricEnabled,
                                    activeColor: AppColors.primary,
                                    onChanged: _isBiometricAvailable
                                        ? _toggleBiometric
                                        : null,
                                  ),
                          ] else ...[
                            _loadingPrefs
                                ? const ListTile(
                                    leading: Icon(
                                        Icons.verified_user_outlined,
                                        color: AppColors.primary),
                                    title: Text('CAPTCHA Protection'),
                                    trailing: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : SwitchListTile(
                                    secondary: const Icon(
                                        Icons.verified_user_outlined,
                                        color: AppColors.primary),
                                    title: const Text('CAPTCHA Protection'),
                                    subtitle: const Text(
                                      'Require human verification on login (web)',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    value: _captchaEnabled,
                                    activeColor: AppColors.primary,
                                    onChanged: _toggleCaptcha,
                                  ),
                          ],
                          const Divider(height: 1, indent: 56),
                          ListTile(
                            leading: const Icon(Icons.lock_reset_outlined,
                                color: AppColors.primary),
                            title: const Text('Change Password'),
                            subtitle: const Text(
                              'Send a password reset link to your email',
                              style: TextStyle(fontSize: 12),
                            ),
                            trailing: const Icon(Icons.chevron_right,
                                color: Colors.grey),
                            onTap: email.isNotEmpty
                                ? () => _sendPasswordReset(email)
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  SliverAppBar _buildAppBar(
      User user, String name, String email, String role) {
    return SliverAppBar(
      expandedHeight: 210,
      pinned: true,
      backgroundColor: AppColors.primary,
      iconTheme: const IconThemeData(color: Colors.white),
      title: const Text(
        'My Profile',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 44),
                CircleAvatar(
                  radius: 46,
                  backgroundColor: Colors.white,
                  backgroundImage: AssetImage(_avatarPath(user.uid)),
                ),
                const SizedBox(height: 10),
                Text(
                  name.isNotEmpty ? name : email,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (role.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      role.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          color: Colors.white,
          child: Column(children: children),
        ),
      ],
    );
  }
}
