import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/avatar_selector.dart';
import 'package:loringo_app/providers/biometric_provider.dart';
import 'package:loringo_app/services/auth/login_or_register.dart';
import 'package:loringo_app/services/auth/student_auth_service.dart';
import 'package:loringo_app/theme/app_theme.dart';

class StudentSettingsTab extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String studentAvatar; // Add this parameter

  const StudentSettingsTab({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.studentAvatar, // Required parameter
  });

  @override
  State<StudentSettingsTab> createState() => _StudentSettingsTabState();
}

class _StudentSettingsTabState extends State<StudentSettingsTab> {
  late String currentAvatar; // Store current avatar state

  @override
  void initState() {
    super.initState();
    currentAvatar = widget.studentAvatar; // Initialize with database value

    // Initialize biometric provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BiometricProvider>().initialize(widget.studentId);
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    final biometricProvider = context.read<BiometricProvider>();
    await biometricProvider.toggle(context, widget.studentId);
  }

  /// Show avatar selector dialog
  void _showAvatarSelector() {
    showDialog(
      context: context,
      builder: (context) => AvatarSelector(
        currentAvatar: currentAvatar,
        onAvatarSelected: (avatar) async {
          // Update the avatar in Firebase
          try {
            await StudentAuthService.updateStudentAvatar(
              studentId: widget.studentId,
              newAvatar: avatar,
            );

            // Update local state. The Activities tab listens to the
            // student doc directly via a Firestore stream, so it picks up
            // this change on its own — no callback or shared state needed.
            setState(() {
              currentAvatar = avatar;
            });

            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Avatar updated successfully!'),
                  backgroundColor: AppColors.success,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error updating avatar: $e'),
                  backgroundColor: AppColors.danger,
                ),
              );
            }
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final biometricProvider = context.watch<BiometricProvider>();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE8F5E9), Colors.white],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text(
                'Settings',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 30),

              // Avatar Section — centered, avatar-only, tap to change
              _buildAvatarSection(),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 24),

              if (biometricProvider.isLoading)
                const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                  ),
                )
              else if (biometricProvider.isSupported)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.tint(AppColors.primary),
                      borderRadius: AppRadii.smAll,
                    ),
                    child: Icon(
                      biometricProvider.biometricTypeName == 'Face ID'
                          ? Icons.face_rounded
                          : Icons.fingerprint_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  title: Text(
                    '${biometricProvider.biometricTypeName} Login',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text('Quick and secure login'),
                  trailing: Switch(
                    value: biometricProvider.isEnabled,
                    onChanged: _toggleBiometric,
                    activeColor: AppColors.primary,
                  ),
                ),
              const SizedBox(height: 16),
              _buildLogoutTile(),
            ],
          ),
        ),
      ),
    );
  }

  /// Centered avatar with an edit badge — tap anywhere on it to open the
  /// avatar picker. No name shown here on purpose; the name already shows
  /// on the Home tab header.
  Widget _buildAvatarSection() {
    return Center(
      child: GestureDetector(
        onTap: _showAvatarSelector,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.subtleFill,
                    border: Border.all(color: AppColors.primary, width: 3),
                    boxShadow: AppShadows.card,
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      currentAvatar,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.person,
                          color: AppColors.muted,
                          size: 56,
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 2),
                    ),
                    child: const Icon(
                      Icons.edit_rounded,
                      color: AppColors.onPrimary,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Tap to change avatar', style: AppText.caption),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutTile() {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.tint(AppColors.danger),
          borderRadius: AppRadii.smAll,
        ),
        child: const Icon(Icons.logout_rounded, color: AppColors.danger),
      ),
      title: const Text(
        'Logout',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.danger,
        ),
      ),
      subtitle: const Text('Return to login screen'),
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Logout'),
            content: const Text('Are you sure you want to logout?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await StudentAuthService.clearStudentLogin();
                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LoginOrRegister(),
                      ),
                      (route) => false,
                    );
                  }
                },
                child: const Text(
                  'Logout',
                  style: TextStyle(color: AppColors.danger),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}