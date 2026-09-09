// test/database/user_test.dart
//
// Replaces test/admin_validation_test.dart, which reimplemented its own
// `AdminManager` class with a hand-picked MAX_ADMINS = 3 rule that doesn't
// match the real app: Database.createUser (lib/services/database/database.dart)
// only allows exactly ONE 'image_manager' account — a stricter, different
// rule than the fake test asserted. Tested here for real against
// FakeFirebaseFirestore.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/services/database/database.dart';

void main() {
  group('Database.imageManagerExists - AAA Pattern', () {
    late FakeFirebaseFirestore fakeDb;
    late Database database;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      database = Database(firestore: fakeDb);
    });

    test('ARRANGE-ACT-ASSERT: returns false when no image_manager account exists yet',
        () async {
      // ARRANGE - empty users collection

      // ACT
      final exists = await database.imageManagerExists();

      // ASSERT
      expect(exists, false);
    });

    test('ARRANGE-ACT-ASSERT: returns true once an image_manager account exists',
        () async {
      // ARRANGE - a user with role image_manager already stored directly
      await fakeDb.collection('users').doc('uid_1').set({
        'name': 'Someone',
        'role': 'image_manager',
      });

      // ACT
      final exists = await database.imageManagerExists();

      // ASSERT
      expect(exists, true);
    });
  });

  group('Database.createUser/getUser/updateUser - AAA Pattern', () {
    late FakeFirebaseFirestore fakeDb;
    late Database database;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      database = Database(firestore: fakeDb);
    });

    test('ARRANGE-ACT-ASSERT: a user named "admin" is promoted to the image_manager role',
        () async {
      // ARRANGE & ACT
      await database.createUser(
        uid: 'uid_1',
        name: 'admin',
        email: 'admin@loringo.app',
        role: 'teacher',
        privacyPolicyAccepted: true,
      );

      // ASSERT - name-based promotion overrides the requested role
      final doc = await database.getUser('uid_1');
      final data = doc.data() as Map<String, dynamic>;
      expect(data['role'], 'image_manager');
    });

    test('ARRANGE-ACT-ASSERT: "administrador" (Spanish) is also recognized as the admin name',
        () async {
      // ARRANGE & ACT
      await database.createUser(
        uid: 'uid_2',
        name: 'Administrador',
        email: 'a2@loringo.app',
        role: 'parent',
        privacyPolicyAccepted: true,
      );

      // ASSERT
      final doc = await database.getUser('uid_2');
      expect((doc.data() as Map<String, dynamic>)['role'], 'image_manager');
    });

    test('ARRANGE-ACT-ASSERT: a second admin-named signup is rejected once one image_manager exists',
        () async {
      // ARRANGE - a first admin account already exists
      await database.createUser(
        uid: 'uid_1',
        name: 'admin',
        email: 'admin@loringo.app',
        role: 'teacher',
        privacyPolicyAccepted: true,
      );

      // ACT & ASSERT - the real limit is exactly 1, not 3 (unlike the old
      // fake test's assumption)
      expect(
        () => database.createUser(
          uid: 'uid_3',
          name: 'admin',
          email: 'admin2@loringo.app',
          role: 'teacher',
          privacyPolicyAccepted: true,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('ARRANGE-ACT-ASSERT: a non-admin name keeps the requested role', () async {
      // ARRANGE & ACT
      await database.createUser(
        uid: 'uid_4',
        name: 'Maria Teacher',
        email: 'maria@loringo.app',
        role: 'teacher',
        privacyPolicyAccepted: true,
      );

      // ASSERT
      final doc = await database.getUser('uid_4');
      expect((doc.data() as Map<String, dynamic>)['role'], 'teacher');
    });

    test('ARRANGE-ACT-ASSERT: createUser does not persist privacy policy consent fields', () async {
      // ARRANGE & ACT
      await database.createUser(
        uid: 'uid_6',
        name: 'Jane',
        email: 'jane@loringo.app',
        role: 'parent',
        privacyPolicyAccepted: true,
      );

      // ASSERT — the consent checkbox is still required client-side to
      // reach this call (and privacyPolicyAccepted is still checked as a
      // last line of defense below), but nothing about it is written to
      // the user doc.
      final doc = await database.getUser('uid_6');
      final data = doc.data() as Map<String, dynamic>;
      expect(data.containsKey('privacyPolicyAcceptedAt'), false);
      expect(data.containsKey('privacyPolicyVersion'), false);
    });

    test('ARRANGE-ACT-ASSERT: createUser rejects when privacy policy is not accepted', () async {
      // ACT & ASSERT
      expect(
        () => database.createUser(
          uid: 'uid_7',
          name: 'John',
          email: 'john@loringo.app',
          role: 'parent',
          privacyPolicyAccepted: false,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('ARRANGE-ACT-ASSERT: updateUser only writes the fields that were passed', () async {
      // ARRANGE
      await database.createUser(
        uid: 'uid_5',
        name: 'Carlos',
        email: 'carlos@loringo.app',
        role: 'teacher',
        privacyPolicyAccepted: true,
      );

      // ACT - only name is updated
      await database.updateUser(uid: 'uid_5', name: 'Carlos Updated');

      // ASSERT
      final doc = await database.getUser('uid_5');
      final data = doc.data() as Map<String, dynamic>;
      expect(data['name'], 'Carlos Updated');
    });
  });
}
