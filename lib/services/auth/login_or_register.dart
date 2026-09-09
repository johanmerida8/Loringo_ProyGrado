import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/initials/login_screen.dart';
import 'package:loringo_app/screens/initials/register_screen.dart';

/// The single entry point for the pre-auth flow: every logout path in the
/// app (LogoutService, or the separate inline logout dialogs in each
/// role's profile/settings screen) ends up here, either directly or via
/// AuthGate rendering this widget once authStateChanges() reports no
/// user. That makes initState() here the one place that reliably runs
/// whenever we're about to show login/register — the right spot to reset
/// the locale to the device's own language, so a previous user's manual
/// in-app language override (saved to disk by LocaleProvider) never
/// leaks into the next person's login screen. A still-logged-in user's
/// own override is unaffected, since this widget is never built while
/// they're signed in.
class LoginOrRegister extends StatefulWidget {
  const LoginOrRegister({super.key});

  @override
  State<LoginOrRegister> createState() => _LoginOrRegisterState();
}

class _LoginOrRegisterState extends State<LoginOrRegister> {
  // initially show the login screen
  bool showLoginPage = true;

  @override
  void initState() {
    super.initState();
    // Post-frame: resetLocale() ultimately calls setState on the
    // EasyLocalization ancestor, which must not happen while this widget
    // is still being built (same defensive pattern used elsewhere in this
    // codebase for provider calls triggered from initState). The
    // EasyLocalization.of(context) null-check guards widget tests that
    // pump this screen without the full EasyLocalization wrapper (see
    // test/helpers/pump_app.dart) — always non-null in the real app,
    // which main.dart wraps in EasyLocalization unconditionally.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && EasyLocalization.of(context) != null) {
        context.resetLocale();
      }
    });
  }

  // toggle between login and register
  void toggleScreens() {
    setState(() {
      showLoginPage = !showLoginPage;
    });
  }

  @override
  Widget build(BuildContext context) {
    return showLoginPage
        ? LoginScreen(onTap: toggleScreens)
        : RegisterScreen(onTap: toggleScreens);
  }
}