// test/admin/admin_category_test.dart
import 'package:flutter_test/flutter_test.dart';

class CategoryHelper {
  static String sanitizeName(String raw) {
    return raw
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')  // Replace special chars with _
        .replaceAll(RegExp(r'_+'), '_')              // Collapse multiple underscores
        .replaceAll(RegExp(r'^_|_$'), '')            // Remove leading/trailing underscores
        .toLowerCase();
  }
}

void main() {
  group('Category Name Sanitization - AAA Testing', () {
    
    test('Should replace spaces with underscores', () {
      // ARRANGE
      const input = 'My Category Name';
      
      // ACT
      final result = CategoryHelper.sanitizeName(input);
      
      // ASSERT
      expect(result, equals('my_category_name'));
    });

    test('Should remove special characters and collapse underscores', () {
      // ARRANGE
      const input = 'Animals & Nature!';
      
      // ACT
      final result = CategoryHelper.sanitizeName(input);
      
      // ASSERT
      expect(result, equals('animals_nature'));  // Now single underscore
    });

    test('Should convert to lowercase', () {
      // ARRANGE
      const input = 'UPPERCASE CATEGORY';
      
      // ACT
      final result = CategoryHelper.sanitizeName(input);
      
      // ASSERT
      expect(result, equals('uppercase_category'));
    });

    test('Should handle empty input', () {
      // ARRANGE
      const input = '';
      
      // ACT
      final result = CategoryHelper.sanitizeName(input);
      
      // ASSERT
      expect(result, equals(''));
    });

    test('Should handle multiple special characters', () {
      // ARRANGE
      const input = 'Hello!!! World???';
      
      // ACT
      final result = CategoryHelper.sanitizeName(input);
      
      // ASSERT
      expect(result, equals('hello_world'));
    });

    test('Should trim leading/trailing underscores', () {
      // ARRANGE
      const input = '  Hello World  ';
      
      // ACT
      final result = CategoryHelper.sanitizeName(input);
      
      // ASSERT
      expect(result, equals('hello_world'));
    });
  });
}