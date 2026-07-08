import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/admin/admin_navigation_screen.dart';
import 'package:loringo_app/screens/teacher/teacher_home_screen.dart';
import 'package:loringo_app/screens/parent/parent_navigation_screen.dart';
import 'package:loringo_app/screens/parent/parent_register_child_screen.dart';
import 'package:loringo_app/screens/student/student_main_screen.dart';
import 'package:loringo_app/services/auth/login_or_register.dart';
import 'package:loringo_app/services/auth/student_auth_service.dart';
import 'package:loringo_app/services/notifications/one_signal_service.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    // Student sessions live entirely in SharedPreferences (access-code
    // login, no FirebaseAuth.currentUser at all), so they must be
    // checked BEFORE the FirebaseAuth stream below — otherwise a
    // logged-in student always falls through to "no auth data" and gets
    // sent to LoginOrRegister. This matters especially on web, where
    // main.dart routes straight to AuthGate (skipping SplashScreen,
    // which is the only place this check used to happen), so every hot
    // reload was re-triggering exactly this bug.
    return FutureBuilder<bool>(
      future: StudentAuthService.isStudentLoggedIn(),
      builder: (context, studentSnapshot) {
        if (studentSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (studentSnapshot.data == true) {
          return FutureBuilder<Map<String, dynamic>>(
            future: StudentAuthService.getStudentData(),
            builder: (context, studentDataSnapshot) {
              if (studentDataSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              final data = studentDataSnapshot.data;
              final studentId = data?['studentId'] as String?;
              final studentName = data?['studentName'] as String?;
              if (data != null &&
                  studentId != null && studentId.isNotEmpty &&
                  studentName != null && studentName.isNotEmpty) {
                final avatar = data['studentAvatar'] as String?;
                return StudentMainScreen(
                  studentId: studentId,
                  studentName: studentName,
                  studentAvatar: (avatar?.isEmpty ?? true) ? null : avatar,
                );
              }
              // Stored flag said "logged in" but data is incomplete/corrupt
              // — fall through to normal auth instead of getting stuck.
              return const _FirebaseAuthGate();
            },
          );
        }

        return const _FirebaseAuthGate();
      },
    );
  }
}

/// The original AuthGate logic, unchanged — only reached once we've
/// confirmed there's no active student session.
class _FirebaseAuthGate extends StatelessWidget {
  const _FirebaseAuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        
        if (!authSnapshot.hasData) {
          return const LoginOrRegister();
        }

        final uid = authSnapshot.data!.uid;
        
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
          key: ValueKey(uid),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (userSnapshot.hasError) {
              debugPrint('Error loading user document: ${userSnapshot.error}');
              return _buildErrorScreen(
                context,
                'Error loading user data: ${userSnapshot.error}',
              );
            }

            if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
              debugPrint('User document not found for UID: $uid');
              return _buildErrorScreen(
                context,
                'User profile not found. Please contact support.',
              );
            }

            final userData = userSnapshot.data!.data() as Map<String, dynamic>;
            final role = userData['role'] as String?;
            
            debugPrint('User role: $role for UID: $uid');

            if (!kIsWeb && (role == 'parent' || role == 'teacher')) {
              _initializeNotificationsForRole(uid, role!);
            }

            switch (role) {
              case 'admin':
                return AdminNavigationScreen();
              case 'teacher':
                return TeacherHomeScreen();
              case 'parent':
                return _ParentRouter(parentId: uid);
              default:
                return _buildErrorScreen(context, 'Invalid user role: $role');
            }
          },
        );
      },
    );
  }

  void _initializeNotificationsForRole(String uid, String role) {
    OneSignalNotificationService.initializeUser(uid).catchError((e) {
      debugPrint('OneSignal initialization error for $role: $e');
    });
  }

  Widget _buildErrorScreen(BuildContext context, String message) {
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
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const AuthGate()),
                  );
                }
              },
              child: const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }
}

// Parent router - checks if parent has children
class _ParentRouter extends StatefulWidget {
  final String parentId;

  const _ParentRouter({required this.parentId});

  @override
  State<_ParentRouter> createState() => _ParentRouterState();
}

class _ParentRouterState extends State<_ParentRouter> with AutomaticKeepAliveClientMixin {
  bool? _hasChildren;
  bool _isLoading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _checkChildren();
  }

  Future<void> _checkChildren() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('parentId', isEqualTo: widget.parentId)
          .limit(1)
          .get();
      
      if (mounted) {
        setState(() {
          _hasChildren = snapshot.docs.isNotEmpty;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error checking children: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
          _hasChildren = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text('Error loading parent data'),
              const SizedBox(height: 8),
              Text(_error!),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error = null;
                    _checkChildren();
                  });
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_hasChildren == false) {
      return const ParentRegisterChildScreen();
    }
    
    return const ParentNavigationScreen();
  }
}