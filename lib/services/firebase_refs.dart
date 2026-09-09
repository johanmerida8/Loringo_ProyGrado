import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Swappable indirection over the Firebase singletons. Production code never
/// reassigns these — only test setUp()/tearDown() does, so widget/integration
/// tests can substitute MockFirebaseAuth/FakeFirebaseFirestore without any
/// change to call-site behavior in the app itself.
FirebaseAuth authInstance = FirebaseAuth.instance;
FirebaseFirestore firestoreInstance = FirebaseFirestore.instance;
