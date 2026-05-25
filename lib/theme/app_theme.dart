import 'package:flutter/material.dart';

// ── Colors ──────────────────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  /// Primary green — the app's brand color.
  static const Color primary = Color(0xFF4CAF50);

  /// Lighter green used in gradients and accents.
  static const Color primaryLight = Color(0xFF81C784);

  /// Destructive / error actions.
  static const Color danger = Colors.red;

  /// Positive / success feedback.
  static const Color success = Colors.green;

  /// Text / icons on top of [primary].
  static const Color onPrimary = Colors.white;

  /// Muted text, hints and placeholders.
  static const Color muted = Colors.grey;

  /// Scaffold background.
  static Color get scaffoldBackground => Colors.grey[50]!;

  /// Divider / border lines.
  static Color get divider => Colors.grey[300]!;

  /// Primary with custom opacity.
  static Color primarySoft(double opacity) => primary.withOpacity(opacity);
}

// ── Spacing ─────────────────────────────────────────────────────────────────

class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

// ── Border radii ─────────────────────────────────────────────────────────────

class AppRadii {
  AppRadii._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 20;
  static const double pill = 35;
}

// ── Text styles ──────────────────────────────────────────────────────────────

class AppText {
  AppText._();

  static const TextStyle h1 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.primary,
  );

  static const TextStyle appBarTitle = TextStyle(
    color: AppColors.onPrimary,
    fontSize: 22,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle body = TextStyle(fontSize: 16);

  static const TextStyle subtitle = TextStyle(
    fontSize: 16,
    color: AppColors.muted,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: AppColors.muted,
  );
}

// ── Decorations ──────────────────────────────────────────────────────────────

class AppDecorations {
  AppDecorations._();

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [AppColors.primary, AppColors.primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
