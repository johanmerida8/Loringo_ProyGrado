import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:loringo_app/components/my_loading.dart';
import 'package:loringo_app/components/my_textfield.dart';
import 'package:loringo_app/components/recaptcha/recaptcha_widget.dart';
import 'package:loringo_app/components/responsive.dart';
import 'package:loringo_app/components/wave_form.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/password_utils.dart';

const _kGradient = LinearGradient(
  colors: [Color(0xFFF6E96B), Color(0xFFBEDC74), Color(0xFFA2CA71)],
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
);
const _kBottomColor = Color(0xFFF2F8F2);

class RegisterScreen extends StatefulWidget {
  final void Function()? onTap;
  const RegisterScreen({super.key, required this.onTap});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _isLoading = false;
  String _errorMsg = '';
  bool _isAdminName = false;
  String? _selectedRole;
  String _passStrength = '';
  bool _showPassStrength = false;
  bool _captchaVerified = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _checkAdminName() {
    final l = _nameCtrl.text.trim().toLowerCase();
    final isAdmin = l == 'admin' || l == 'administrador';
    if (isAdmin != _isAdminName) {
      setState(() {
        _isAdminName = isAdmin;
        if (isAdmin) _selectedRole = null;
      });
    }
  }

  Future<void> _signUp() async {
    setState(() => _errorMsg = '');
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMsg = 'Name is required');
      return;
    }
    if (_emailCtrl.text.trim().isEmpty) {
      setState(() => _errorMsg = 'Email is required');
      return;
    }
    if (!_emailCtrl.text.contains('@')) {
      setState(() => _errorMsg = 'Enter a valid email');
      return;
    }
    if (_passCtrl.text.isEmpty) {
      setState(() => _errorMsg = 'Password is required');
      return;
    }
    if (!PasswordUtils.isPasswordValid(_passCtrl.text)) {
      setState(() => _errorMsg =
          'Password must contain: ${PasswordUtils.getPasswordRequirements(_passCtrl.text).join(', ')}');
      return;
    }
    if (_confirmCtrl.text.isEmpty) {
      setState(() => _errorMsg = 'Please confirm your password');
      return;
    }
    if (_confirmCtrl.text != _passCtrl.text) {
      setState(() => _errorMsg = 'Passwords do not match');
      return;
    }
    final isAdmin = name.toLowerCase() == 'admin' || name.toLowerCase() == 'administrador';
    if (!isAdmin && _selectedRole == null) {
      setState(() => _errorMsg = 'Please select your role: Teacher or Parent');
      return;
    }
    if (kIsWeb && !_captchaVerified) {
      setState(() => _errorMsg = 'Please complete the captcha');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailCtrl.text.trim(), password: _passCtrl.text.trim());
      final uid = cred.user?.uid ?? (throw Exception('No UID'));
      final role = isAdmin ? 'admin' : _selectedRole!;
      
      // Simplified user creation - only essential fields
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'name': name,
        'email': _emailCtrl.text.trim(),
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Account created as $role'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md)),
        ));
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      resetRecaptcha();
      setState(() {
        _captchaVerified = false;
        _errorMsg = e.code == 'email-already-in-use'
            ? 'This email is already registered.'
            : e.code == 'weak-password'
                ? 'Password is too weak.'
                : e.code == 'invalid-email'
                    ? 'Invalid email format.'
                    : (e.message ?? 'Registration failed');
      });
    } catch (e) {
      resetRecaptcha();
      setState(() {
        _captchaVerified = false;
        _errorMsg = e.toString();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double get _strengthFraction {
    switch (_passStrength.toLowerCase()) {
      case 'weak':
        return 0.33;
      case 'medium':
        return 0.66;
      case 'strong':
        return 1.0;
      default:
        return 0.1;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: _kGradient),
          child: const MyLoading(),
        ),
      );
    }

    final screenH = MediaQuery.of(context).size.height;
    final heroH = screenH * 0.38;
    final maxW = kIsWeb ? 480.0 : double.infinity;

    return Scaffold(
      backgroundColor: _kBottomColor,
      body: Stack(
        children: [
          Container(color: _kBottomColor),

          // Fixed Hero Section with gradient
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: heroH + 20,
            child: Container(
              decoration: const BoxDecoration(gradient: _kGradient),
              child: SafeArea(
                bottom: false,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    Image.asset(
                      'assets/images/loro-llave.png',
                      width: 100,
                      height: 135,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Text(
                      'Create your account',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E6B30),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'Sign up to Loringo',
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
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: AppSpacing.lg),

                          // Form card with semi-transparent background
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(AppRadii.lg + 4),
                              border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF387F39).withOpacity(0.12),
                                  blurRadius: 24,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                MyTextField(
                                  controller: _nameCtrl,
                                  hintText: 'Full Name',
                                  obscureText: false,
                                  isEnabled: true,
                                  onChanged: (_) => _checkAdminName(),
                                ),
                                const SizedBox(height: AppSpacing.md),
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
                                  onChanged: (v) => setState(() {
                                    _passStrength = PasswordUtils.getPasswordStrength(v);
                                    _showPassStrength = v.isNotEmpty;
                                  }),
                                ),
                                if (_showPassStrength) ...[
                                  const SizedBox(height: AppSpacing.sm),
                                  Row(children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(2),
                                        child: LinearProgressIndicator(
                                          value: _strengthFraction,
                                          minHeight: 4,
                                          backgroundColor: Colors.grey.shade200,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                              PasswordUtils.getPasswordStrengthColor(_passCtrl.text)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.md),
                                    Text(_passStrength,
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: PasswordUtils.getPasswordStrengthColor(_passCtrl.text))),
                                  ]),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                      '8+ chars, uppercase, lowercase, number & special character',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                ],
                                const SizedBox(height: AppSpacing.md),
                                MyTextField(
                                  controller: _confirmCtrl,
                                  hintText: 'Confirm Password',
                                  obscureText: true,
                                  isEnabled: true,
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                if (_isAdminName)
                                  Container(
                                    padding: const EdgeInsets.all(AppSpacing.md),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF8E1),
                                      borderRadius: BorderRadius.circular(AppRadii.md),
                                      border: Border.all(color: const Color(0xFFFFCA28), width: 1.5),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.admin_panel_settings_rounded,
                                            color: Color(0xFFD97706), size: 24),
                                        SizedBox(width: AppSpacing.sm),
                                        Text('Registering as Administrator',
                                            style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFFD97706))),
                                      ],
                                    ),
                                  )
                                else ...[
                                  Text('I am a…',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade700)),
                                  const SizedBox(height: AppSpacing.sm),
                                  Row(children: [
                                    Expanded(
                                        child: GestureDetector(
                                      onTap: () => setState(() => _selectedRole = 'teacher'),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 180),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: AppSpacing.md, horizontal: AppSpacing.sm),
                                        decoration: BoxDecoration(
                                          color: _selectedRole == 'teacher'
                                              ? AppColors.primary.withOpacity(0.1)
                                              : Colors.grey.shade50,
                                          borderRadius: BorderRadius.circular(AppRadii.md),
                                          border: Border.all(
                                              color: _selectedRole == 'teacher'
                                                  ? AppColors.primary
                                                  : Colors.grey.shade300,
                                              width: _selectedRole == 'teacher' ? 2 : 1),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.school_rounded,
                                                color: _selectedRole == 'teacher'
                                                    ? AppColors.primary
                                                    : Colors.grey.shade500,
                                                size: 26),
                                            const SizedBox(height: AppSpacing.xs),
                                            Text('Teacher',
                                                style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: _selectedRole == 'teacher'
                                                        ? AppColors.primary
                                                        : Colors.grey.shade600)),
                                          ],
                                        ),
                                      ),
                                    )),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(
                                        child: GestureDetector(
                                      onTap: () => setState(() => _selectedRole = 'parent'),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 180),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: AppSpacing.md, horizontal: AppSpacing.sm),
                                        decoration: BoxDecoration(
                                          color: _selectedRole == 'parent'
                                              ? const Color(0xFFFF9800).withOpacity(0.1)
                                              : Colors.grey.shade50,
                                          borderRadius: BorderRadius.circular(AppRadii.md),
                                          border: Border.all(
                                              color: _selectedRole == 'parent'
                                                  ? const Color(0xFFFF9800)
                                                  : Colors.grey.shade300,
                                              width: _selectedRole == 'parent' ? 2 : 1),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.family_restroom_rounded,
                                                color: _selectedRole == 'parent'
                                                    ? const Color(0xFFFF9800)
                                                    : Colors.grey.shade500,
                                                size: 26),
                                            const SizedBox(height: AppSpacing.xs),
                                            Text('Parent',
                                                style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: _selectedRole == 'parent'
                                                        ? const Color(0xFFFF9800)
                                                        : Colors.grey.shade600)),
                                          ],
                                        ),
                                      ),
                                    )),
                                  ]),
                                ],
                                if (_errorMsg.isNotEmpty) ...[
                                  const SizedBox(height: AppSpacing.md),
                                  Container(
                                    padding: const EdgeInsets.all(AppSpacing.md - 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.danger.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(AppRadii.sm),
                                      border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                                    ),
                                    child: Row(children: [
                                      Icon(Icons.error_outline, color: AppColors.danger, size: 16),
                                      const SizedBox(width: AppSpacing.sm),
                                      Expanded(
                                          child: Text(_errorMsg,
                                              style: TextStyle(fontSize: 13, color: AppColors.danger))),
                                    ]),
                                  ),
                                ],
                                if (kIsWeb) ...[
                                  const SizedBox(height: AppSpacing.md),
                                  RecaptchaWidget(
                                    onVerified: (t) => setState(
                                        () => _captchaVerified = t.isNotEmpty)),
                                ],
                                const SizedBox(height: AppSpacing.lg),
                                ElevatedButton(
                                  onPressed: _signUp,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: AppColors.onPrimary,
                                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(AppRadii.md)),
                                    elevation: 0,
                                  ),
                                  child: const Text('Create Account',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Already have an account? ',
                                  style: TextStyle(
                                      color: Color(0xFF3D7A3F),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500)),
                              GestureDetector(
                                onTap: widget.onTap,
                                child: const Text(
                                  'Sign In',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2E6B30),
                                    fontSize: 14,
                                    decoration: TextDecoration.underline,
                                    decorationColor: Color(0xFF2E6B30),
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