import 'package:flutter/material.dart';
import 'package:loringo_app/components/auth_layout.dart';
import 'package:loringo_app/screens/initials/otp_screen.dart';
import 'package:loringo_app/services/auth/otp_service.dart';
import 'package:loringo_app/theme/app_theme.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final OTPService _otpService = OTPService();
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
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

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final email = _emailCtrl.text.trim();
      final canRequest = await _otpService.canRequestOTP(email);

      if (!canRequest['canSend']) {
        String msg = canRequest['message'] as String;
        if (canRequest['reason'] == 'cooldown') {
          final remaining = canRequest['remainingMinutes'];
          msg = 'Please wait $remaining minutes before requesting a code';
        } else if (canRequest['reason'] == 'daily_limit') {
          msg =
              'Daily limit of ${canRequest['maxDaily']} attempts reached. Try tomorrow';
        }
        _snack(msg, color: AppColors.warning);
        return;
      }

      if (canRequest['remainingAttempts'] != null) {
        _snack(
          'You have ${canRequest['remainingAttempts']} attempts left today',
          color: AppColors.info,
        );
      }

      await _otpService.sendOTPToEmail(email);
      _snack('Verification code sent to $email', color: AppColors.success);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => OTPScreen(email: email)),
        );
      }
    } catch (e) {
      String errMsg = e.toString().replaceFirst('Exception: ', '');
      if (errMsg.contains('Email is not registered')) {
        errMsg = 'This email is not registered';
      }
      _snack(errMsg);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      mobileHeroFraction: 0.40,
      onBack: () => Navigator.pop(context),
      heroVisual: Image.asset(
        'assets/images/loro-llave.png',
        width: 110,
        height: 145,
        fit: BoxFit.contain,
      ),
      title: 'Reset Password',
      subtitle: 'We\'ll send a code to your email',
      form: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: AppInput.decoration(
                accent: AppColors.primary,
                hint: 'Email address',
                icon: Icons.email_outlined,
              ),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Email is required';
                }
                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
                  return 'Enter a valid email';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: _isLoading ? null : _sendCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                disabledBackgroundColor: AppColors.primaryLight,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md)),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Send Code', style: AppText.button),
            ),
          ],
        ),
      ),
      footer: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md - 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.primarySoft(0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.arrow_back_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: AppSpacing.sm),
              const Text(
                'Back to Login',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}