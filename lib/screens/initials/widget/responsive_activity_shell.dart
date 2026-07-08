// lib/screens/initials/widget/responsive_activity_shell.dart
import 'package:flutter/material.dart';

/// Breakpoint above which we're clearly on web/desktop, not a phone.
const double kActivityWideBreakpoint = 700;

/// Max content width so activities don't stretch edge-to-edge on wide
/// screens (this is what was happening in image 1 and image 3 — options
/// and match tiles spanning the full 1900px browser width).
const double kActivityMaxWidth = 720;

/// Wraps every task screen's body content. On narrow (phone) screens it's
/// a no-op passthrough. On wide (web) screens it centers the content and
/// caps its width, and gives images/grids a sane max size via
/// [ResponsiveActivityMetrics].
class ResponsiveActivityShell extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsiveActivityShell({
    super.key,
    required this.child,
    this.maxWidth = kActivityMaxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= kActivityWideBreakpoint;
        if (!isWide) return child;

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        );
      },
    );
  }
}

/// Size helpers so each screen doesn't hardcode "250" or "crossAxisCount: 2"
/// — instead it asks "how wide is my available space right now" and picks
/// a sensible value. Use inside a LayoutBuilder or with MediaQuery.
class ResponsiveActivityMetrics {
  final bool isWide;
  final double availableWidth;

  const ResponsiveActivityMetrics({
    required this.isWide,
    required this.availableWidth,
  });

  factory ResponsiveActivityMetrics.of(BuildContext context, {double? constrainedWidth}) {
    final width = constrainedWidth ?? MediaQuery.of(context).size.width;
    return ResponsiveActivityMetrics(
      isWide: width >= kActivityWideBreakpoint,
      availableWidth: width,
    );
  }

  /// For image_select-style grids: 2 columns on phone, still 2 on web but
  /// with a capped tile size so tiles don't become huge (fixes image 1,
  /// where the two option tiles filled almost the entire viewport).
  int get imageGridCrossAxisCount => 2;

  /// Height cap for a single "hero" image, like screen_five's image card.
  /// Phone: let it flow (existing fixed height stays as-is at call site).
  /// Web: cap it so a 1080p browser doesn't get a gigantic image.
  double get heroImageMaxHeight => isWide ? 260 : 250;

  /// Grid tile aspect ratio for image_select options — keeps tiles closer
  /// to square/card-shaped rather than stretching to fill leftover width.
  double get imageOptionAspectRatio => isWide ? 1.15 : 1.0;
}