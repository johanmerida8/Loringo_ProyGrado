import 'package:flutter/material.dart';
import 'package:loringo_app/components/my_textfield.dart';
import 'package:loringo_app/components/wave_form.dart';
import 'package:loringo_app/screens/initials/login_screen.dart';
import 'package:loringo_app/services/auth/otp_service.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/password_utils.dart';

const _kTopGradient = LinearGradient(
  colors: [Color(0xFFF6E96B), Color(0xFFBEDC74), Color(0xFFA2CA71)],
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
);
const _kBottomColor = Color(0xFFF2F8F2);

class ConfirmResetPasswordScreen extends StatefulWidget {
  final String email;
  final String otp;
  final void Function()? onTap;

  const ConfirmResetPasswordScreen({
    super.key,
    required this.email,
    required this.otp,
    this.onTap,
  });

  @override
  State<ConfirmResetPasswordScreen> createState() =>
      _ConfirmResetPasswordScreenState();
}

class _ConfirmResetPasswordScreenState
    extends State<ConfirmResetPasswordScreen> {
  final OTPService _otpService = OTPService();

  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _showStrength = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _newPassCtrl.addListener(() {
      setState(() => _showStrength = _newPassCtrl.text.isNotEmpty);
    });
    _confirmPassCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {Color color = AppColors.danger}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md)),
    ));
  }

  Future<void> _resetPassword() async {
    final newPwd = _newPassCtrl.text.trim();
    final confirmPwd = _confirmPassCtrl.text.trim();

    if (newPwd.isEmpty) {
      _snack('Please enter a new password');
      return;
    }
    if (newPwd != confirmPwd) {
      _snack('Passwords don\'t match');
      return;
    }
    if (!PasswordUtils.isPasswordValid(newPwd)) {
      final requirements = PasswordUtils.getPasswordRequirements(newPwd);
      _snack(
        'Password must include:\n• ${requirements.join('\n• ')}',
        color: AppColors.warning,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _otpService.updatePassword(
        email: widget.email,
        otp: widget.otp,
        newPassword: newPwd,
      );
      _snack('Password reset successfully!', color: AppColors.success);
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
              builder: (_) => LoginScreen(onTap: widget.onTap)),
          (_) => false,
        );
      }
    } catch (e) {
      _snack('Error resetting password: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final heroH = screenH * 0.38;

    final password = _newPassCtrl.text;
    final confirmPassword = _confirmPassCtrl.text;
    final mismatch =
        confirmPassword.isNotEmpty && password != confirmPassword;

    return Scaffold(
      backgroundColor: _kBottomColor,
      body: Stack(
        children: [
          Container(color: _kBottomColor),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: heroH + 20,
            child: Container(
              decoration: const BoxDecoration(gradient: _kTopGradient),
              child: SafeArea(
                bottom: false,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        size: 52,
                        color: Color(0xFF2E6B30),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Text(
                      'New Password',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E6B30),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      widget.email,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF3D7A3F),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: heroH - 8,
            left: 0,
            right: 0,
            child: const WaveDivider(
              color: _kBottomColor,
              height: 54,
              waveIntensity: 1.0,
            ),
          ),
          Positioned(
            top: heroH + 20,
            left: 0,
            right: 0,
            bottom: 0,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadii.lg + 4),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.08),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          MyTextField(
                            controller: _newPassCtrl,
                            hintText: 'New password',
                            obscureText: true,
                            isEnabled: true,
                          ),
                          if (_showStrength) ...[
                            const SizedBox(height: AppSpacing.md),
                            _PasswordStrengthPanel(password: password),
                          ],
                          const SizedBox(height: AppSpacing.md),
                          MyTextField(
                            controller: _confirmPassCtrl,
                            hintText: 'Confirm password',
                            obscureText: true,
                            isEnabled: true,
                          ),
                          if (mismatch) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Row(
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    size: 15,
                                    color: AppColors.warning),
                                const SizedBox(width: 6),
                                Text(
                                  'Passwords don\'t match',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          ElevatedButton(
                            onPressed: _isLoading ? null : _resetPassword,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.onPrimary,
                              disabledBackgroundColor: AppColors.primaryLight,
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.md),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadii.md)),
                              elevation: 0,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
                                  )
                                : const Text('Reset Password',
                                    style: AppText.button),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl * 2),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordStrengthPanel extends StatelessWidget {
  final String password;
  const _PasswordStrengthPanel({required this.password});

  @override
  Widget build(BuildContext context) {
    final strength = PasswordUtils.getPasswordStrength(password);
    final color = PasswordUtils.getPasswordStrengthColor(password);
    final missing = PasswordUtils.getPasswordRequirements(password);
    final score = PasswordUtils.strengthScore(password);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBackground,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Strength: ',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              Text(
                strength,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(5, (i) {
              return Expanded(
                child: Container(
                  height: 5,
                  margin: EdgeInsets.only(right: i < 4 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: i < score ? color : AppColors.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }),
          ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...missing.map((req) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.cancel_outlined,
                          size: 13, color: AppColors.danger),
                      const SizedBox(width: 6),
                      Text(req,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                )),
          ] else ...[
            const SizedBox(height: 6),
            Row(
              children: const [
                Icon(Icons.check_circle_rounded,
                    size: 13, color: AppColors.success),
                SizedBox(width: 6),
                Text('Password meets all requirements',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.success)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}