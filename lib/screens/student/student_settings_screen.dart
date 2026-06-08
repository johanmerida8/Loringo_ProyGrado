import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:loringo_app/services/auth/biometric_service.dart';
import 'package:loringo_app/services/auth/login_or_register.dart';
import 'package:loringo_app/services/auth/student_auth_service.dart';

class StudentSettingsTab extends StatefulWidget {
  final String studentId;
  final String studentName;

  const StudentSettingsTab({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<StudentSettingsTab> createState() => _StudentSettingsTabState();
}

class _StudentSettingsTabState extends State<StudentSettingsTab> {
  bool isBiometricSupported = false;
  bool isBiometricEnabled = false;
  List<BiometricType> availableBiometrics = [];
  String biometricTypeName = 'Biometrics';

  @override
  void initState() {
    super.initState();
    _initBiometrics();
  }

  Future<void> _initBiometrics() async {
    try {
      final isSupported = await BiometricService.isDeviceSupported();
      final canCheck = await BiometricService.canCheckBiometrics();
      final available = await BiometricService.getAvailableBiometrics();
      final isEnabled = await BiometricService.isBiometricEnabled(widget.studentId);

      setState(() {
        isBiometricSupported = isSupported && canCheck;
        availableBiometrics = available;
        biometricTypeName = BiometricService.getBiometricTypeName(available);
        isBiometricEnabled = isEnabled;
      });
    } catch (e) {
      debugPrint('Error initializing biometrics: $e');
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      final authenticated = await BiometricService.authenticate(
        reason: 'Verify your identity to enable biometric login',
      );
      if (authenticated) {
        await BiometricService.setBiometricEnabled(
            userId: widget.studentId, enabled: true);
        setState(() => isBiometricEnabled = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✅ $biometricTypeName login enabled'),
            backgroundColor: Colors.green,
          ));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('❌ Authentication failed'),
            backgroundColor: Colors.red,
          ));
        }
      }
    } else {
      await BiometricService.setBiometricEnabled(
          userId: widget.studentId, enabled: false);
      setState(() => isBiometricEnabled = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$biometricTypeName login disabled'),
          backgroundColor: Colors.grey,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE8F5E9), Colors.white],
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text('Settings',
                  style: TextStyle(
                      fontSize: 32, fontWeight: FontWeight.bold,
                      color: Color(0xFF4CAF50))),
              const SizedBox(height: 40),
              if (isBiometricSupported)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      availableBiometrics.contains(BiometricType.face)
                          ? Icons.face_rounded : Icons.fingerprint_rounded,
                      color: const Color(0xFF4CAF50),
                    ),
                  ),
                  title: Text('$biometricTypeName Login',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Quick and secure login'),
                  trailing: Switch(
                    value: isBiometricEnabled,
                    onChanged: _toggleBiometric,
                    activeColor: const Color(0xFF4CAF50),
                  ),
                ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.logout_rounded, color: Colors.red),
                ),
                title: const Text('Logout',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600,
                        color: Colors.red)),
                subtitle: const Text('Return to login screen'),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Logout'),
                      content: const Text('Are you sure you want to logout?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel')),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await StudentAuthService.clearStudentLogin();
                            if (context.mounted) {
                              Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const LoginOrRegister()),
                                  (route) => false);
                            }
                          },
                          child: const Text('Logout',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const Spacer(),
              Center(
                child: Column(
                  children: [
                    Icon(Icons.school_rounded, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text('Loringo Student',
                        style: TextStyle(
                            fontSize: 16, color: Colors.grey[600],
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('Version 1.0.0',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500])),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}