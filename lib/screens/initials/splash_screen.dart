import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:loringo_app/services/auth/biometric_service.dart';
import 'package:loringo_app/services/auth/student_auth_service.dart';
import 'package:loringo_app/screens/student/student_main_screen.dart';
import 'package:loringo_app/theme/app_theme.dart';
import 'package:lottie/lottie.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool isLoading = true;
  late Timer _timer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _timer = Timer(const Duration(seconds: 2), _navigate);
  }

  Future<void> _navigate() async {
    if (_navigated || !mounted) return;
    _navigated = true;

    setState(() => isLoading = false);
    await Future.delayed(const Duration(milliseconds: 100));

    // 1. Check for student session FIRST
    final isStudentLoggedIn = await StudentAuthService.isLoggedIn();

    if (isStudentLoggedIn) {
      final studentData = await StudentAuthService.getStudentData();
      final studentId = studentData['studentId'];
      final studentName = studentData['studentName'];
      final studentAvatar = studentData['studentAvatar'];

      if (studentId != null && studentId.isNotEmpty && studentName != null && studentName.isNotEmpty) {
        // Check if biometric is enabled for student
        final biometricEnabled = await BiometricService.isBiometricEnabled(studentId);
        
        if (biometricEnabled) {
          // Show biometric prompt
          final authenticated = await BiometricService.authenticate(
            reason: 'Login to Loringo as $studentName',
          );
          
          if (authenticated && mounted) {
            _goToStudentScreen(studentId, studentName, studentAvatar);
            return;
          } else {
            // Biometric failed - show password/code dialog instead of clearing session
            if (mounted) {
              final shouldRetry = await _showStudentPasswordDialog(studentId, studentName);
              if (shouldRetry && mounted) {
                _goToStudentScreen(studentId, studentName, studentAvatar);
                return;
              } else if (mounted) {
                await StudentAuthService.clearStudentLogin();
                _goToAuthGate();
                return;
              }
            }
          }
        } else {
          if (mounted) {
            _goToStudentScreen(studentId, studentName, studentAvatar);
            return;
          }
        }
      }
    }

    // 2. Check for Firebase Auth user (parent/teacher)
    final firebaseUser = FirebaseAuth.instance.currentUser;
    
    if (firebaseUser != null && mounted) {
      final biometricEnabled = await BiometricService.isBiometricEnabled(firebaseUser.uid);
      
      if (biometricEnabled) {
        final authenticated = await BiometricService.authenticate(
          reason: 'Login to Loringo',
        );
        
        if (authenticated && mounted) {
          _goToAuthGate();
          return;
        } else {
          if (mounted) {
            final shouldRetry = await _showParentPasswordDialog(firebaseUser);
            if (shouldRetry && mounted) {
              _goToAuthGate();
              return;
            } else if (mounted) {
              await FirebaseAuth.instance.signOut();
              _goToAuthGate();
              return;
            }
          }
        }
      } else {
        if (mounted) {
          _goToAuthGate();
          return;
        }
      }
    }

    // 3. No session - go to AuthGate
    if (mounted) {
      _goToAuthGate();
    }
  }

  Future<bool> _showStudentPasswordDialog(String studentId, String studentName) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _StudentPasswordDialog(
        studentId: studentId,
        studentName: studentName,
      ),
    );
    return result == true;
  }

  Future<bool> _showParentPasswordDialog(User user) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ParentPasswordDialog(user: user),
    );
    return result == true;
  }

  void _goToStudentScreen(String studentId, String studentName, String? studentAvatar) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => StudentMainScreen(
          studentId: studentId,
          studentName: studentName,
          studentAvatar: (studentAvatar?.isEmpty ?? true) ? null : studentAvatar,
        ),
      ),
    );
  }

  void _goToAuthGate() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const AuthGate()),
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF6E96B), Color(0xFFBEDC74), Color(0xFFA2CA71)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/loro.png',
              width: 280,
              height: 280,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 20),
            const Text(
              'Loringo',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF387F39),
                fontSize: 32,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 60),
            if (isLoading)
              Lottie.asset(
                'assets/JSON/happy-loader.json',
                width: 120,
                height: 120,
                fit: BoxFit.contain,
                repeat: true,
              )
            else
              Container(),
          ],
        ),
      ),
    );
  }
}

// Student Password Dialog - Beautifully styled with AppTheme
class _StudentPasswordDialog extends StatefulWidget {
  final String studentId;
  final String studentName;

  const _StudentPasswordDialog({
    required this.studentId,
    required this.studentName,
  });

  @override
  State<_StudentPasswordDialog> createState() => _StudentPasswordDialogState();
}

class _StudentPasswordDialogState extends State<_StudentPasswordDialog> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    setState(() => _isLoading = true);
    
    try {
      final snap = await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.studentId)
          .get();
      
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>;
        final storedCode = data['accessCode'] as String?;
        
        if (storedCode?.toUpperCase() == _codeController.text.trim().toUpperCase()) {
          await BiometricService.setBiometricEnabled(
            userId: widget.studentId,
            enabled: false,
          );
          if (mounted) {
            Navigator.pop(context, true);
          }
          return;
        }
      }
      throw Exception('Invalid code');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Invalid access code. Please try again.'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: const Icon(
              Icons.lock_outline,
              color: AppColors.warning,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: Text(
              'Access Code Required',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Biometric authentication failed. Please enter your access code to continue as ${widget.studentName}.',
            style: AppText.body.copyWith(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 12,
              color: AppColors.primary,
            ),
            decoration: InputDecoration(
              labelText: 'Access Code',
              hintText: '••••••',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
            ),
            autofocus: true,
            onSubmitted: (_) => _verifyCode(),
          ),
          if (_isLoading) ...[
            const SizedBox(height: AppSpacing.md),
            const Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
          ),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _verifyCode,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            elevation: 0,
          ),
          child: const Text('Verify'),
        ),
      ],
    );
  }
}

// Parent Password Dialog - Beautifully styled with AppTheme
class _ParentPasswordDialog extends StatefulWidget {
  final User user;

  const _ParentPasswordDialog({required this.user});

  @override
  State<_ParentPasswordDialog> createState() => _ParentPasswordDialogState();
}

class _ParentPasswordDialogState extends State<_ParentPasswordDialog> {
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _verifyPassword() async {
    setState(() => _isLoading = true);
    
    try {
      final credential = EmailAuthProvider.credential(
        email: widget.user.email!,
        password: _passwordController.text,
      );
      await widget.user.reauthenticateWithCredential(credential);
      
      await BiometricService.setBiometricEnabled(
        userId: widget.user.uid,
        enabled: false,
      );
      
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Invalid password. Please try again.'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: const Icon(
              Icons.lock_outline,
              color: AppColors.warning,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: Text(
              'Password Required',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Biometric authentication failed. Please enter your password to continue.',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.primarySoft(0.05),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.email_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    widget.user.email ?? '',
                    style: AppText.caption.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              prefixIcon: const Icon(Icons.password, color: AppColors.primary),
            ),
            autofocus: true,
            onSubmitted: (_) => _verifyPassword(),
          ),
          if (_isLoading) ...[
            const SizedBox(height: AppSpacing.md),
            const Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
          ),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _verifyPassword,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            elevation: 0,
          ),
          child: const Text('Verify'),
        ),
      ],
    );
  }
}