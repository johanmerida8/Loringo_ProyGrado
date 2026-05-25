import 'package:flutter/material.dart';

class MyTextField extends StatefulWidget {

    final TextEditingController controller;
    final String hintText;
    final bool obscureText;
    final FocusNode? focusNode;
    final Function(String)? onChanged;
    final bool isEnabled;
    final Widget? prefixIcon;
    final Widget? suffixIcon;

  const MyTextField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.obscureText,
    this.focusNode,
    this.onChanged,
    required this.isEnabled,
    this.prefixIcon,
    this.suffixIcon,
  });

  @override
  State<MyTextField> createState() => _MyTextFieldState();
}

class _MyTextFieldState extends State<MyTextField> {

  bool isPasswordVisible = false;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: widget.obscureText && !isPasswordVisible,
      focusNode: widget.focusNode,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(
            color: Colors.white
          ),
        ),
        fillColor: Theme.of(context).colorScheme.background,
        filled: true,
        hintText: widget.hintText,
        hintStyle: const TextStyle(
          color: Colors.grey
        ),
        enabled: widget.isEnabled,
        prefixIcon: widget.prefixIcon,
        suffixIcon: widget.suffixIcon ?? (widget.obscureText ? IconButton(
          icon: Icon(
            isPasswordVisible ? Icons.visibility : Icons.visibility_off,
          ),
          onPressed: () {
            setState(() {
              isPasswordVisible = !isPasswordVisible;
            });
          },
        ) : null),
      ),
    );
  }
}