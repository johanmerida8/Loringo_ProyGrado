// lib/components/app_loading_indicator.dart
//
// Shared full-screen/section loading indicator using
// assets/JSON/loading.json — for the app's main content-loading screens
// (student activities/task/quiz play, parent dashboards, teacher content
// screens), so those primary loaders read as one consistent visual
// language instead of a bare CircularProgressIndicator per screen.
//
// Distinct from MyLoading (lib/components/my_loading.dart), which is
// already established on the login/register flow with its own asset
// (happy-loader.json) — that one is left as-is, this is a separate
// component for everywhere else.

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class AppLoadingIndicator extends StatelessWidget {
  final double size;

  /// Optional caption shown under the animation (e.g. "Loading your
  /// activities..."). Omit for a bare animation.
  final String? message;

  const AppLoadingIndicator({
    super.key,
    this.size = 160,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Lottie.asset(
            'assets/JSON/loading.json',
            width: size,
            height: size,
            fit: BoxFit.contain,
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
