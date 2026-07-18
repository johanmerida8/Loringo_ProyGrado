import 'package:flutter/material.dart';
import 'package:loringo_app/components/wave_form.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// Breakpoint at which auth screens switch from the mobile "stacked hero"
/// layout to the web "side-by-side panel" layout.
const double kAuthWebBreakpoint = 900;

/// Shared shell for all auth screens (Login, Register, ResetPassword,
/// OTP, ConfirmResetPassword).
///
/// Mobile (< kAuthWebBreakpoint): keeps the original design untouched —
/// a fixed gradient hero with a WaveDivider, and a scrollable form
/// positioned below it.
///
/// Web (>= kAuthWebBreakpoint): a compact, centered two-column card —
/// gradient/branding panel on the left, form on the right — with the
/// whole card scrolling as a single unit so there's no "only the form
/// scrolls" mismatch.
class AuthLayout extends StatelessWidget {
  /// Icon or image shown in the hero/left panel.
  final Widget heroVisual;

  /// Headline text, e.g. "Welcome back!"
  final String title;

  /// Supporting text under the title, e.g. "Sign in to Loringo"
  final String subtitle;

  /// The actual form content (card contents only — no outer card
  /// decoration needed, AuthLayout supplies that).
  final Widget form;

  /// Extra content placed below the form card but still inside the
  /// scroll view (e.g. the "Student Login" pill, "Create account" row).
  final Widget? footer;

  /// Fraction of screen height the mobile hero should occupy.
  /// Ignored on web.
  final double mobileHeroFraction;

  /// Optional back button (used by ResetPassword/OTP/etc. that aren't
  /// reachable from a bottom nav). Shown top-left on both layouts.
  final VoidCallback? onBack;

  const AuthLayout({
    super.key,
    required this.heroVisual,
    required this.title,
    required this.subtitle,
    required this.form,
    this.footer,
    this.mobileHeroFraction = 0.40,
    this.onBack,
  });

  static const _kTopGradient = LinearGradient(
    colors: [Color(0xFFF6E96B), Color(0xFFBEDC74), Color(0xFFA2CA71)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const _kBottomColor = Color(0xFFF2F8F2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBottomColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWeb = constraints.maxWidth >= kAuthWebBreakpoint;
          return isWeb
              ? _WebLayout(
                  heroVisual: heroVisual,
                  title: title,
                  subtitle: subtitle,
                  form: form,
                  footer: footer,
                  onBack: onBack,
                  gradient: _kTopGradient,
                  bottomColor: _kBottomColor,
                )
              : _MobileLayout(
                  heroVisual: heroVisual,
                  title: title,
                  subtitle: subtitle,
                  form: form,
                  footer: footer,
                  onBack: onBack,
                  heroFraction: mobileHeroFraction,
                  gradient: _kTopGradient,
                  bottomColor: _kBottomColor,
                );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Mobile: original stacked hero + wave + scrollable form below it.
// ─────────────────────────────────────────────────────────────────────────
class _MobileLayout extends StatelessWidget {
  final Widget heroVisual;
  final String title;
  final String subtitle;
  final Widget form;
  final Widget? footer;
  final VoidCallback? onBack;
  final double heroFraction;
  final Gradient gradient;
  final Color bottomColor;

  const _MobileLayout({
    required this.heroVisual,
    required this.title,
    required this.subtitle,
    required this.form,
    required this.footer,
    required this.onBack,
    required this.heroFraction,
    required this.gradient,
    required this.bottomColor,
  });

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final heroH = screenH * heroFraction;

    return Stack(
      children: [
        Container(color: bottomColor),

        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: heroH + 20,
          child: Container(
            decoration: BoxDecoration(gradient: gradient),
            child: SafeArea(
              bottom: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  heroVisual,
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E6B30),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF3D7A3F),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),

        Positioned(
          top: heroH - 8,
          left: 0,
          right: 0,
          child: WaveDivider(
            color: bottomColor,
            height: 54,
            waveIntensity: 1.0,
          ),
        ),

        Positioned(
          top: heroH + 20,
          left: 0,
          right: 0,
          bottom: 0,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadii.lg + 4),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: form,
                  ),
                  if (footer != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    footer!,
                  ],
                  const SizedBox(height: AppSpacing.xl * 2),
                ],
              ),
            ),
          ),
        ),

        if (onBack != null)
          Positioned(
            top: 50,
            left: 20,
            child: _BackButton(onTap: onBack!),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Web: compact split card, gradient panel left / form right, with a
// vertical WaveDivider seaming the two panels (same visual language as
// mobile). No IntrinsicHeight — that was forcing both panels through an
// intrinsic-size pass which, combined with platform views (reCAPTCHA's
// iframe) on Flutter web, was leaving a stale hit-test region over the
// footer and swallowing taps on "Create account". Instead each panel
// sizes itself naturally and the Row stretches them to match.
// ─────────────────────────────────────────────────────────────────────────
class _WebLayout extends StatelessWidget {
  final Widget heroVisual;
  final String title;
  final String subtitle;
  final Widget form;
  final Widget? footer;
  final VoidCallback? onBack;
  final Gradient gradient;
  final Color bottomColor;

  const _WebLayout({
    required this.heroVisual,
    required this.title,
    required this.subtitle,
    required this.form,
    required this.footer,
    required this.onBack,
    required this.gradient,
    required this.bottomColor,
  });

  static const double _cardMaxWidth = 820;
  static const double _leftPanelWidth = 320;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: bottomColor),
        SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl * 2),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _cardMaxWidth),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.lg + 8),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.12),
                        blurRadius: 32,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: IntrinsicHeight(
                    // Row + stretch sizes both panels to whichever is
                    // taller (form or branding content) — this is what a
                    // Stack + Positioned.fill cannot do, since Positioned
                    // forces its child into the Stack's own resolved
                    // size instead of contributing to it. That mismatch
                    // was overflowing the branding Column on screens with
                    // a short form (e.g. ResetPassword).
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Gradient branding panel — its own wavy right
                        // edge is clipped directly onto it, so there's
                        // no separate strip to seam against the white
                        // panel beside it.
                        ClipPath(
                          clipper: const _WavyRightEdgeClipper(),
                          child: Container(
                            width: _leftPanelWidth,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xl,
                              vertical: AppSpacing.xl * 1.5,
                            ),
                            decoration: BoxDecoration(gradient: gradient),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                heroVisual,
                                const SizedBox(height: AppSpacing.lg),
                                Text(
                                  title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2E6B30),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  subtitle,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF3D7A3F),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Form side — no overlap compensation needed since
                        // the wave stays within the branding panel's own
                        // width (see _waveDepth in the clipper).
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.xl,
                              AppSpacing.xl * 1.5,
                              AppSpacing.xl,
                              AppSpacing.xl * 1.5,
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  form,
                                  if (footer != null) ...[
                                    const SizedBox(height: AppSpacing.md),
                                    footer!,
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (onBack != null)
          Positioned(
            top: 30,
            left: 30,
            child: _BackButton(onTap: onBack!),
          ),
      ],
    );
  }
}

/// Clips the branding panel's right edge into a wave — a direct 90°
/// rotation of the mobile [WaveDivider]'s own curve (same two cubics,
/// x and y swapped), so the web and mobile waves are visually the same
/// shape instead of a separately hand-tuned one. WaveDivider draws a
/// single continuous S using two cubics that hand off tangentially; the
/// earlier version here stitched three cubics that each snapped back to
/// the edge, producing visible cusps instead of a smooth curve.
class _WavyRightEdgeClipper extends CustomClipper<Path> {
  const _WavyRightEdgeClipper();

  @override
  Path getClip(Size size) {
    final path = Path();

    // WaveDivider: startY = h * 0.55, then two cubics sweeping across
    // width. Here width/height are swapped and the "depth" axis (its
    // height, our width) is compressed to _depth of the panel width so
    // the wave stays subtle instead of spanning the full panel depth.
    const depth = 0.16;
    final w = size.width * depth;
    final h = size.height;

    final startX = size.width - w * 0.55;
    path.moveTo(startX, 0);
    path.cubicTo(
      size.width - w * (-0.1), h * 0.20,
      size.width - w * 0.9, h * 0.45,
      size.width - w * 0.25, h * 0.65,
    );
    path.cubicTo(
      size.width - w * (-0.05), h * 0.80,
      size.width - w * 0.5, h * 0.90,
      size.width - w * 0.3, h,
    );

    path.lineTo(0, h);
    path.lineTo(0, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(AppRadii.md),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF2E6B30),
            size: 16,
          ),
        ),
      ),
    );
  }
}