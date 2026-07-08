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
  final String studentAvatar;
  final bool showBackButton;

  const StudentSettingsTab({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.studentAvatar,
    this.showBackButton = false,
  });

  static Future<void> showAvatarSelectorFor({
    required BuildContext context,
    required String studentId,
    required String currentAvatar,
    required void Function(String newAvatar) onUpdated,
  }) {
    return showDialog(
      context: context,
      builder: (context) => AvatarSelector(
        currentAvatar: currentAvatar,
        onAvatarSelected: (avatar) async {
          try {
            await StudentAuthService.updateStudentAvatar(
              studentId: studentId,
              newAvatar: avatar,
            );
            onUpdated(avatar);
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
  State<StudentSettingsTab> createState() => _StudentSettingsTabState();
}

class _StudentSettingsTabState extends State<StudentSettingsTab> {
  late String currentAvatar;

  @override
  void initState() {
    super.initState();
    currentAvatar = widget.studentAvatar;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BiometricProvider>().initialize(widget.studentId);
    });
  }

  @override
  void didUpdateWidget(covariant StudentSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.studentAvatar != oldWidget.studentAvatar) {
      currentAvatar = widget.studentAvatar;
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    final biometricProvider = context.read<BiometricProvider>();
    await biometricProvider.toggle(context, widget.studentId);
  }

  void _showAvatarSelector() {
    StudentSettingsTab.showAvatarSelectorFor(
      context: context,
      studentId: widget.studentId,
      currentAvatar: currentAvatar,
      onUpdated: (avatar) => setState(() => currentAvatar = avatar),
    );
  }

  /// Same inline header pattern used by _SecurityScreen — a rounded
  /// back-arrow chip next to the title, no Flutter AppBar. Only shown
  /// when this screen was navigated to (Navigator.canPop is true); when
  /// embedded as a tab inside StudentMainScreen's IndexedStack there's
  /// nothing to pop back to, so the arrow is omitted there.
  Widget _buildHeader(BuildContext context, String title) {
    return Row(children: [
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
      Text(title, style: AppText.h1),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final biometricProvider = context.watch<BiometricProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFE8F5E9),
      body: Container(
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
                _buildHeader(context, 'Settings'),
                const SizedBox(height: 30),
                _buildAvatarSection(),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 24),
                if (biometricProvider.isLoading)
                  const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
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
      ),
    );
  }

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