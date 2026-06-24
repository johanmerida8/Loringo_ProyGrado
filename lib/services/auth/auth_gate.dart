import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/admin/admin_navigation_screen.dart';
import 'package:loringo_app/screens/teacher/teacher_home_screen.dart';
import 'package:loringo_app/screens/parent/parent_home_screen.dart';
import 'package:loringo_app/screens/parent/parent_register_child_screen.dart';
import 'package:loringo_app/services/auth/login_or_register.dart';
import 'package:loringo_app/services/notifications/one_signal_service.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

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

            // Route based on role
            switch (role) {
              case 'admin':
                return const AdminNavigationScreen();
              case 'teacher':
                return const TeacherHomeScreen();
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
    
    return const ParentHomeScreen();
  }
}