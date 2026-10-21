// test/database/category_test.dart
//
// Replaces test/admin/admin_category_test.dart. That file reimplemented its
// own `CategoryHelper.sanitizeName` to test admin_images_screen.dart's
// category-creation dialog — but that dialog builds Database() directly
// inside a StatelessWidget method and the screen's body eagerly opens a
// StreamBuilder<QuerySnapshot> on mount, so the real screen can't be pumped
// in a test without a working Firestore connection (see the source-level
// investigation this test suite is built on: pumping it throws "no
// Firebase App" before any interaction is possible). This instead covers
// what IS reachable and real: Database.createCategory, updateCategory and
// deleteCategory. categoryName (the Cloudinary folder) is the category's own
// doc id, separate from displayName (what the user typed) — see
// createCategory's comment.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/services/database/database.dart';

void main() {
  group('Database.createCategory - AAA Pattern', () {
    late FakeFirebaseFirestore fakeDb;
    late Database database;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      database = Database(firestore: fakeDb);
    });

    test('ARRANGE-ACT-ASSERT: creating a category persists it under the owner and returns its id',
        () async {
      // ARRANGE & ACT
      final categoryId = await database.createCategory(
        displayName: 'animals',
        ownerId: 'owner_1',
        ownerRole: 'image_manager',
      );

      // ASSERT
      final doc = await fakeDb
          .collection('mediaLibrary')
          .doc('owner_1')
          .collection('categories')
          .doc(categoryId)
          .get();
      expect(doc.exists, true);
      expect(doc.data()!['categoryName'], categoryId);
      expect(doc.data()!['displayName'], 'animals');
      expect(doc.data()!['ownerRole'], 'image_manager');
    });

    test('ARRANGE-ACT-ASSERT: a spaced, mixed-case display name is stored '
        'verbatim while categoryName (the Cloudinary folder) is the doc id',
        () async {
      // ARRANGE & ACT
      final categoryId = await database.createCategory(
        displayName: 'Sea Animals',
        ownerId: 'owner_1',
        ownerRole: 'image_manager',
      );

      // ASSERT
      final doc = await fakeDb
          .collection('mediaLibrary')
          .doc('owner_1')
          .collection('categories')
          .doc(categoryId)
          .get();
      expect(doc.data()!['displayName'], 'Sea Animals');
      expect(doc.data()!['categoryName'], categoryId);
    });

    test('ARRANGE-ACT-ASSERT: updateCategory renames the displayName but '
        'keeps the Cloudinary folder (categoryName) unchanged',
        () async {
      // ARRANGE
      final categoryId = await database.createCategory(
        displayName: 'Animals',
        ownerId: 'owner_1',
        ownerRole: 'teacher',
      );

      // ACT
      await database.updateCategory(
        ownerId: 'owner_1',
        categoryId: categoryId,
        displayName: '  Farm Animals ',
      );

      // ASSERT
      final doc = await fakeDb
          .collection('mediaLibrary')
          .doc('owner_1')
          .collection('categories')
          .doc(categoryId)
          .get();
      expect(doc.data()!['displayName'], 'Farm Animals');
      expect(doc.data()!['categoryName'], categoryId);
    });

    test('ARRANGE-ACT-ASSERT: two different owners can create categories with the same name independently',
        () async {
      // ARRANGE & ACT
      final id1 = await database.createCategory(
        displayName: 'animals',
        ownerId: 'owner_1',
        ownerRole: 'image_manager',
      );
      final id2 = await database.createCategory(
        displayName: 'animals',
        ownerId: 'owner_2',
        ownerRole: 'teacher',
      );

      // ASSERT - different owners, independent subcollections, no collision
      expect(id1, isNot(equals(id2)));
      final owner1Cats = await fakeDb
          .collection('mediaLibrary')
          .doc('owner_1')
          .collection('categories')
          .get();
      final owner2Cats = await fakeDb
          .collection('mediaLibrary')
          .doc('owner_2')
          .collection('categories')
          .get();
      expect(owner1Cats.docs.length, 1);
      expect(owner2Cats.docs.length, 1);
    });

    test('ARRANGE-ACT-ASSERT: deleteCategory removes the category document', () async {
      // ARRANGE
      final categoryId = await database.createCategory(
        displayName: 'shapes',
        ownerId: 'owner_1',
        ownerRole: 'image_manager',
      );

      // ACT
      await database.deleteCategory('owner_1', categoryId);

      // ASSERT
      final doc = await fakeDb
          .collection('mediaLibrary')
          .doc('owner_1')
          .collection('categories')
          .doc(categoryId)
          .get();
      expect(doc.exists, false);
    });
  });
}
