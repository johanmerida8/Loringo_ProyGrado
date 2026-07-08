import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loringo_app/components/avatar_selector.dart';
import 'package:loringo_app/screens/parent/parent_navigation_screen.dart';
import 'dart:math';

/// Parent Register Child Screen
/// After parent registers, they must register their child
class ParentRegisterChildScreen extends StatefulWidget {
  const ParentRegisterChildScreen({super.key});

  @override
  State<ParentRegisterChildScreen> createState() =>
      _ParentRegisterChildScreenState();
}

class _ParentRegisterChildScreenState extends State<ParentRegisterChildScreen> {
  final childNameController = TextEditingController();
  String? generatedAccessCode;
  bool isRegistered = false;
  String? selectedAvatar;

  @override
  void dispose() {
    childNameController.dispose();
    super.dispose();
  }

  /// Generate unique 6-character access code
  String _generateAccessCode() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // No O, 0, I, 1 to avoid confusion
    final random = Random();
    return List.generate(
      6,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  /// Register child and go to parent home
  void _registerChild() async {
    if (childNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your child\'s name')),
      );
      return;
    }

    try {
      // Get parent auth user
      final parentAuthUser = FirebaseAuth.instance.currentUser;

      if (parentAuthUser == null) {
        throw Exception('No authenticated user found');
      }

      final parentUserId = parentAuthUser.uid;

      // Generate unique access code
      final accessCode = _generateAccessCode();

      // Create student data map
      final newStudentData = {
        'parentId': parentUserId,
        'names': childNameController.text.trim(),
        'accessCode': accessCode,
        'avatar': selectedAvatar ?? 'assets/avatars/parrot.png',
        'state': 1,
        'xp': 0,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Insert to Firebase
      await FirebaseFirestore.instance
          .collection('students')
          .doc(accessCode) // Use access code as document ID for easy lookup
          .set(newStudentData);

      if (mounted) {
        setState(() {
          generatedAccessCode = accessCode;
          isRegistered = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error registering child: $e')));
      }
    }
  }

  /// Copy access code to clipboard
  void _copyAccessCode() {
    if (generatedAccessCode != null) {
      Clipboard.setData(ClipboardData(text: generatedAccessCode!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Code copied to clipboard'),
          backgroundColor: Color(0xFFA2CA71),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Navigate to parent home
  void _goToHome() {
    // Replace current screen with ParentHomeScreen
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const ParentNavigationScreen()),
    );
  }

  /// Show avatar selector
  void _showAvatarSelector() {
    showDialog(
      context: context,
      builder: (context) => AvatarSelector(
        currentAvatar: selectedAvatar,
        onAvatarSelected: (avatar) {
          setState(() {
            selectedAvatar = avatar;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAEDCA),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: isRegistered
                  ? _buildSuccessView()
                  : _buildRegistrationForm(),
            ),
          ),
        ),
      ),
    );
  }

  /// Registration form
  Widget _buildRegistrationForm() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 80),

        // Logo
        Image.asset(
          'assets/images/loro-llave.png',
          width: 160,
          height: 200,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(
              Icons.school,
              size: 100,
              color: Color(0xFF4CAF50),
            );
          },
        ),

        const SizedBox(height: 40),

        const Text(
          'Register Your Child!',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color(0xFFFE5D26),
          ),
        ),

        const SizedBox(height: 12),

        Text(
          'To continue, we need your child\'s name',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey[700]),
        ),

        const SizedBox(height: 40),

        // Child name textfield
        TextField(
          controller: childNameController,
          decoration: InputDecoration(
            labelText: 'Child\'s full name',
            hintText: 'E.g.: Juan Pérez',
            prefixIcon: const Icon(
              Icons.child_care_rounded,
              color: Color(0xFFFFCFB3),
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFFCFB3), width: 2),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Avatar selector button
        GestureDetector(
          onTap: _showAvatarSelector,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selectedAvatar != null
                    ? const Color(0xFFB7E0FF)
                    : Colors.grey.shade300,
                width: selectedAvatar != null ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: selectedAvatar != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            selectedAvatar!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.face_rounded,
                                color: Colors.grey[400],
                                size: 32,
                              );
                            },
                          ),
                        )
                      : Icon(
                          Icons.face_rounded,
                          color: Colors.grey[400],
                          size: 32,
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your child\'s avatar',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        selectedAvatar != null
                            ? 'Avatar selected ✓'
                            : 'Tap to choose an avatar',
                        style: TextStyle(
                          fontSize: 16,
                          color: selectedAvatar != null
                              ? const Color(0xFFA2CA71)
                              : Colors.grey[600],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.grey[400],
                  size: 20,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 40),

        // Register button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _registerChild,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFCFB3),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 3,
            ),
            child: const Text(
              'Register Child',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),

        const SizedBox(height: 80),
      ],
    );
  }

  /// Success view with access code
  Widget _buildSuccessView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),

        // Success icon
        Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFFA2CA71),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            size: 80,
            color: Colors.white,
          ),
        ),

        const SizedBox(height: 30),

        const Text(
          'Child Registered!',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color(0xFFFE5D26),
          ),
        ),

        const SizedBox(height: 12),

        Text(
          childNameController.text,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: Color(0xFF387F39),
          ),
        ),

        const SizedBox(height: 40),

        // Access code card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFB7E0FF), Color(0xFF4A90E2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFB7E0FF).withOpacity(0.5),
                offset: const Offset(0, 6),
                blurRadius: 12,
              ),
            ],
          ),
          child: Column(
            children: [
              const Icon(Icons.key_rounded, size: 48, color: Colors.white),
              const SizedBox(height: 16),
              const Text(
                'Student Access Code',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  generatedAccessCode ?? '',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    color: Color(0xFFFE5D26),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _copyAccessCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF4A90E2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.copy_rounded),
                label: const Text(
                  'Copy Code',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 30),

        // Important message
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFF6E96B).withOpacity(0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF6E96B), width: 2),
          ),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFE67E22),
                    size: 28,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Important!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE67E22),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Save this code. Your child will need it to log in to the app for the first time.',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[800],
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 30),

        // Continue button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _goToHome,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFCFB3),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 3,
            ),
            child: const Text(
              'Continue',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Register another child button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              // Reset form and go back to registration
              setState(() {
                isRegistered = false;
                generatedAccessCode = null;
                childNameController.clear();
                selectedAvatar = null;
              });
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFA2CA71),
              side: const BorderSide(color: Color(0xFFA2CA71), width: 2),
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text(
              'Register Another Child',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),

        const SizedBox(height: 60),
      ],
    );
  }
}
