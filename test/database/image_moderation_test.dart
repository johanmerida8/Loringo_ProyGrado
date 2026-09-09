// test/database/image_moderation_test.dart
//
// Replaces test/admin/admin_approval_test.dart, which reimplemented its own
// `ApprovalHelper` class with UI copy strings that have no real counterpart
// in lib/. The real, persisted moderation behavior is
// Database.approveImage/rejectImage, tested here for real against
// FakeFirebaseFirestore. (approveImage/rejectImage read
// lib/services/firebase_refs.dart's authInstance for the approving/rejecting
// uid, the same swappable indirection used for the login/register/auth_gate
// flows, so MockFirebaseAuth is used here too.)
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/services/firebase_refs.dart';

import '../helpers/firebase_test_setup.dart';

void main() {
  group('Database.approveImage/rejectImage - AAA Pattern', () {
    late FakeFirebaseFirestore fakeDb;
    late Database database;

    setUp(() async {
      fakeDb = FakeFirebaseFirestore();
      database = Database(firestore: fakeDb);
      authInstance = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'moderator_1'),
      );
      await fakeDb
          .collection('mediaLibrary')
          .doc('owner_1')
          .collection('categories')
          .doc('cat_1')
          .collection('imageItems')
          .doc('img_1')
          .set({
        'name': 'test_image',
        'moderationStatus': 'pending',
        'isVisible': false,
      });
    });

    tearDown(() {
      tearDownMockedFirebase();
    });

    test('ARRANGE-ACT-ASSERT: approving an image marks it visible and records the approver',
        () async {
      // ARRANGE & ACT
      await database.approveImage(
        ownerId: 'owner_1',
        categoryId: 'cat_1',
        imageId: 'img_1',
      );

      // ASSERT
      final doc = await fakeDb
          .collection('mediaLibrary')
          .doc('owner_1')
          .collection('categories')
          .doc('cat_1')
          .collection('imageItems')
          .doc('img_1')
          .get();
      final data = doc.data()!;
      expect(data['moderationStatus'], 'approved');
      expect(data['isVisible'], true);
      expect(data['approvedBy'], 'moderator_1');
      expect(data['rejectedBy'], null);
    });

    test('ARRANGE-ACT-ASSERT: rejecting an image hides it and records the rejector', () async {
      // ARRANGE & ACT
      await database.rejectImage(
        ownerId: 'owner_1',
        categoryId: 'cat_1',
        imageId: 'img_1',
      );

      // ASSERT
      final doc = await fakeDb
          .collection('mediaLibrary')
          .doc('owner_1')
          .collection('categories')
          .doc('cat_1')
          .collection('imageItems')
          .doc('img_1')
          .get();
      final data = doc.data()!;
      expect(data['moderationStatus'], 'rejected');
      expect(data['isVisible'], false);
      expect(data['rejectedBy'], 'moderator_1');
    });
  });
}
