import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/services/auth/biometric_service.dart';
import 'package:loringo_app/services/auth/login_or_register.dart';
import 'package:loringo_app/theme/app_theme.dart';

class BiometricVerificationScreen extends StatefulWidget {
  final Widget child;
  final String userId;
  
  const BiometricVerificationScreen({
    super.key,
    required this.child,
    required this.userId,
  });

  @override
  State<BiometricVerificationScreen> createState() => _BiometricVerificationScreenState();
}

class _BiometricVerificationScreenState extends State<BiometricVerificationScreen> {
  bool _isVerifying = true;
  bool _hasShownBiometric = false;
  bool _isAuthenticated = false;
  String? _errorMessage;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _loadUserEmail();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadUserEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userEmail = user.email;
    }
    _verifyBiometric();
  }

  Future<void> _verifyBiometric() async {
    // Skip if already authenticated
    if (_isAuthenticated) return;
    
    // Prevent multiple calls
    if (_hasShownBiometric) return;
    
    // Check if biometric is enabled for this user
    final isEnabled = await BiometricService.isBiometricEnabled(widget.userId);
    
    if (!isEnabled) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _isAuthenticated = true;
        });
      }
      return;
    }

    // Check if device supports biometrics
    final isSupported = await BiometricService.isDeviceSupported();
    if (!isSupported) {
      if (mounted) {
        // Disable biometric since device doesn't support it
        await BiometricService.setBiometricEnabled(
          userId: widget.userId, 
          enabled: false,
        );
        setState(() {
          _isVerifying = false;
          _isAuthenticated = true;
        });
      }
      return;
    }

    _hasShownBiometric = true;
    
    // Add a small delay to ensure UI is ready
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Perform biometric authentication
    final result = await BiometricService.authenticateWithResult(
      reason: 'Please verify your identity to access the app',
    );

    if (mounted) {
      if (result.isSuccess) {
        // Success - proceed to app
        setState(() {
          _isVerifying = false;
          _isAuthenticated = true;
        });
      } else {
        // Show password dialog instead of signing out
        setState(() {
          _errorMessage = 'Biometric authentication failed. Please login with your password.';
          _isVerifying = false;
        });
      }
    }
  }

  Future<void> _showPasswordLoginDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _PasswordDialog(
          userEmail: _userEmail,
          userId: widget.userId,
        );
      },
    );
    
    if (result == true && mounted) {
      // Password verified successfully - proceed to app
      setState(() {
        _isAuthenticated = true;
        _isVerifying = false;
        _errorMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // If already authenticated, show child immediately
    if (_isAuthenticated && !_isVerifying) {
      return widget.child;
    }
    
    if (_isVerifying) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Verifying identity...'),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      // Show error screen with password option
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.fingerprint,
                  size: 80,
                  color: Colors.red,
                ),
                const SizedBox(height: 24),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _showPasswordLoginDialog,
                    icon: const Icon(Icons.password),
                    label: const Text('Login with Password'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () async {
                    // Sign out option
                    await FirebaseAuth.instance.signOut();
                    if (mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginOrRegister()),
                        (route) => false,
                      );
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Fallback - show child
    return widget.child;
  }
}

// Separate dialog widget to handle its own controller lifecycle
class _PasswordDialog extends StatefulWidget {
  final String? userEmail;
  final String userId;

  const _PasswordDialog({
    required this.userEmail,
    required this.userId,
  });

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _verifyPassword() async {
    setState(() => _isLoading = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        _showError('User not found');
        return;
      }
      
      // Re-authenticate the user
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _passwordController.text,
      );
      await user.reauthenticateWithCredential(credential);
      
      // Disable biometric temporarily since it failed
      await BiometricService.setBiometricEnabled(
        userId: widget.userId,
        enabled: false,
      );
      
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showError('Invalid password. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invalid password. Please try again.'),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pop(context, false);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginOrRegister()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_outline, color: Colors.orange),
          SizedBox(width: 8),
          Text('Password Required'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Biometric authentication failed. Please enter your password to continue.',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          if (widget.userEmail != null) ...[
            Text(
              'Email: ${widget.userEmail}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.password),
            ),
            autofocus: true,
            onSubmitted: (_) => _verifyPassword(),
          ),
          if (_isLoading) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : _signOut,
          child: const Text('Sign Out'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _verifyPassword,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
          ),
          child: const Text('Verify'),
        ),
      ],
    );
  }
}