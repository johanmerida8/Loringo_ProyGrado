import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show Locale;

/// Bump this whenever assets/legal/privacy_policy_*.txt changes in a way
/// that should require re-consent (see database.dart's
/// privacyPolicyVersion/childDataConsentVersion fields).
const String kPrivacyPolicyVersion = '1.0';

/// Loads the privacy policy text matching [locale], falling back to
/// Spanish (the app's primary language) for any locale without a
/// dedicated translation.
Future<String> loadPrivacyPolicyText(Locale locale) {
  final languageCode = locale.languageCode == 'en' ? 'en' : 'es';
  return rootBundle.loadString('assets/legal/privacy_policy_$languageCode.txt');
}
