import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:loringo_app/services/auth/biometric_service.dart';
import 'package:loringo_app/services/auth/student_auth_service.dart';
import 'package:loringo_app/screens/student/student_main_screen.dart';
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
        final biometricEnabled = await BiometricService.isBiometricEnabled(studentId);

        if (biometricEnabled) {
          final authenticated = await BiometricService.authenticate(
            reason: 'Login to Loringo as $studentName',
          );
          if (authenticated && mounted) {
            _goToStudentScreen(studentId, studentName, studentAvatar);
            return;
          } else {
            // Biometric failed - clear session and fall through to Firebase check
            await StudentAuthService.clearStudentLogin();
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
        }
      } else {
        if (mounted) {
          _goToAuthGate();
          return;
        }
      }
    }

    // 3. No session - go to AuthGate (which shows LoginOrRegister)
    if (mounted) {
      _goToAuthGate();
    }
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