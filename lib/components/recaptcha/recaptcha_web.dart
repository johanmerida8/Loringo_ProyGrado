// ignore_for_file: avoid_web_libraries_in_flutter
@JS()
library;

import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

// Site key is public — safe to have in client code.
const String _siteKey = '6LfYaucsAAAAAKBBvwJhX6XXg4wH4HTZwTCgmkV7';

// Typed JS interop for the global grecaptcha object.
@JS('grecaptcha')
external _Grecaptcha? get _grecaptcha;

extension type _Grecaptcha._(JSObject _) implements JSObject {
  external void ready(JSFunction callback);
  external void render(String element, JSObject options);
  external void reset();
}

class RecaptchaWidget extends StatefulWidget {
  final void Function(String token) onVerified;

  const RecaptchaWidget({super.key, required this.onVerified});

  @override
  State<RecaptchaWidget> createState() => _RecaptchaWidgetState();
}

class _RecaptchaWidgetState extends State<RecaptchaWidget> {
  late final String _viewId;
  late final String _elementId;

  @override
  void initState() {
    super.initState();
    final ts = DateTime.now().millisecondsSinceEpoch;
    _viewId = 'recaptcha-view-$ts';
    _elementId = 'recaptcha-el-$ts';

    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int id) {
      final container = html.DivElement()
        ..id = _elementId
        ..style.width = '304px'
        ..style.height = '78px';

      // Wait for element to be in the DOM, then render the widget.
      Future.delayed(const Duration(milliseconds: 400), _renderCaptcha);

      return container;
    });
  }

  void _renderCaptcha() {
    final captcha = _grecaptcha;
    if (captcha == null) return;

    final callbackFn = ((JSString jsToken) {
      if (mounted) widget.onVerified(jsToken.toDart);
    }).toJS;

    final expiredFn = (() {
      if (mounted) widget.onVerified('');
    }).toJS;

    captcha.ready((() {
      final options = JSObject();
      options['sitekey'] = _siteKey.toJS;
      options['callback'] = callbackFn;
      options['expired-callback'] = expiredFn;
      try {
        captcha.render(_elementId, options);
      } catch (_) {
        // Widget may already be rendered (hot reload).
      }
    }).toJS);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      width: 304,
      child: HtmlElementView(viewType: _viewId),
    );
  }
}

/// Resets any currently displayed reCAPTCHA widget.
void resetRecaptcha() {
  try {
    _grecaptcha?.reset();
  } catch (_) {}
}

