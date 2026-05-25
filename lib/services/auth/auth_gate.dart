import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/admin/admin_navigation_screen.dart';
import 'package:loringo_app/screens/teacher/teacher_home_screen.dart';
import 'package:loringo_app/screens/parent/parent_home_screen.dart';
import 'package:loringo_app/screens/parent/parent_register_child_screen.dart';
import 'package:loringo_app/services/auth/login_or_register.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // User not logged in
        if (!snapshot.hasData) {
          return const LoginOrRegister();
        }

        // User logged in - check role
        final uid = snapshot.data!.uid;
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
              // User document doesn't exist
              return const LoginOrRegister();
            }

            final userData = userSnapshot.data!.data() as Map<String, dynamic>;
            final role = userData['role'];

            // Route based on role (admin, teacher, parent only)
            // Students use access codes and don't authenticate through Firebase
            switch (role) {
              case 'admin':
                return const AdminNavigationScreen();
              case 'teacher':
                return const TeacherHomeScreen();
              case 'parent':
                // Check if parent has children registered
                return FutureBuilder<QuerySnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('students')
                      .where('parentId', isEqualTo: uid)
                      .limit(1)
                      .get(),
                  builder: (context, childSnapshot) {
                    if (childSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    }

                    // If no children registered, go to register child screen
                    if (!childSnapshot.hasData ||
                        childSnapshot.data!.docs.isEmpty) {
                      return const ParentRegisterChildScreen();
                    }

                    // If children registered, go to parent home
                    return const ParentHomeScreen();
                  },
                );
              default:
                // Missing or invalid role - sign out and redirect to login
                // This prevents auto-logout loops
                FirebaseAuth.instance.signOut();
                return Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Account Error',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'Your account doesn\'t have a valid role.\nPlease contact support.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () {
                            // Force navigation to login
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginOrRegister(),
                              ),
                            );
                          },
                          child: const Text('Back to Login'),
                        ),
                      ],
                    ),
                  ),
                );
            }
          },
        );
      },
    );
  }
}
