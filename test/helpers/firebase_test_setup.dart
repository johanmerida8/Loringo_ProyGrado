import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:loringo_app/services/firebase_refs.dart';

/// Swaps the app's global Firebase refs (see lib/services/firebase_refs.dart)
/// for fakes, and returns them so the test can seed/read data or drive auth
/// state directly. Call [tearDownMockedFirebase] afterwards (e.g. in a
/// tearDown()) so later tests in the same file don't inherit this test's
/// populated fakes.
///
/// Also loads fake ACCESS_CODE_PEPPER/ACCESS_CODE_KEY via
/// dotenv.loadFromString — real .env files aren't read under `flutter
/// test`, but AccessCodeHasher.hash and AccessCodeCipher.encrypt/decrypt
/// (used by Database.createStudent/revealAccessCode/etc.) require them to
/// be present or they throw. The key must decode to exactly 32 bytes
/// (AES-256) — this base64 string does.
({MockFirebaseAuth auth, FakeFirebaseFirestore firestore}) setUpMockedFirebase({
  MockUser? signedInUser,
}) {
  dotenv.loadFromString(envString: 'ACCESS_CODE_PEPPER=test-pepper\n'
      'ACCESS_CODE_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=');
  final auth = MockFirebaseAuth(signedIn: signedInUser != null, mockUser: signedInUser);
  final firestore = FakeFirebaseFirestore();
  authInstance = auth;
  firestoreInstance = firestore;
  return (auth: auth, firestore: firestore);
}

/// Resets the global refs to fresh, empty fakes — deliberately NOT the real
/// FirebaseAuth.instance/FirebaseFirestore.instance, since plain `flutter
/// test` runs never call Firebase.initializeApp() and touching the real
/// singleton here would throw a "no Firebase App" error.
void tearDownMockedFirebase() {
  authInstance = MockFirebaseAuth();
  firestoreInstance = FakeFirebaseFirestore();
}
