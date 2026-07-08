// lib/screens/teacher/widgets/create_form_widgets.dart
import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// Colored accent banner shown at the top of every create/edit screen so the
/// teacher always sees, in plain language, what they're about to build.
class CreateFormBanner extends StatelessWidget {
  const CreateFormBanner({
    super.key,
    required this.color,
    required this.icon,
    required this.label,
    required this.description,
  });

  final Color color;
  final IconData icon;
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.infoBanner(color),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md - 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: AppRadii.mdAll,
          ),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.w700, letterSpacing: 0.4,
            )),
            const SizedBox(height: 3),
            Text(description, style: const TextStyle(
              fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500,
            )),
          ]),
        ),
      ]),
    );
  }
}

/// Small bold label shown above a form field.
class CreateFormLabel extends StatelessWidget {
  const CreateFormLabel(this.text, {super.key, this.color = AppColors.primary});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(Icons.label_outline, size: 14, color: color),
        const SizedBox(width: 6),
        Text(text.toUpperCase(), style: AppText.fieldLabel.copyWith(color: color)),
      ]);
}

/// Single canonical text field for every create/edit screen — wraps
/// [AppInput.decoration] so no screen hand-rolls borders anymore.
class CreateFormField extends StatelessWidget {
  const CreateFormField({
    super.key,
    required this.controller,
    required this.color,
    this.hint,
    this.helperText,
    this.icon,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.validator,
    this.onChanged,
  });

  final TextEditingController controller;
  final Color color;
  final String? hint;
  final String? helperText;
  final IconData? icon;
  final TextInputType keyboardType;
  final int maxLines;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      onChanged: onChanged,
      decoration: AppInput.decoration(
        accent: color,
        hint: hint,
        helper: helperText,
        icon: icon,
      ),
    );
  }
}

/// Full-width primary submit button used by every create/edit screen.
class CreateFormSubmitButton extends StatelessWidget {
  const CreateFormSubmitButton({
    super.key,
    required this.color,
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final Color color;
  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
        ),
        child: isLoading
            ? const SizedBox(
                height: 22, width: 22,
                child: CircularProgressIndicator(color: AppColors.onPrimary, strokeWidth: 2),
              )
            : Text(label, style: AppText.button.copyWith(letterSpacing: 0.5)),
      ),
    );
  }
}