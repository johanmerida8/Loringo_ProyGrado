import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/auth_layout.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/student/student_main_screen.dart';
import 'package:loringo_app/services/auth/student_auth_service.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/services/firebase_refs.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:loringo_app/utils/access_code_hasher.dart';

class StudentCodeScreen extends StatefulWidget {
  const StudentCodeScreen({super.key});

  @override
  State<StudentCodeScreen> createState() => _StudentCodeScreenState();
}

class _StudentCodeScreenState extends State<StudentCodeScreen> {
  final _codeCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkExistingSession() async {
    if (_isNavigating) return;
    if (await StudentAuthService.isLoggedIn()) {
      _isNavigating = true;
      final data = await StudentAuthService.getStoredStudentLogin();
      if (data != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => StudentMainScreen(
              studentId: data['studentId']!,
              studentName: data['studentName']!,
              studentAvatar:
                  data['studentAvatar']?.isEmpty ?? true ? null : data['studentAvatar'],
            ),
          ),
        );
      }
    }
  }

  Future<void> _loginWithCode() async {
    if (_codeCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('common.studentAccessCodeMsg'.tr()),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final data = await Database(firestore: firestoreInstance)
          .findStudentByAccessCode(_codeCtrl.text.trim());

      if (data == null) throw Exception('Invalid');

      final studentId = data['id'] as String;
      final studentName = data['names'] as String;
      final avatar = data['avatar'] as String?;

      await StudentAuthService.saveStudentLogin(
        studentId: studentId,
        studentName: studentName,
        studentAvatar: avatar,
        accessCode: _codeCtrl.text.trim().toUpperCase(),
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => StudentMainScreen(
              studentId: studentId,
              studentName: studentName,
              studentAvatar: avatar,
            ),
          ),
        );
      }
    } catch (e) {
      // ignore: avoid_print
      print('[STUDENT LOGIN] typed="${_codeCtrl.text.trim()}" '
          'hash=${AccessCodeHasher.hash(_codeCtrl.text.trim())} failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('student.student_code_screen.incorrectAccessCodeMsg'.tr()),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return AuthLayout(
      mobileHeroFraction: 0.46,
      onBack: () => Navigator.pop(context),
      heroVisual: Image.asset(
        'assets/images/loringo-playful.png',
        width: 130,
        height: 150,
        fit: BoxFit.contain,
      ),
      title: 'common.helloStudent'.tr(),
      subtitle: 'student.student_code_screen.subtitle'.tr(),
      form: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _codeCtrl,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: 10,
              color: AppColors.primary,
            ),
            decoration: InputDecoration(
              hintText: '······',
              hintStyle: TextStyle(
                color: Colors.grey.shade300,
                letterSpacing: 10,
                fontSize: 28,
              ),
              filled: true,
              fillColor: AppColors.scaffoldBackground,
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
                borderSide: BorderSide(color: AppColors.divider, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
                borderSide: const BorderSide(color: AppColors.primary, width: 2.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: AppSpacing.md,
                horizontal: AppSpacing.md,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ElevatedButton(
            onPressed: _isLoading ? null : _loginWithCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              disabledBackgroundColor: Colors.grey.shade300,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.onPrimary),
                  )
                : Text('common.enter'.tr(),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      footer: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.md),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.help_outline_rounded, color: AppColors.primary, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'common.askParent'.tr(),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}