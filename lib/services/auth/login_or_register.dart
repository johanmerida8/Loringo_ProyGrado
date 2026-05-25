import 'package:flutter/material.dart';
import 'package:loringo_app/screens/initials/login_screen.dart';
import 'package:loringo_app/screens/initials/register_screen.dart';

class LoginOrRegister extends StatefulWidget {
  const LoginOrRegister({super.key});

  @override
  State<LoginOrRegister> createState() => _LoginOrRegisterState();
}

class _LoginOrRegisterState extends State<LoginOrRegister> {
  // initially show the login screen
  bool showLoginPage = true;

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