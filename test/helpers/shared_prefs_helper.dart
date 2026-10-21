import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around SharedPreferences' own test helper, reused by every
/// file that tests SharedPreferences-backed services (student auth,
/// notification permission, biometric settings) instead of each repeating
/// the same setUp() call.
void setUpMockSharedPreferences([Map<String, Object> initialValues = const {}]) {
  SharedPreferences.setMockInitialValues(initialValues);
}
