import 'package:flutter/material.dart';
import 'package:loringo_app/components/my_button.dart';
import 'package:loringo_app/components/wave_form.dart';
import 'package:loringo_app/screens/initials/otp_screen.dart';
import 'package:loringo_app/services/auth/otp_service.dart';
import 'package:loringo_app/theme/app_theme.dart';

// ─── Shared gradient — identical to LoginScreen so auth flow feels unified ───
const _kTopGradient = LinearGradient(
  colors: [Color(0xFFF6E96B), Color(0xFFBEDC74), Color(0xFFA2CA71)],
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
);
const _kBottomColor = Color(0xFFF2F8F2); // AppColors.scaffoldBackground

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

  // ── Snackbar helper (mirrors LoginScreen pattern) ─────────────────────────
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

  // ── Main send-code logic (unchanged from original) ────────────────────────
  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final email = _emailCtrl.text.trim();

      // Rate-limit check (15 min cooldown, max 3/day)
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
    final screenH = MediaQuery.of(context).size.height;
    final heroH = screenH * 0.40; // same proportion as LoginScreen

    return Scaffold(
      backgroundColor: _kBottomColor,
      body: Stack(
        children: [
          // ── Background fill ──────────────────────────────────────────────
          Container(color: _kBottomColor),

          // ── Hero gradient section ────────────────────────────────────────
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
                    // Lock icon — visually consistent with the parrot in login
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_reset_rounded,
                        size: 52,
                        color: Color(0xFF2E6B30),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Text(
                      'Reset Password',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E6B30),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'We\'ll send a code to your email',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF3D7A3F),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),

          // ── Wave divider (same component as LoginScreen) ─────────────────
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

          // ── Scrollable form ──────────────────────────────────────────────
          Positioned(
            top: heroH + 20,
            left: 0,
            right: 0,
            bottom: 0,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppSpacing.lg),

                      // ── White card (mirrors LoginScreen card) ──────────
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.circular(AppRadii.lg + 4),
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
                            // Email field — uses AppInput for consistency
                            TextFormField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: AppInput.decoration(
                                accent: AppColors.primary,
                                hint: 'Email address',
                                icon: Icons.email_outlined,
                              ),
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Email is required';
                                }
                                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+')
                                    .hasMatch(v.trim())) {
                                  return 'Enter a valid email';
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: AppSpacing.lg),

                            // Send code button — same style as Sign In
                            ElevatedButton(
                              onPressed: _isLoading ? null : _sendCode,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.onPrimary,
                                disabledBackgroundColor:
                                    AppColors.primaryLight,
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
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Send Code',
                                      style: AppText.button,
                                    ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // ── Back to login pill (mirrors Student Login pill) ─
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.md - 2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                                BorderRadius.circular(AppRadii.md),
                            border: Border.all(
                                color: AppColors.primarySoft(0.3),
                                width: 1.5),
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
                              Icon(Icons.arrow_back_rounded,
                                  color: AppColors.primary, size: 20),
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

                      const SizedBox(height: AppSpacing.xl * 2),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}