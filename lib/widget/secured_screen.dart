// import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
// import 'package:loringo_app/services/auth/logout_service.dart';
import 'package:loringo_app/services/logout/logout_service.dart';

class SecuredScreen extends StatelessWidget {
  final Widget child;
  final bool showExitDialog;
  final bool isStudent; // Differentiate student vs regular user
  final VoidCallback? customLogoutHandler;

  const SecuredScreen({
    super.key,
    required this.child,
    this.showExitDialog = true,
    this.isStudent = false,
    this.customLogoutHandler,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        
        if (customLogoutHandler != null) {
          customLogoutHandler!();
          return;
        }
        
        if (showExitDialog) {
          final shouldLogout = await LogoutService.showLogoutConfirmation(context);
          
          if (shouldLogout) {
            if (isStudent) {
              await LogoutService.logoutStudent(context);
            } else {
              await LogoutService.logoutUser(context);
            }
          }
        }
      },
      child: child,
    );
  }
}