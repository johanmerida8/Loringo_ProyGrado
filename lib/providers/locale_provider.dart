import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Wraps easy_localization's context.setLocale() in the same
/// ChangeNotifier pattern as BiometricProvider/NotificationProvider, so
/// widgets can dispatch a language change through the same provider
/// convention used elsewhere in the app. Reading the *current* locale
/// should still go through context.locale (easy_localization's own,
/// already-reactive mechanism) — this provider only handles the switch.
class LocaleProvider extends ChangeNotifier {
  // Switches the locale and notifies once the switch has fully completed.
  // Never touch `context` inside a provider's `create` callback (it runs
  // lazily, exactly once, and Flutter forbids establishing an
  // InheritedWidget dependency there) — that was the actual cause of a
  // "Tried to listen to an InheritedWidget in a life-cycle that will
  // never be called again" crash previously seeded here via
  // ctx.locale. Also notifying before the await (e.g. to flip a loading
  // flag) races easy_localization's own rebuild — notify only once, after.
  Future<void> setLocale(BuildContext context, Locale locale) async {
    if (context.locale == locale) return;

    await context.setLocale(locale);
    notifyListeners();
  }
}
