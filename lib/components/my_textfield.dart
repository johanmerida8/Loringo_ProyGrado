import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';

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
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_onFocusChange);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return TextField(
      controller: widget.controller,
      obscureText: widget.obscureText && !isPasswordVisible,
      focusNode: _focusNode,
      onChanged: widget.onChanged,
      enabled: widget.isEnabled,
      style: TextStyle(
        color: isDarkMode ? Colors.white : AppColors.textPrimary,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: TextStyle(
          color: isDarkMode ? Colors.grey.shade500 : AppColors.textSecondary,
          fontSize: 13,
        ),
        filled: true,
        fillColor: widget.isEnabled
            ? (isDarkMode ? Colors.grey.shade800 : AppColors.surface)
            : (isDarkMode ? Colors.grey.shade900 : AppColors.subtleFill),
        prefixIcon: widget.prefixIcon != null
            ? IconTheme(
                data: IconThemeData(
                  color: _getIconColor(isDarkMode),
                  size: 18,
                ),
                child: widget.prefixIcon!,
              )
            : null,
        suffixIcon: widget.suffixIcon ??
            (widget.obscureText
                ? IconButton(
                    icon: Icon(
                      isPasswordVisible
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      size: 18,
                      color: _getIconColor(isDarkMode),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      setState(() {
                        isPasswordVisible = !isPasswordVisible;
                      });
                    },
                  )
                : null),
        border: OutlineInputBorder(
          borderRadius: AppRadii.mdAll,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.mdAll,
          borderSide: BorderSide(
            color: _isFocused
                ? AppColors.primary
                : (isDarkMode ? Colors.grey.shade700 : AppColors.divider),
            width: _isFocused ? 2 : 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.mdAll,
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadii.mdAll,
          borderSide: const BorderSide(
            color: AppColors.danger,
            width: 1.5,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadii.mdAll,
          borderSide: const BorderSide(
            color: AppColors.danger,
            width: 2,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.mdAll,
          borderSide: BorderSide(
            color: isDarkMode ? Colors.grey.shade800 : AppColors.divider,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
    );
  }

  Color _getIconColor(bool isDarkMode) {
    if (!widget.isEnabled) {
      return isDarkMode ? Colors.grey.shade600 : AppColors.textSecondary;
    }
    if (_isFocused) {
      return AppColors.primary;
    }
    return isDarkMode ? Colors.grey.shade400 : AppColors.textSecondary;
  }
}