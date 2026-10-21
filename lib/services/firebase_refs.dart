import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Swappable indirection over the Firebase singletons. Production code never
/// reassigns these — only test setUp()/tearDown() does, so widget/integration
/// tests can substitute MockFirebaseAuth/FakeFirebaseFirestore without any
/// change to call-site behavior in the app itself.
FirebaseAuth authInstance = FirebaseAuth.instance;
FirebaseFirestore firestoreInstance = FirebaseFirestore.instance;

/// Group-code lookup (Database.findGroupByCode). In the app this calls the
/// `findGroupByCode` Cloud Function (functions/src/groupCode.ts), which
/// hashes the code server-side; `flutter test` has no Functions backend,
/// so tests swap in a fake with the same return shape
/// ({groupId, name, archived, teacherId}, or null when no group matches).
typedef GroupCodeLookup = Future<Map<String, dynamic>?> Function(String code);

GroupCodeLookup findGroupByCodeCall = _callFindGroupByCodeFunction;

Future<Map<String, dynamic>?> _callFindGroupByCodeFunction(String code) async {
  final result = await FirebaseFunctions.instance
      .httpsCallable('findGroupByCode')
      .call({'code': code});
  if (result.data == null) return null;
  return (result.data as Map).cast<String, dynamic>();
}
