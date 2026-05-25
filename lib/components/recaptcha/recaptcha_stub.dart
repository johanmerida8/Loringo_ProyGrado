// Non-web stub — captcha is skipped entirely on mobile/desktop.
import 'package:flutter/material.dart';

class RecaptchaWidget extends StatelessWidget {
  final void Function(String token) onVerified;

  const RecaptchaWidget({super.key, required this.onVerified});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// No-op on non-web platforms.
void resetRecaptcha() {}
