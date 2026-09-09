import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/biometric_provider.dart';
import 'package:loringo_app/services/auth/biometric_service.dart';
import 'package:loringo_app/theme/app_theme.dart';

// ── confirmIdentity ───────────────────────────────────────────────────────
//
// Reusable "confirm it's you" gate for sensitive actions (e.g. revealing/
// regenerating a child's access code). Modeled on
// biometric_verification_screen.dart's try-biometric-then-password-dialog
// logic, but as an awaitable dialog instead of a full-screen wrapper, so it
// can be dropped in front of a single action anywhere in the app.
//
// Flow:
//   1. If biometrics are enabled for the CURRENT (parent) auth user, try
//      biometric auth — succeed immediately on success.
//   2. If biometrics aren't enabled but the device supports them, nudge the
//      user to enable them (reusing BiometricProvider.toggle's existing
//      opt-in dialog) before falling back to password.
//   3. Fall back to a password re-auth dialog (Firebase
//      reauthenticateWithCredential), same as the other password-confirm
//      flows in this app (reset_in_app_screen.dart,
//      biometric_verification_screen.dart's _PasswordDialog).
//
// Returns true only if the user proved their identity; false if they
// canceled or failed.
Future<bool> confirmIdentity(BuildContext context, {required String reason}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;

  final isEnabled = await BiometricService.isBiometricEnabled(user.uid);
  final isSupported = await BiometricService.isDeviceSupported();

  if (isEnabled && isSupported) {
    final result = await BiometricService.authenticateWithResult(reason: reason);
    if (result.isSuccess) return true;
    // Fall through to password on failure/cancel, same as
    // BiometricVerificationScreen does.
  } else if (isSupported && context.mounted) {
    // Not enabled yet — recommend it, then continue to password regardless
    // of the user's choice so this confirmation doesn't block on it.
    await context.read<BiometricProvider>().toggle(context, user.uid);
  }

  if (!context.mounted) return false;
  return reauthenticateWithPassword(context);
}

// ── reauthenticateWithPassword ────────────────────────────────────────────
//
// Always performs a real Firebase reauthenticateWithCredential call — no
// biometric shortcut. Needed wherever a genuinely fresh sign-in is
// required server-side (e.g. before user.delete(), which throws
// `requires-recent-login` otherwise) — confirmIdentity()'s biometric path
// only proves identity locally to the device, it never actually refreshes
// Firebase's server-side "recent login" timestamp the way a real
// reauthenticateWithCredential call does.
Future<bool> reauthenticateWithPassword(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _PasswordConfirmDialog(userEmail: user.email),
  );
  return result == true;
}

class _PasswordConfirmDialog extends StatefulWidget {
  final String? userEmail;

  const _PasswordConfirmDialog({required this.userEmail});

  @override
  State<_PasswordConfirmDialog> createState() => _PasswordConfirmDialogState();
}

class _PasswordConfirmDialogState extends State<_PasswordConfirmDialog> {
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        throw Exception('no user');
      }
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _passwordController.text,
      );
      await user.reauthenticateWithCredential(credential);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('common.invalidPassword'.tr()),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
      title: Row(
        children: [
          const Icon(Icons.lock_outline, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text('common.confirmIdentity'.tr())),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('common.confirmIdentityBody'.tr()),
          const SizedBox(height: AppSpacing.md),
          if (widget.userEmail != null)
            Text(widget.userEmail!,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _passwordController,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'common.password'.tr(),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.password),
            ),
            onSubmitted: (_) => _verify(),
          ),
          if (_isLoading) ...[
            const SizedBox(height: AppSpacing.md),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
          child: Text('common.cancel'.tr()),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _verify,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          child: Text('common.verify'.tr()),
        ),
      ],
    );
  }
}
