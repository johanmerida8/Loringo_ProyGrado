// lib/utils/connectivity_banner.dart
//
// Wraps a screen's body and shows a thin banner above it while the device
// has no real internet access (not just "Wi-Fi connected": the check makes
// actual requests, via internet_connection_checker_plus). Works on Android
// and web. When the connection comes back it shows a green "back online"
// banner for a couple of seconds and then disappears.
//
// Usage — wrap the body of a role's main screen:
//     bodyBuilder: (context, isWide) => ConnectivityBanner(child: ...),

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/theme/app_theme.dart';

class ConnectivityBanner extends StatefulWidget {
  final Widget child;

  const ConnectivityBanner({super.key, required this.child});

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  static const Duration _backOnlineDuration = Duration(seconds: 2);

  StreamSubscription<InternetStatus>? _subscription;
  Timer? _backOnlineTimer;
  bool _offline = false;
  bool _showBackOnline = false;

  @override
  void initState() {
    super.initState();
    _checkNow();
    _subscription = InternetConnection().onStatusChange.listen(
      (status) => _apply(status == InternetStatus.connected),
      // A failed check must never crash a screen; keep the last known state.
      onError: (_) {},
    );
  }

  Future<void> _checkNow() async {
    try {
      _apply(await InternetConnection().hasInternetAccess);
    } catch (_) {
      // Keep the last known state.
    }
  }

  void _apply(bool connected) {
    if (!mounted) return;
    // Repeated reports of the state we're already in change nothing.
    if (connected != _offline) return;
    _backOnlineTimer?.cancel();
    setState(() {
      if (connected) {
        // We were offline: celebrate briefly.
        _offline = false;
        _showBackOnline = true;
      } else {
        _offline = true;
        _showBackOnline = false;
      }
    });
    if (connected) {
      _backOnlineTimer = Timer(_backOnlineDuration, () {
        if (mounted) setState(() => _showBackOnline = false);
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _backOnlineTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final visible = _offline || _showBackOnline;
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: visible
              ? _Banner(offline: _offline)
              : const SizedBox(width: double.infinity),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final bool offline;

  const _Banner({required this.offline});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      color: offline ? AppColors.danger : AppColors.success,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(offline ? Icons.wifi_off_rounded : Icons.wifi_rounded,
              color: Colors.white, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              offline
                  ? 'common.noInternet'.tr()
                  : 'common.backOnline'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
