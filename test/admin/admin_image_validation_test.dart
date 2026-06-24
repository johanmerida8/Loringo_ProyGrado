// test/admin/admin_image_validation_test.dart
import 'package:flutter_test/flutter_test.dart';

class ImageUploadValidator {
  static const int minRecommended = 15;
  
  static bool isRecommended(int count) => count >= minRecommended;
  
  static String? validateFileExtension(String fileName) {
    final ext = fileName.toLowerCase();
    if (!ext.endsWith('.png') && !ext.endsWith('.svg')) {
      return 'Only PNG and SVG files are accepted';
    }
    return null;
  }
  
  static String getStatusMessage(int count) {
    if (count == 0) return 'No images selected';
    if (count >= minRecommended) return '$count selected · Ready!';
    return '$count selected · ${minRecommended - count} more recommended';
  }
}

void main() {
  group('Admin Image Upload Validation - AAA Testing', () {
    
    test('Should accept PNG files', () {
      // ARRANGE
      const fileName = 'image.png';
      
      // ACT
      final result = ImageUploadValidator.validateFileExtension(fileName);
      
      // ASSERT
      expect(result, isNull);
    });

    test('Should accept SVG files', () {
      // ARRANGE
      const fileName = 'icon.svg';
      
      // ACT
      final result = ImageUploadValidator.validateFileExtension(fileName);
      
      // ASSERT
      expect(result, isNull);
    });

    test('Should reject non-image files', () {
      // ARRANGE
      const fileName = 'document.pdf';
      
      // ACT
      final result = ImageUploadValidator.validateFileExtension(fileName);
      
      // ASSERT
      expect(result, equals('Only PNG and SVG files are accepted'));
    });

    test('Should recommend 15+ images', () {
      // ARRANGE
      const count = 15;
      
      // ACT
      final recommended = ImageUploadValidator.isRecommended(count);
      
      // ASSERT
      expect(recommended, isTrue);
    });

    test('Should not recommend less than 15 images', () {
      // ARRANGE
      const count = 10;
      
      // ACT
      final recommended = ImageUploadValidator.isRecommended(count);
      
      // ASSERT
      expect(recommended, isFalse);
    });
  });
}