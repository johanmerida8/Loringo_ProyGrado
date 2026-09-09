import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/auth_layout.dart';
import 'package:loringo_app/providers/locale_provider.dart';
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
          msg = 'initials.reset_password_screen.waitBeforeCode'
              .tr(namedArgs: {'minutes': '$remaining'});
        } else if (canRequest['reason'] == 'daily_limit') {
          msg = 'initials.reset_password_screen.dailyLimitReached'
              .tr(namedArgs: {'max': '${canRequest['maxDaily']}'});
        }
        _snack(msg, color: AppColors.warning);
        return;
      }

      if (canRequest['remainingAttempts'] != null) {
        _snack(
          'initials.reset_password_screen.attemptsLeftToday'
              .tr(namedArgs: {'count': '${canRequest['remainingAttempts']}'}),
          color: AppColors.info,
        );
      }

      await _otpService.sendOTPToEmail(email);
      _snack(
          'initials.reset_password_screen.codeSentTo'.tr(namedArgs: {'email': email}),
          color: AppColors.success);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => OTPScreen(email: email)),
        );
      }
    } catch (e) {
      // 'Email is not registered' is thrown as a stable, untranslated
      // sentinel from OTPService.sendOTPToEmail — matched here by content,
      // not shown directly (see the comment there for why it stays
      // English regardless of locale).
      String errMsg = e.toString().replaceFirst('Exception: ', '');
      if (errMsg.contains('Email is not registered')) {
        errMsg = 'initials.reset_password_screen.emailNotRegistered'.tr();
      }
      _snack(errMsg);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return AuthLayout(
      mobileHeroFraction: 0.40,
      onBack: () => Navigator.pop(context),
      heroVisual: Image.asset(
        'assets/images/loro-llave.png',
        width: 110,
        height: 145,
        fit: BoxFit.contain,
      ),
      title: 'common.resetPassword'.tr(),
      subtitle: 'initials.reset_password_screen.subtitle'.tr(),
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
                hint: 'initials.reset_password_screen.emailHint'.tr(),
                icon: Icons.email_outlined,
              ),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'common.emailValidation1'.tr();
                }
                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
                  return 'common.emailValidation2'.tr();
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
                  : Text('initials.reset_password_screen.sendCode'.tr(),
                      style: AppText.button),
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
              Text(
                'initials.reset_password_screen.backToLogin'.tr(),
                style: const TextStyle(
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