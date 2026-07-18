import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:loringo_app/components/auth_layout.dart';
import 'package:loringo_app/components/my_loading.dart';
import 'package:loringo_app/components/my_textfield.dart';
import 'package:loringo_app/components/recaptcha/recaptcha_widget.dart';
import 'package:loringo_app/screens/initials/reset_password_screen.dart';
import 'package:loringo_app/screens/student/student_code_screen.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:loringo_app/services/auth/student_auth_service.dart';
import 'package:loringo_app/theme/app_theme.dart';

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
      return const Scaffold(
        body: ColoredBox(
          color: Color(0xFFBEDC74),
          child: MyLoading(),
        ),
      );
    }

    return AuthLayout(
      heroVisual: Image.asset(
        'assets/images/loro-llave.png',
        width: kIsWeb ? 140 : 140,
        height: kIsWeb ? 180 : 185,
        fit: BoxFit.contain,
      ),
      title: 'Welcome back!',
      subtitle: 'Sign in to Loringo',
      form: Column(
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
                  MaterialPageRoute(builder: (_) => const ResetPasswordScreen())),
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
              onVerified: (t) => setState(() => _captchaVerified = t.isNotEmpty),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(
            onPressed: _signIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
              elevation: 0,
            ),
            child: const Text('Sign In',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const StudentCodeScreen())),
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
        ],
      ),
    );
  }
}