// test/database/student_access_code_test.dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/utils/access_code_hasher.dart';

void main() {
  setUp(() {
    dotenv.loadFromString(envString: 'ACCESS_CODE_PEPPER=test-pepper\n'
        'ACCESS_CODE_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=');
  });

  group('Database student access codes - AAA Pattern', () {
    test('createStudent never stores the plaintext code, only its hash and an encrypted copy', () async {
      // ARRANGE
      final firestore = FakeFirebaseFirestore();
      final db = Database(firestore: firestore);

      // ACT
      final code = await db.createStudent(
        parentId: 'parent_1',
        names: 'Juan Perez',
        avatar: 'assets/avatars/parrot.png',
        childDataConsentAccepted: true,
      );

      // ASSERT
      expect(code.length, 6);
      final snap = await firestore.collection('students').get();
      final data = snap.docs.first.data();
      expect(data.containsKey('accessCode'), false);
      expect(data['accessCodeHash'], AccessCodeHasher.hash(code));
      expect(data['accessCodeEncrypted'], isNot(code));
    });

    test('the 9th child registration is rejected once 8 already exist', () async {
      // ARRANGE
      final firestore = FakeFirebaseFirestore();
      final db = Database(firestore: firestore);
      for (var i = 0; i < 8; i++) {
        await db.createStudent(
          parentId: 'parent_1',
          names: 'Child $i',
          avatar: 'assets/avatars/parrot.png',
          childDataConsentAccepted: true,
        );
      }

      // ACT / ASSERT
      expect(
        () => db.createStudent(
          parentId: 'parent_1',
          names: 'One Too Many',
          avatar: 'assets/avatars/parrot.png',
          childDataConsentAccepted: true,
        ),
        throwsA(predicate((e) => e.toString().contains('max_children_reached'))),
      );
    });

    test('findStudentByAccessCode logs in with the right code and rejects the wrong one', () async {
      // ARRANGE
      final firestore = FakeFirebaseFirestore();
      final db = Database(firestore: firestore);
      final code = await db.createStudent(
        parentId: 'parent_1',
        names: 'Juan Perez',
        avatar: 'assets/avatars/parrot.png',
        childDataConsentAccepted: true,
      );

      // ACT
      final found = await db.findStudentByAccessCode(code);
      final notFound = await db.findStudentByAccessCode('WRONG1');

      // ASSERT
      expect(found?['names'], 'Juan Perez');
      expect(notFound, null);
    });

    test('the code is static — revealAccessCode always decrypts back to the original, and login keeps working after multiple reveals', () async {
      // ARRANGE
      final firestore = FakeFirebaseFirestore();
      final db = Database(firestore: firestore);
      final code = await db.createStudent(
        parentId: 'parent_1',
        names: 'Juan Perez',
        avatar: 'assets/avatars/parrot.png',
        childDataConsentAccepted: true,
      );
      final studentId =
          (await firestore.collection('students').get()).docs.first.id;

      // ACT
      final revealed1 = await db.revealAccessCode(studentId);
      final revealed2 = await db.revealAccessCode(studentId);

      // ASSERT — same code every time, and it still logs the student in
      expect(revealed1, code);
      expect(revealed2, code);
      expect((await db.findStudentByAccessCode(code))?['id'], studentId);
    });

    test('revealAccessCode re-syncs a stale accessCodeHash so login keeps working', () async {
      // ARRANGE — a doc where accessCodeHash has drifted out of sync with
      // accessCodeEncrypted (e.g. from some earlier inconsistent write)
      final firestore = FakeFirebaseFirestore();
      final db = Database(firestore: firestore);
      final code = await db.createStudent(
        parentId: 'parent_1',
        names: 'Juan Perez',
        avatar: 'assets/avatars/parrot.png',
        childDataConsentAccepted: true,
      );
      final ref = (await firestore.collection('students').get()).docs.first.reference;
      await ref.update({'accessCodeHash': 'stale_hash_from_somewhere'});

      // ACT
      final revealed = await db.revealAccessCode(ref.id);

      // ASSERT — the real code still comes back, the stale hash is
      // repaired, and login with the real code works again
      expect(revealed, code);
      final data = (await ref.get()).data() as Map<String, dynamic>;
      expect(data['accessCodeHash'], AccessCodeHasher.hash(code));
      expect((await db.findStudentByAccessCode(code))?['id'], ref.id);
    });

    test('findStudentByAccessCode logs in a legacy plaintext student and migrates the doc', () async {
      // ARRANGE — a student doc shaped like it predates hashing entirely,
      // never yet "revealed" by a parent
      final firestore = FakeFirebaseFirestore();
      final db = Database(firestore: firestore);
      final ref = await firestore.collection('students').add({
        'parentId': 'parent_1',
        'names': 'Legacy Kid',
        'accessCode': 'LEGACY',
        'avatar': 'assets/avatars/parrot.png',
      });

      // ACT
      final found = await db.findStudentByAccessCode('LEGACY');

      // ASSERT — login succeeds, and the doc is now migrated for next time
      expect(found?['id'], ref.id);
      final data = (await ref.get()).data() as Map<String, dynamic>;
      expect(data.containsKey('accessCode'), false);
      expect(data['accessCodeHash'], AccessCodeHasher.hash('LEGACY'));
      expect(await db.findStudentByAccessCode('LEGACY'), isNotNull);
    });

    test('revealAccessCode self-heals a legacy plaintext doc instead of throwing', () async {
      // ARRANGE — a student doc shaped like it predates hashing entirely
      final firestore = FakeFirebaseFirestore();
      final db = Database(firestore: firestore);
      final ref = await firestore.collection('students').add({
        'parentId': 'parent_1',
        'names': 'Legacy Kid',
        'accessCode': 'LEGACY',
        'avatar': 'assets/avatars/parrot.png',
      });

      // ACT
      final revealed = await db.revealAccessCode(ref.id);

      // ASSERT — original code preserved, doc migrated in place
      expect(revealed, 'LEGACY');
      final data = (await ref.get()).data() as Map<String, dynamic>;
      expect(data.containsKey('accessCode'), false);
      expect(data['accessCodeHash'], AccessCodeHasher.hash('LEGACY'));
      expect(await db.revealAccessCode(ref.id), 'LEGACY');
    });

    test('revealAccessCode issues a fresh code for a hash-only legacy doc with nothing recoverable', () async {
      // ARRANGE — a student doc shaped like the brief hash-only window
      // (no plaintext, no accessCodeEncrypted)
      final firestore = FakeFirebaseFirestore();
      final db = Database(firestore: firestore);
      final ref = await firestore.collection('students').add({
        'parentId': 'parent_1',
        'names': 'Hash Only Kid',
        'accessCodeHash': 'some_old_hash',
        'avatar': 'assets/avatars/parrot.png',
      });

      // ACT
      final revealed = await db.revealAccessCode(ref.id);

      // ASSERT — a usable code now exists and is stable afterward
      expect(revealed.length, 6);
      expect(await db.revealAccessCode(ref.id), revealed);
      expect((await db.findStudentByAccessCode(revealed))?['id'], ref.id);
    });

    test('verifyAccessCode matches the static code', () async {
      // ARRANGE
      final firestore = FakeFirebaseFirestore();
      final db = Database(firestore: firestore);
      final code = await db.createStudent(
        parentId: 'parent_1',
        names: 'Juan Perez',
        avatar: 'assets/avatars/parrot.png',
        childDataConsentAccepted: true,
      );
      final studentId =
          (await firestore.collection('students').get()).docs.first.id;

      // ACT / ASSERT
      expect(await db.verifyAccessCode(studentId, code), true);
      expect(await db.verifyAccessCode(studentId, 'WRONG1'), false);
    });
  });
}
