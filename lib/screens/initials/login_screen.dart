import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:loringo_app/components/my_button.dart';
import 'package:loringo_app/components/recaptcha/recaptcha_widget.dart';
import 'package:loringo_app/components/my_loading.dart';
import 'package:loringo_app/components/my_textfield.dart';
import 'package:loringo_app/components/responsive.dart';
import 'package:loringo_app/screens/initials/reset_password_screen.dart';
import 'package:loringo_app/screens/student/student_code_screen.dart';
import 'package:loringo_app/services/auth/auth_gate.dart';
import 'package:loringo_app/services/auth/student_auth_service.dart';
// import 'package:loringo_app/screens/register_screen.dart';

class LoginScreen extends StatefulWidget {
  final void Function()? onTap;
  const LoginScreen({super.key, required this.onTap});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  String errorMsg = '';
  bool isLoading = false;
  bool _captchaVerified = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> signIn() async {
    // Captcha required on web
    if (kIsWeb && !_captchaVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete the captcha'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Manual validation
    if (emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email is required'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!emailController.text.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password is required'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
      errorMsg = '';
    });

    try {
      await StudentAuthService.clearStudentLogin(); // Clear any existing student session

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
      
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()), 
          (route) => false,
        );
      }

    } on FirebaseAuthException {
      resetRecaptcha();
      setState(() {
        isLoading = false;
        _captchaVerified = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email or password is incorrect'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // show loading animation if logging in
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFFAEDCA),
        body: MyLoading(),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFAEDCA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Responsive(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 50),

                  Image.asset(
                    'assets/images/loro-llave.png',
                    width: 160,
                    height: 250,
                    fit: BoxFit.contain,
                  ),

                  const Text(
                    'Welcome back, we missed you!',
                    style: TextStyle(fontSize: 16),
                  ),

                  const SizedBox(height: 25),

                  MyTextField(
                    controller: emailController,
                    hintText: 'Email',
                    obscureText: false,
                    isEnabled: true,
                  ),

                  const SizedBox(height: 15),

                  MyTextField(
                    controller: passwordController,
                    hintText: 'Password',
                    obscureText: true,
                    isEnabled: true,
                  ),

                  const SizedBox(height: 15),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const ResetPasswordScreen(),
                          ),
                        ),
                        child: const Text('Forgot password?'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  if (kIsWeb) ...[
                    RecaptchaWidget(
                      onVerified: (token) =>
                          setState(() => _captchaVerified = token.isNotEmpty),
                    ),
                    const SizedBox(height: 16),
                  ],

                  MyButton(
                    onTap: signIn,
                    text: 'Sign In',
                    color: const Color.fromRGBO(162, 202, 113, 1),
                  ),

                  const SizedBox(height: 30),

                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const StudentCodeScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      'Student Login',
                      style: TextStyle(
                        color: Color(0xFF4A90E2),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Not a member?'),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: widget.onTap,
                        child: const Text(
                          'Register now',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
