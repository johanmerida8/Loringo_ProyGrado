import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:loringo_app/components/wave_form.dart';
import 'package:loringo_app/screens/student/student_main_screen.dart';
import 'package:loringo_app/services/auth/student_auth_service.dart';
import 'package:loringo_app/theme/app_theme.dart';

const _kTopGradient = LinearGradient(
  colors: [Color(0xFFF6E96B), Color(0xFFBEDC74), Color(0xFFA2CA71)],
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
);

const _kBottomColor = Color(0xFFF2F8F2);

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
              studentAvatar: data['studentAvatar']?.isEmpty ?? true
                  ? null
                  : data['studentAvatar'],
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
          content: const Text('Please enter your access code'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('students')
          .where('accessCode', isEqualTo: _codeCtrl.text.trim().toUpperCase())
          .limit(1)
          .get();

      if (snap.docs.isEmpty) throw Exception('Invalid');

      final doc = snap.docs.first;
      final data = doc.data();
      final studentId = doc.id;
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Incorrect access code. Please try again.'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    // Make hero smaller on web
    final heroH = kIsWeb ? screenH * 0.40 : screenH * 0.46;
    final maxW = kIsWeb ? 450.0 : double.infinity;
    final horizontalPadding = kIsWeb ? AppSpacing.xl * 2 : AppSpacing.lg;

    return Scaffold(
      backgroundColor: _kBottomColor,
      body: Stack(
        children: [
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
                      'assets/images/loringo-playful.png',
                      width: kIsWeb ? 130 : 150,
                      height: kIsWeb ? 150 : 170,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Text(
                      'Hello, Student!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: kIsWeb ? 26 : 30,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E6B30),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'Enter your access code to get started',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: kIsWeb ? 13 : 15,
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
              height: 40,
              waveIntensity: 0.8,
            ),
          ),

          // Scrollable content
          Positioned(
            top: heroH + 15,
            left: 0,
            right: 0,
            bottom: 0,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: AppSpacing.md),
                        
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppRadii.lg + 4),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.10),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
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
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppRadii.md),
                                  ),
                                  elevation: 0,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.onPrimary,
                                        ),
                                      )
                                    : const Text(
                                        'Enter',
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                      ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: AppSpacing.md),

                        Container(
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
                              const Icon(
                                Icons.help_outline_rounded,
                                color: AppColors.primary,
                                size: 18,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  "Don't have a code? Ask your parent.",
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

                        const SizedBox(height: AppSpacing.lg),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Back button
          Positioned(
            top: kIsWeb ? 40 : 50,
            left: kIsWeb ? 30 : 20,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Color(0xFF2E6B30),
                    size: 16,
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