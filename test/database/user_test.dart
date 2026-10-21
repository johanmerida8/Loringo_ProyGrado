// test/database/user_test.dart
//
// Replaces test/admin_validation_test.dart, which reimplemented its own
// `AdminManager` class with a hand-picked MAX_ADMINS = 3 rule that doesn't
// match the real app.
//
// Note on naming: the app has no "administrator" role. `image_manager` is
// an elevated role that only curates the educational image library.
// Database.createUser never auto-promotes based on the name argument —
// public self-registration can only create 'teacher'/'parent' accounts;
// image_manager accounts are not created through this app's sign-up flow
// at all (see register_screen.dart). Tested here for real against
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

    test('ARRANGE-ACT-ASSERT: a user named "admin" keeps the requested role — no name-based promotion',
        () async {
      // ARRANGE & ACT
      await database.createUser(
        uid: 'uid_1',
        name: 'admin',
        email: 'admin@loringo.app',
        role: 'teacher',
        privacyPolicyAccepted: true,
      );

      // ASSERT - the name "admin" no longer has any special meaning
      final doc = await database.getUser('uid_1');
      final data = doc.data() as Map<String, dynamic>;
      expect(data['role'], 'teacher');
    });

    test('ARRANGE-ACT-ASSERT: a user named "administrador" (Spanish) also keeps the requested role',
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
      expect((doc.data() as Map<String, dynamic>)['role'], 'parent');
    });

    test('ARRANGE-ACT-ASSERT: createUser can still create an image_manager account when role is passed explicitly',
        () async {
      // ARRANGE & ACT - only reachable by a caller other than RegisterScreen
      // (e.g. a manual/back-office flow), since the public sign-up form
      // never offers or sends role: 'image_manager'
      await database.createUser(
        uid: 'uid_3',
        name: 'Maria',
        email: 'maria@loringo.app',
        role: 'image_manager',
        privacyPolicyAccepted: true,
      );

      // ASSERT
      final doc = await database.getUser('uid_3');
      expect((doc.data() as Map<String, dynamic>)['role'], 'image_manager');
    });

    test('ARRANGE-ACT-ASSERT: a second explicit image_manager creation is rejected once one exists',
        () async {
      // ARRANGE - a first image_manager account already exists
      await database.createUser(
        uid: 'uid_3',
        name: 'Maria',
        email: 'maria@loringo.app',
        role: 'image_manager',
        privacyPolicyAccepted: true,
      );

      // ACT & ASSERT - the cap is exactly 1
      expect(
        () => database.createUser(
          uid: 'uid_8',
          name: 'Pedro',
          email: 'pedro@loringo.app',
          role: 'image_manager',
          privacyPolicyAccepted: true,
        ),
        throwsA(isA<Exception>()),
      );
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
