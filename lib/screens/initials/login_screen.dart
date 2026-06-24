import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:loringo_app/components/my_loading.dart';
import 'package:loringo_app/components/my_textfield.dart';
import 'package:loringo_app/components/recaptcha/recaptcha_widget.dart';
import 'package:loringo_app/components/responsive.dart';
// import 'package:loringo_app/components/wave_divider.dart';
import 'package:loringo_app/components/wave_form.dart';
import 'package:loringo_app/screens/initials/reset_password_screen.dart';
import 'package:loringo_app/screens/student/student_code_screen.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:loringo_app/services/auth/student_auth_service.dart';
import 'package:loringo_app/theme/app_theme.dart';

const _kTopGradient = LinearGradient(
  colors: [Color(0xFFF6E96B), Color(0xFFBEDC74), Color(0xFFA2CA71)],
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
);
const _kBottomColor = Color(0xFFF2F8F2);

class LoginScreen extends StatefulWidget {
  final void Function()? onTap;
  const LoginScreen({super.key, required this.onTap});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isLoading = false;
  bool _captchaVerified = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
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

  Future<void> _signIn() async {
    if (kIsWeb && !_captchaVerified) {
      _snack('Please complete the captcha');
      return;
    }
    if (_emailCtrl.text.trim().isEmpty) {
      _snack('Email is required');
      return;
    }
    if (!_emailCtrl.text.contains('@')) {
      _snack('Please enter a valid email');
      return;
    }
    if (_passCtrl.text.isEmpty) {
      _snack('Password is required');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await StudentAuthService.clearStudentLogin();
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (r) => false,
        );
      }
    } on FirebaseAuthException {
      resetRecaptcha();
      setState(() => _captchaVerified = false);
      _snack('Incorrect email or password');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: _kTopGradient),
          child: const MyLoading(),
        ),
      );
    }

    final screenH = MediaQuery.of(context).size.height;
    final heroH = screenH * 0.42;
    final maxW = kIsWeb ? 480.0 : double.infinity;

    return Scaffold(
      backgroundColor: _kBottomColor,
      body: Stack(
        children: [
          // Background
          Container(color: _kBottomColor),

          // Fixed Hero Section
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
                    Image.asset(
                      'assets/images/loro-llave.png',
                      width: kIsWeb ? 170 : 140,
                      height: kIsWeb ? 220 : 185,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Text(
                      'Welcome back!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E6B30),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'Sign in to Loringo',
                      textAlign: TextAlign.center,
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

          // Wave Divider
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

          // Scrollable Form
          Positioned(
            top: heroH + 20,
            left: 0,
            right: 0,
            bottom: 0,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW),
                  child: Responsive(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: kIsWeb ? AppSpacing.xl : AppSpacing.lg,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: AppSpacing.lg),
                          
                          // Form card
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
                                  controller: _emailCtrl,
                                  hintText: 'Email',
                                  obscureText: false,
                                  isEnabled: true,
                                ),
                                const SizedBox(height: AppSpacing.md),
                                MyTextField(
                                  controller: _passCtrl,
                                  hintText: 'Password',
                                  obscureText: true,
                                  isEnabled: true,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: GestureDetector(
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) => const ResetPasswordScreen())),
                                    child: const Text(
                                      'Forgot password?',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                if (kIsWeb) ...[
                                  const SizedBox(height: AppSpacing.md),
                                  RecaptchaWidget(
                                    onVerified: (t) => setState(
                                        () => _captchaVerified = t.isNotEmpty),
                                  ),
                                ],
                                const SizedBox(height: AppSpacing.lg),
                                ElevatedButton(
                                  onPressed: _signIn,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: AppColors.onPrimary,
                                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(AppRadii.md)),
                                    elevation: 0,
                                  ),
                                  child: const Text('Sign In',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: AppSpacing.md),

                          // Student login outline pill
                          GestureDetector(
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const StudentCodeScreen())),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md - 2),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(AppRadii.md),
                                border: Border.all(
                                    color: AppColors.primarySoft(0.3), width: 1.5),
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
                                  Icon(Icons.school_rounded, color: AppColors.primary, size: 20),
                                  const SizedBox(width: AppSpacing.sm),
                                  const Text('Student Login',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary,
                                      )),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: AppSpacing.lg),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('New here? ',
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500)),
                              GestureDetector(
                                onTap: widget.onTap,
                                child: const Text(
                                  'Create account',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                    fontSize: 14,
                                    decoration: TextDecoration.underline,
                                    decorationColor: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: AppSpacing.xl * 2),
                        ],
                      ),
                    ),
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