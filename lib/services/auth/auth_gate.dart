import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/admin/admin_navigation_screen.dart';
import 'package:loringo_app/screens/teacher/teacher_home_screen.dart';
import 'package:loringo_app/screens/parent/parent_home_screen.dart';
import 'package:loringo_app/screens/parent/parent_register_child_screen.dart';
import 'package:loringo_app/services/auth/login_or_register.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  Future<DocumentSnapshot> _fetchUserDocumentWithRetry(String uid,
      {int maxRetries = 5, Duration delay = const Duration(milliseconds: 800)}) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        final doc = await _firestore.collection('users').doc(uid).get();
        if (doc.exists) return doc;
        await Future.delayed(delay);
      } catch (_) {
        await Future.delayed(delay);
      }
    }
    // After all retries, still not found – return an empty snapshot
    return _firestore.collection('users').doc(uid).get();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _auth.authStateChanges(),
      builder: (context, authSnapshot) {
        if (!authSnapshot.hasData) {
          return const LoginOrRegister();
        }

        final uid = authSnapshot.data!.uid;
        return FutureBuilder<DocumentSnapshot>(
          future: _fetchUserDocumentWithRetry(uid),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            // If still missing after retries – show a helpful error screen
            if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.orange),
                      const SizedBox(height: 16),
                      const Text(
                        'Unable to load your account',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Your user profile could not be found.\nPlease try again or contact support.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () {
                          // Force refresh: sign out and back to login
                          _auth.signOut();
                        },
                        child: const Text('Sign Out'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final userData = userSnapshot.data!.data() as Map<String, dynamic>;
            final role = userData['role'];

            switch (role) {
              case 'admin':
                return const AdminNavigationScreen();
              case 'teacher':
                return const TeacherHomeScreen();
              case 'parent':
                return FutureBuilder<QuerySnapshot>(
                  future: _firestore
                      .collection('students')
                      .where('parentId', isEqualTo: uid)
                      .limit(1)
                      .get(),
                  builder: (context, childSnapshot) {
                    if (childSnapshot.connectionState == ConnectionState.waiting) {
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (!childSnapshot.hasData || childSnapshot.data!.docs.isEmpty) {
                      return const ParentRegisterChildScreen();
                    }
                    return const ParentHomeScreen();
                  },
                );
              default:
                // Invalid role – show error instead of auto sign out
                return Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text('Invalid user role', style: TextStyle(fontSize: 20)),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () => _auth.signOut(),
                          child: const Text('Sign Out'),
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