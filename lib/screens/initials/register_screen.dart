import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:loringo_app/components/my_button.dart';
import 'package:loringo_app/components/my_loading.dart';
import 'package:loringo_app/components/my_textfield.dart';
import 'package:loringo_app/components/recaptcha/recaptcha_widget.dart';
import 'package:loringo_app/components/responsive.dart';
// import 'package:loringo_app/screens/initials/login_screen.dart';
import 'package:loringo_app/utils/password_utils.dart';

class RegisterScreen extends StatefulWidget {
  final void Function()? onTap;

  const RegisterScreen({super.key, required this.onTap});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const Color greenPrimary = Color(0xFF4CAF50);

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isLoading = false;
  String errorMsg = '';
  bool isAdminName = false;
  String? selectedUserType; // 'teacher', 'parent', 'student'
  String passwordStrength = '';
  bool showPasswordStrength = false;
  bool _captchaVerified = false;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  void _checkAdminName() {
    final name = nameController.text.trim().toLowerCase();
    final isAdmin = name == 'admin' || name == 'administrador';
    if (isAdmin != isAdminName) {
      setState(() {
        isAdminName = isAdmin;
        if (isAdmin) {
          selectedUserType = null;
        }
      });
    }
  }

  Future<void> signUp() async {
    // Manual validation
    setState(() {
      errorMsg = '';
    });

    final name = nameController.text.trim();

    if (name.isEmpty) {
      setState(() {
        errorMsg = 'Name is required';
      });
      return;
    }

    if (emailController.text.trim().isEmpty) {
      setState(() {
        errorMsg = 'Email is required';
      });
      return;
    }

    if (!emailController.text.contains('@')) {
      setState(() {
        errorMsg = 'Please enter a valid email';
      });
      return;
    }

    if (passwordController.text.isEmpty) {
      setState(() {
        errorMsg = 'Password is required';
      });
      return;
    }

    if (!PasswordUtils.isPasswordValid(passwordController.text)) {
      final requirements = PasswordUtils.getPasswordRequirements(passwordController.text);
      setState(() {
        errorMsg = 'Password must contain: ${requirements.join(', ')}';
      });
      return;
    }

    if (confirmPasswordController.text.isEmpty) {
      setState(() {
        errorMsg = 'Please confirm your password';
      });
      return;
    }

    if (confirmPasswordController.text != passwordController.text) {
      setState(() {
        errorMsg = 'Passwords do not match';
      });
      return;
    }
    final nameLower = name.toLowerCase();
    final isAdmin = nameLower == 'admin' || nameLower == 'administrador';

    // Validate user type selection (skip for admin)
    if (!isAdmin && selectedUserType == null) {
      setState(() {
        errorMsg = 'Please select your role: Teacher or Parent';
      });
      return;
    }

    // Captcha required on web
    if (kIsWeb && !_captchaVerified) {
      setState(() => errorMsg = 'Please complete the captcha');
      return;
    }

    setState(() {
      isLoading = true;
      errorMsg = '';
    });

    try {
      // Check if admin limit reached
      if (isAdmin) {
        final adminSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'admin')
            .get();

        if (adminSnapshot.docs.length >= 3) {
          setState(() {
            errorMsg = 'Maximum of 3 administrators already exists';
            isLoading = false;
          });
          return;
        }
      }

      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: emailController.text.trim(),
            password: passwordController.text.trim(),
          );

      final uid = credential.user?.uid;
      if (uid == null) throw Exception('Failed to get user ID');

      // Determine role
      final role = isAdmin ? 'admin' : selectedUserType!;

      // Create user document
      await FirebaseFirestore.instance.collection("users").doc(uid).set({
        "name": name,
        "email": emailController.text.trim(),
        "role": role,
        "xp": 0,
        "streak": 0,
        "language": "Spanish",
        "state": 1,
        "createdAt": FieldValue.serverTimestamp(),
      });

      // Clone levels only for students
      if (role == 'student') {
        final levelsSnapshot = await FirebaseFirestore.instance
            .collection("levels")
            .get();
        for (final doc in levelsSnapshot.docs) {
          await FirebaseFirestore.instance
              .collection("users")
              .doc(uid)
              .collection("levels")
              .doc(doc.id)
              .set({
                'isUnlocked': doc['levelNumber'] == 1,
                'levelNumber': doc['levelNumber'],
                'title': doc['title'],
              });
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account created successfully as $role'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      resetRecaptcha();
      setState(() {
        _captchaVerified = false;
        // Check for specific error codes
        if (e.code == 'email-already-in-use') {
          errorMsg =
              'This email is already registered. Please use a different email or sign in.';
        } else if (e.code == 'weak-password') {
          errorMsg = 'Password is too weak. Please use a stronger password.';
        } else if (e.code == 'invalid-email') {
          errorMsg = 'Invalid email format. Please check your email address.';
        } else {
          errorMsg = e.message ?? 'An error occurred during registration';
        }
      });
    } catch (e) {
      resetRecaptcha();
      setState(() {
        _captchaVerified = false;
        errorMsg = e.toString();
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
          child: Responsive(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 25.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 50),

                  //logo
                  Image.asset(
                    'assets/images/loro-llave.png',
                    width: 160,
                    height: 250,
                    fit: BoxFit.contain,
                  ),

                  Text('Create your account!', style: TextStyle(fontSize: 16)),

                  const SizedBox(height: 25),
                  //name textfield
                  MyTextField(
                    controller: nameController,
                    hintText: 'Full Name',
                    obscureText: false,
                    isEnabled: true,
                    onChanged: (value) => _checkAdminName(),
                  ),

                  const SizedBox(height: 15),

                  //email textfield
                  MyTextField(
                    controller: emailController,
                    hintText: 'Email',
                    obscureText: false,
                    isEnabled: true,
                  ),

                  const SizedBox(height: 15),
                  //password textfield
                  MyTextField(
                    controller: passwordController,
                    hintText: 'Password',
                    obscureText: true,
                    isEnabled: true,
                    onChanged: (value) {
                      setState(() {
                        passwordStrength = PasswordUtils.getPasswordStrength(value);
                        showPasswordStrength = value.isNotEmpty;
                      });
                    },
                  ),
                  if (showPasswordStrength) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: PasswordUtils.getPasswordStrengthColor(passwordController.text),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          passwordStrength,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: PasswordUtils.getPasswordStrengthColor(passwordController.text),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Use 8+ chars, uppercase, lowercase, number & special character',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 15),
                  //confirm password textfield
                  MyTextField(
                    controller: confirmPasswordController,
                    hintText: 'Confirm Password',
                    obscureText: true,
                    isEnabled: true,
                  ),

                  const SizedBox(height: 25),

                  // Show admin indicator or user type selection
                  if (isAdminName)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFFD700),
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.admin_panel_settings,
                            color: Color(0xFFD97706),
                            size: 28,
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Registering as Administrator',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFD97706),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    // User type selection
                    const Text(
                      'Who are you?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF387F39),
                      ),
                    ),

                    const SizedBox(height: 15),

                    // Radio buttons in rows
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selectedUserType == 'teacher'
                                    ? const Color(0xFFA2CA71)
                                    : Colors.grey.shade300,
                                width: 2,
                              ),
                            ),
                            child: RadioListTile<String>(
                              title: const Text(
                                'Teacher',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              value: 'teacher',
                              groupValue: selectedUserType,
                              activeColor: const Color(0xFFA2CA71),
                              onChanged: (value) {
                                setState(() {
                                  selectedUserType = value;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selectedUserType == 'parent'
                                    ? const Color(0xFFFFCFB3)
                                    : Colors.grey.shade300,
                                width: 2,
                              ),
                            ),
                            child: RadioListTile<String>(
                              title: const Text(
                                'Parent',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              value: 'parent',
                              groupValue: selectedUserType,
                              activeColor: const Color(0xFFFFCFB3),
                              onChanged: (value) {
                                setState(() {
                                  selectedUserType = value;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Show error message if validation fails
                  if (errorMsg.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 15),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        errorMsg,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 14,
                        ),
                      ),
                    ),

                  const SizedBox(height: 20),

                  if (kIsWeb) ...[
                    RecaptchaWidget(
                      onVerified: (token) =>
                          setState(() => _captchaVerified = token.isNotEmpty),
                    ),
                    const SizedBox(height: 16),
                  ] else
                    const SizedBox(height: 10),

                  MyButton(
                    onTap: signUp,
                    text: 'Register',
                    color: const Color.fromRGBO(162, 202, 113, 1),
                  ),

                  const SizedBox(height: 50),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Already a member?'),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: widget.onTap,
                        child: Text(
                          'Sign In',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
