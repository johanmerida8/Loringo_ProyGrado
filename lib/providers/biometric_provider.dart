import 'package:flutter/material.dart';
import 'package:loringo_app/services/auth/biometric_service.dart';
import 'package:loringo_app/theme/app_theme.dart';

class BiometricProvider extends ChangeNotifier {
  bool _isEnabled = false;
  bool _isSupported = false;
  String _biometricTypeName = 'Biometrics';
  bool _isLoading = true;

  bool get isEnabled => _isEnabled;
  bool get isSupported => _isSupported;
  String get biometricTypeName => _biometricTypeName;
  bool get isLoading => _isLoading;

  Future<void> initialize(String userId) async {
    _isLoading = true;
    notifyListeners();
    
    _isEnabled = await BiometricService.isBiometricEnabled(userId);
    
    final isSupported = await BiometricService.isDeviceSupported();
    final canCheck = await BiometricService.canCheckBiometrics();
    _isSupported = isSupported && canCheck;
    
    final available = await BiometricService.getAvailableBiometrics();
    _biometricTypeName = BiometricService.getBiometricTypeName(available);
    
    _isLoading = false;
    notifyListeners();
  }

  Future<void> toggle(BuildContext context, String userId) async {
    if (_isEnabled) {
      // Disable
      await BiometricService.setBiometricEnabled(userId: userId, enabled: false);
      _isEnabled = false;
      notifyListeners();
      _showSnackBar(context, '$_biometricTypeName login disabled');
    } else {
      // Enable - Show styled dialog
      final shouldEnable = await _showEnableBiometricDialog(context);
      
      if (shouldEnable != true) return;
      
      final ok = await BiometricService.authenticate(
        reason: 'Verify your identity to enable biometric login',
      );
      
      if (ok) {
        await BiometricService.setBiometricEnabled(userId: userId, enabled: true);
        _isEnabled = true;
        notifyListeners();
        _showSnackBar(context, '$_biometricTypeName login enabled');
      } else {
        _showSnackBar(context, 'Authentication failed', isError: true);
      }
    }
  }

  Future<bool?> _showEnableBiometricDialog(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primarySoft(0.1),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Icon(
                Icons.fingerprint,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            const Expanded(
              child: Text(
                'Enable Biometric Login',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Would you like to enable $_biometricTypeName login for faster access to your account?',
              style: AppText.body.copyWith(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.primarySoft(0.05),
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(
                  color: AppColors.primarySoft(0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _biometricTypeName == 'Face ID' 
                        ? Icons.face_rounded 
                        : Icons.fingerprint,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'You will be prompted to verify your identity each time you open the app.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              elevation: 0,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
    );
  }
}