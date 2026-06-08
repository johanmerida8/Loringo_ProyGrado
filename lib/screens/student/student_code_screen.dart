import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/student/student_main_screen.dart';
import 'package:loringo_app/services/auth/student_auth_service.dart';

/// Student Code Screen
/// Student enters their access code to login
class StudentCodeScreen extends StatefulWidget {
  const StudentCodeScreen({super.key});

  @override
  State<StudentCodeScreen> createState() => _StudentCodeScreenState();
}

class _StudentCodeScreenState extends State<StudentCodeScreen> {
  final accessCodeController = TextEditingController();
  
  bool isLoading = false;
  bool _isNavigating = false;  // ← Add this


  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  @override
  void dispose() {
    accessCodeController.dispose();
    super.dispose();
  }

  // check if student already has a saved session
  Future<void> _checkExistingSession() async {
    if (_isNavigating) return;  // ← Prevent multiple navigation
    if (await StudentAuthService.isLoggedIn()) {
      _isNavigating = true;  // ← Set flag
      final loginData = await StudentAuthService.getStoredStudentLogin();
      if (loginData != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => StudentMainScreen(
              studentId: loginData['studentId']!,
              studentName: loginData['studentName']!,
              studentAvatar: loginData['studentAvatar']?.isEmpty ?? true 
                  ? null 
                  : loginData['studentAvatar'],
            ),
          ),
        );
      }
    }
  }

  /// Login with access code
  void _loginWithCode() async {
    final enteredCode = accessCodeController.text.trim().toUpperCase();

    if (accessCodeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your access code'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      // Find student by access code
      final studentSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where(
            'accessCode',
            isEqualTo: accessCodeController.text.trim().toUpperCase(),
          )
          .limit(1)
          .get();

      if (studentSnapshot.docs.isEmpty) {
        throw Exception('Invalid access code');
      }

      final studentDoc = studentSnapshot.docs.first;
      final studentData = studentDoc.data();
      final studentId = studentDoc.id;
      final studentName = studentData['names'] as String;
      final studentAvatar = studentData['avatar'] as String?;

      // Save student login state locally
      await StudentAuthService.saveStudentLogin(
        studentId: studentId,
        studentName: studentName,
        studentAvatar: studentAvatar,
        accessCode: enteredCode,
      );

      if (mounted) {
        // Navigate to student main screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => StudentMainScreen(
              studentId: studentId,
              studentName: studentName,
              studentAvatar: studentAvatar,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Incorrect access code'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAEDCA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFB7E0FF),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: const Text(
          'Student Access',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              children: [
                const SizedBox(height: 40),

                // Student illustration
                Image.asset(
                  'assets/images/loro-llave.png',
                  width: 180,
                  height: 220,
                  fit: BoxFit.contain,
                ),

                const SizedBox(height: 40),

                const Text(
                  'Hello Student!',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4A90E2),
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  'Enter the access code your parent gave you',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[700],
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 40),

                // Access code textfield
                TextField(
                  controller: accessCodeController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    hintText: 'ABC123',
                    hintStyle: TextStyle(
                      color: Colors.grey[400],
                      letterSpacing: 8,
                    ),
                    prefixIcon: const Icon(
                      Icons.vpn_key_rounded,
                      color: Color(0xFFB7E0FF),
                      size: 32,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: Colors.grey.shade300,
                        width: 2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: Color(0xFFB7E0FF),
                        width: 3,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // Login button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _loginWithCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB7E0FF),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                    ),
                    child: isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Enter',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 30),

                // Help message
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6E96B).withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFF6E96B),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.help_outline_rounded,
                        color: Color(0xFFE67E22),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'If you don\'t have your code, ask your parent',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
