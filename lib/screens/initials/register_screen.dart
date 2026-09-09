import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/auth_layout.dart';
import 'package:loringo_app/components/my_loading.dart';
import 'package:loringo_app/components/policy_consent_checkbox.dart';
import 'package:loringo_app/components/my_textfield.dart';
import 'package:loringo_app/components/recaptcha/recaptcha_widget.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/services/firebase_refs.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/password_utils.dart';

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
  bool _consentGiven = false;

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
      setState(() => _errorMsg = 'common.nameValidation'.tr());
      return;
    }
    if (_emailCtrl.text.trim().isEmpty) {
      setState(() => _errorMsg = 'common.emailValidation1'.tr());
      return;
    }
    if (!_emailCtrl.text.contains('@')) {
      setState(() => _errorMsg = 'common.emailValidation2'.tr());
      return;
    }
    if (_passCtrl.text.isEmpty) {
      setState(() => _errorMsg = 'common.passwordValidation1'.tr());
      return;
    }
    if (!PasswordUtils.isPasswordValid(_passCtrl.text)) {
      setState(() => _errorMsg =
          '${'common.passwordSecurityValidation'.tr()}: ${PasswordUtils.getPasswordRequirements(_passCtrl.text).join(', ')}');
      return;
    }
    if (_confirmCtrl.text.isEmpty) {
      setState(() => _errorMsg = 'common.confirmPasswordErr'.tr());
      return;
    }
    if (_confirmCtrl.text != _passCtrl.text) {
      setState(() => _errorMsg = 'common.passwordMatch'.tr());
      return;
    }
    final isAdmin =
        name.toLowerCase() == 'admin' || name.toLowerCase() == 'administrador';
    if (!isAdmin && _selectedRole == null) {
      setState(() => _errorMsg = 'common.selectRoleValidation'.tr());
      return;
    }
    if (kIsWeb && !_captchaVerified) {
      setState(() => _errorMsg = 'common.captcha'.tr());
      return;
    }
    if (!_consentGiven) {
      setState(() => _errorMsg = 'initials.register_screen.consentRequired'.tr());
      return;
    }

    setState(() => _isLoading = true);

    // Checked BEFORE creating the Firebase Auth account (not just inside
    // Database.createUser afterward) so a blocked attempt never leaves
    // behind an authenticated Firebase user with no Firestore profile —
    // that orphaned-account state used to be possible when this check
    // only ran after authInstance.createUserWithEmailAndPassword.
    if (isAdmin) {
      final hasAdmin =
          await Database(firestore: firestoreInstance).imageManagerExists();
      if (hasAdmin) {
        setState(() {
          _isLoading = false;
          _errorMsg = 'initials.register_screen.adminExists'.tr();
        });
        return;
      }
    }

    try {
      final cred = await authInstance.createUserWithEmailAndPassword(
          email: _emailCtrl.text.trim(), password: _passCtrl.text.trim());
      final uid = cred.user?.uid ?? (throw Exception('No UID'));
      final role = isAdmin ? 'image_manager' : _selectedRole!;

      // Routed through Database.createUser (instead of writing to
      // Firestore directly) so the real admin-singleton-promotion rule
      // (only one 'image_manager' account allowed) is actually enforced
      // on signup, not just in Database's own unit tests. Explicitly
      // passes firestoreInstance so this stays swappable in tests, the
      // same as every other Firebase call on this screen.
      await Database(firestore: firestoreInstance).createUser(
        uid: uid,
        name: name,
        email: _emailCtrl.text.trim(),
        role: role,
        privacyPolicyAccepted: _consentGiven,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('initials.register_screen.accountCreatedAs'
              .tr(namedArgs: {'role': role})),
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
            ? 'initials.register_screen.emailAlreadyRegistered'.tr()
            : e.code == 'weak-password'
                ? 'initials.register_screen.weakPassword'.tr()
                : e.code == 'invalid-email'
                    ? 'initials.register_screen.invalidEmailFormat'.tr()
                    : (e.message ?? 'initials.register_screen.registrationFailed'.tr());
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
    context.watch<LocaleProvider>();
    if (_isLoading) {
      return const Scaffold(
        body: ColoredBox(
          color: Color(0xFFBEDC74),
          child: MyLoading(),
        ),
      );
    }

    return AuthLayout(
      mobileHeroFraction: 0.38,
      heroVisual: Image.asset(
        'assets/images/loro-llave.png',
        width: 100,
        height: 135,
        fit: BoxFit.contain,
      ),
      title: 'common.createAccountMsg'.tr(),
      subtitle: 'initials.register_screen.signUpSubtitle'.tr(),
      form: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MyTextField(
            controller: _nameCtrl,
            hintText: 'common.fullname'.tr(),
            obscureText: false,
            isEnabled: true,
            onChanged: (_) => _checkAdminName(),
          ),
          const SizedBox(height: AppSpacing.md),
          MyTextField(
            controller: _emailCtrl,
            hintText: 'common.email'.tr(),
            obscureText: false,
            isEnabled: true,
          ),
          const SizedBox(height: AppSpacing.md),
          MyTextField(
            controller: _passCtrl,
            hintText: 'common.password'.tr(),
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
              Text(passwordStrengthLabel(_passStrength),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: PasswordUtils.getPasswordStrengthColor(_passCtrl.text))),
            ]),
            const SizedBox(height: AppSpacing.xs),
            Text('common.passwordCases'.tr(),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],
          const SizedBox(height: AppSpacing.md),
          MyTextField(
            controller: _confirmCtrl,
            hintText: 'common.confirmPassword'.tr(),
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.admin_panel_settings_rounded,
                      color: Color(0xFFD97706), size: 24),
                  const SizedBox(width: AppSpacing.sm),
                  Text('initials.register_screen.registeringAsAdmin'.tr(),
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFD97706))),
                ],
              ),
            )
          else ...[
            Text('initials.register_screen.iAmA'.tr(),
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
                      Text('common.teacher'.tr(),
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
                      Text('common.parent'.tr(),
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
                onVerified: (t) => setState(() => _captchaVerified = t.isNotEmpty)),
          ],
          const SizedBox(height: AppSpacing.sm),
          PolicyConsentCheckbox(
            value: _consentGiven,
            onChanged: (v) => setState(() => _consentGiven = v),
            label: 'initials.register_screen.consentLabel'.tr(),
          ),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(
            onPressed: _signUp,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
              elevation: 0,
            ),
            child: Text('initials.register_screen.createAccountButton'.tr(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('initials.register_screen.alreadyHaveAccount'.tr(),
              style: const TextStyle(
                  color: Color(0xFF3D7A3F),
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          GestureDetector(
            onTap: widget.onTap,
            child: Text(
              'common.signIn'.tr(),
              style: const TextStyle(
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
    );
  }
}