import 'package:flutter/material.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  LORINGO DESIGN SYSTEM — single source of truth for all visual decisions.
//
//  Rule for every screen: NEVER write a raw Color, radius, spacing value or
//  TextStyle inline. Consume it from here. If a token is missing, add it here
//  first, then use it. This keeps the whole app consistent and lets us change
//  the look of Loringo from one single file.
// ═════════════════════════════════════════════════════════════════════════════

// ── Colors ──────────────────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  // Brand ----------------------------------------------------------------

  /// Primary green — the app's brand color.
  static const Color primary = Color(0xFF4CAF50);

  /// Lighter green used in gradients and accents.
  static const Color primaryLight = Color(0xFF81C784);

  /// Darker green for pressed states and text on light-green surfaces.
  static const Color primaryDark = Color(0xFF388E3C);

  // Semantic state colors --------------------------------------------------
  // Use these instead of Colors.green / Colors.orange / Colors.red so that
  // "approved / pending / rejected", "easy / medium / hard" and feedback
  // snackbars share the exact same hues everywhere.

  /// Positive / success feedback (same family as [primary]).
  static const Color success = Color(0xFF4CAF50);

  /// Warnings, "pending" status, medium difficulty.
  static const Color warning = Color(0xFFF59E0B);

  /// Destructive / error actions, "rejected" status, hard difficulty.
  static const Color danger = Color(0xFFE53935);

  /// Informational banners and hints.
  static const Color info = Color(0xFF42A5F5);

  // Surfaces & text ---------------------------------------------------------

  /// Text / icons on top of [primary] (and on any saturated surface).
  static const Color onPrimary = Colors.white;

  /// Card / sheet background.
  static const Color surface = Colors.white;

  /// Scaffold background — a very soft green tint that matches the student
  /// screens, instead of plain grey. Gives the whole app the Loringo feel.
  static const Color scaffoldBackground = Color(0xFFF2F8F2);

  /// Main body text.
  static const Color textPrimary = Color(0xFF263238);

  /// Secondary text: subtitles, helper text, captions.
  static const Color textSecondary = Color(0xFF6B7280);

  /// Muted text, hints and placeholders (kept for backward compatibility).
  static const Color muted = Colors.grey;

  /// Divider / border lines.
  static const Color divider = Color(0xFFE0E0E0);

  /// Background for disabled / subtle containers (chips, toggles, previews).
  static const Color subtleFill = Color(0xFFF5F5F5);

  // Helpers -----------------------------------------------------------------

  /// Primary with custom opacity.
  static Color primarySoft(double opacity) => primary.withOpacity(opacity);

  /// Soft tinted background for any accent color (e.g. group color cards).
  static Color tint(Color c, [double opacity = .08]) => c.withOpacity(opacity);

  /// Maps a difficulty string to its semantic color.
  static Color difficulty(String level) {
    switch (level) {
      case 'medium':
        return warning;
      case 'hard':
        return danger;
      default:
        return success; // 'easy'
    }
  }

  /// Maps a content approval status to its semantic color.
  static Color status(String status) {
    switch (status) {
      case 'approved':
        return success;
      case 'rejected':
        return danger;
      default:
        return warning; // 'pending'
    }
  }
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

  // Pre-built BorderRadius objects so screens never call
  // BorderRadius.circular(...) with a raw number.
  static final BorderRadius smAll = BorderRadius.circular(sm);
  static final BorderRadius mdAll = BorderRadius.circular(md);
  static final BorderRadius lgAll = BorderRadius.circular(lg);
  static final BorderRadius pillAll = BorderRadius.circular(pill);
}

// ── Shadows ──────────────────────────────────────────────────────────────────

class AppShadows {
  AppShadows._();

  /// Standard card elevation used by every list card across the app.
  static List<BoxShadow> get card => [
        BoxShadow(
          color: Colors.black.withOpacity(.05),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ];

  /// Slightly stronger shadow for floating elements (FABs, active chips).
  static List<BoxShadow> floating(Color accent) => [
        BoxShadow(
          color: accent.withOpacity(.25),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];
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

  /// Smaller app-bar title used when a subtitle sits underneath it
  /// (e.g. "Unit title" + "Lessons").
  static const TextStyle appBarTitleSm = TextStyle(
    color: AppColors.onPrimary,
    fontWeight: FontWeight.bold,
    fontSize: 17,
  );

  /// Subtitle line under an app-bar title.
  static const TextStyle appBarSubtitle = TextStyle(
    color: Colors.white70,
    fontSize: 12,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
  );

  /// List-tile title (one size below cardTitle).
  static const TextStyle listTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
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

  /// Small bold label used in section headers above form fields.
  static const TextStyle fieldLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.bold,
    letterSpacing: 1.1,
  );

  /// Text inside primary buttons.
  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: AppColors.onPrimary,
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

  /// Standard white card used across all list screens.
  static BoxDecoration card({Color? borderColor}) => BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.mdAll,
        border: borderColor != null ? Border.all(color: borderColor) : null,
        boxShadow: AppShadows.card,
      );

  /// Soft tinted info banner (the rounded box with an icon + explanation
  /// used in the task editors).
  static BoxDecoration infoBanner(Color accent) => BoxDecoration(
        color: AppColors.tint(accent, .07),
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: accent.withOpacity(.3)),
      );
}

// ── Form field decoration ────────────────────────────────────────────────────

/// One single factory for every TextFormField in the app. Replaces the 20+
/// InputDecoration blocks that were copy-pasted across the create/edit screens.
class AppInput {
  AppInput._();

  static InputDecoration decoration({
    required Color accent,
    String? label,
    String? hint,
    String? helper,
    IconData? icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
      prefixIcon: icon != null ? Icon(icon, color: accent) : null,
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: AppRadii.mdAll),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadii.mdAll,
        borderSide: BorderSide(color: accent.withOpacity(.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadii.mdAll,
        borderSide: BorderSide(color: accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppRadii.mdAll,
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: AppRadii.mdAll,
        borderSide: const BorderSide(color: AppColors.danger, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md - 2,
      ),
    );
  }
}