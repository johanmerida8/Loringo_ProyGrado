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

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);

    _timer = Timer(const Duration(seconds: 3), () async {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        
        // Check if student is logged in
        final isStudentLoggedIn = await StudentAuthService.isStudentLoggedIn();
        
        if (isStudentLoggedIn) {
          // Student is logged in - check biometric
          final studentData = await StudentAuthService.getStudentData();
          final studentId = studentData['studentId'];
          final studentName = studentData['studentName'];
          final studentAvatar = studentData['studentAvatar'];
          
          if (studentId != null && studentName != null) {
            // Check if biometric is enabled for this student
            final isBiometricEnabled = await BiometricService.isBiometricEnabled(studentId);
            
            if (isBiometricEnabled) {
              // Attempt biometric authentication
              final authenticated = await BiometricService.authenticate(
                reason: 'Login to Loringo as $studentName',
              );
              
              if (authenticated && mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => StudentMainScreen(
                      studentId: studentId,
                      studentName: studentName,
                      studentAvatar: studentAvatar,
                    ),
                  ),
                );
                return;
              }
            } else {
              // Biometric not enabled, go directly
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => StudentMainScreen(
                      studentId: studentId,
                      studentName: studentName,
                      studentAvatar: studentAvatar,
                    ),
                  ),
                );
                return;
              }
            }
          }
        }
        
        // Check if parent/teacher is logged in (Firebase Auth)
        final firebaseUser = FirebaseAuth.instance.currentUser;
        if (firebaseUser != null) {
          // Check if biometric is enabled for this parent
          final isBiometricEnabled = await BiometricService.isBiometricEnabled(firebaseUser.uid);
          
          if (isBiometricEnabled) {
            // Attempt biometric authentication
            final authenticated = await BiometricService.authenticate(
              reason: 'Login to Loringo',
            );
            
            if (authenticated && mounted) {
              // Auth gate will handle routing to correct screen
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => const AuthGate(),
                ),
              );
              return;
            }
          }
        }
        
        // No biometric or authentication failed - go to auth gate/login
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const AuthGate(),
            ),
          );
        }
      }
    });
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

  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFF6E96B),
              Color(0xFFBEDC74),
              Color(0xFFA2CA71),
            ],
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