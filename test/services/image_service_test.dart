// test/services/image_service_test.dart
import 'package:flutter_test/flutter_test.dart';

class ContentModerator {
  static const Set<String> blockedTerms = {
    'gun', 'firearm', 'pistol', 'rifle', 'shotgun', 'revolver',
    'ammunition', 'bullet', 'explosive', 'grenade', 'bomb',
    'gore', 'corpse', 'murder', 'kill', 'killing', 'stab',
    'nudity', 'naked', 'sex', 'sexual', 'intercourse',
    'vagina', 'penis', 'genitals', 'pornography', 'porn', 'xxx', 'erotic',
    'cocaine', 'heroin', 'methamphetamine', 'marijuana', 'cannabis',
    'cigarette', 'smoking', 'vape', 'vaping', 'syringe', 'needle', 'overdose',
    'robbery', 'kidnapping', 'rape', 'assault', 'gang', 'gangster',
    'demon', 'devil', 'zombie', 'gambling', 'casino', 'pornographic',
  };

  static const List<String> allowedExtensions = ['png', 'svg'];
  static const int MAX_FILE_SIZE_MB = 5;
  static const int MAX_FILE_SIZE_BYTES = MAX_FILE_SIZE_MB * 1024 * 1024;

  static bool isAllowedExtension(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    return allowedExtensions.contains(extension);
  }

  static String sanitizeFileName(String fileName) {
    // Replace special characters with underscore, then collapse multiple underscores
    String result = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9.\-]'), '_');
    // Collapse multiple underscores into single underscore
    result = result.replaceAll(RegExp(r'_+'), '_');
    return result.toLowerCase();
  }

  static bool containsBlockedTerm(String text) {
    final lowerText = text.toLowerCase();
    for (final term in blockedTerms) {
      if (lowerText.contains(term)) {
        return true;
      }
    }
    return false;
  }

  static String? validateImageName(String name) {
    if (name == null || name.trim().isEmpty) {
      return 'Image name is required';
    }
    if (name.trim().length < 2) {
      return 'Image name must be at least 2 characters';
    }
    if (containsBlockedTerm(name)) {
      return 'Image name contains inappropriate content';
    }
    return null;
  }
}

void main() {
  group('Image Service - AAA Pattern', () {
    
    group('File Name Sanitization', () {
      
      test('ARRANGE-ACT-ASSERT: Replace spaces with underscores', () {
        // ARRANGE
        const String fileName = 'my cute image.png';
        const String expected = 'my_cute_image.png';
        
        // ACT
        final String result = ContentModerator.sanitizeFileName(fileName);
        
        // ASSERT
        expect(result, expected);
      });

      test('ARRANGE-ACT-ASSERT: Remove special characters', () {
        // ARRANGE
        const String fileName = r'animal!@#$%^&*.png';
        const String expected = 'animal_.png';
        
        // ACT
        final String result = ContentModerator.sanitizeFileName(fileName);
        
        // ASSERT
        expect(result, expected);
      });

      test('ARRANGE-ACT-ASSERT: Convert to lowercase', () {
        // ARRANGE
        const String fileName = 'UPPERCASE_IMAGE.PNG';
        const String expected = 'uppercase_image.png';
        
        // ACT
        final String result = ContentModerator.sanitizeFileName(fileName);
        
        // ASSERT
        expect(result, expected);
      });

      test('ARRANGE-ACT-ASSERT: Collapse multiple special characters', () {
        // ARRANGE
        const String fileName = r'hello!!!world???test.png';
        const String expected = 'hello_world_test.png';
        
        // ACT
        final String result = ContentModerator.sanitizeFileName(fileName);
        
        // ASSERT
        expect(result, expected);
      });

      test('ARRANGE-ACT-ASSERT: Handle mix of spaces and special chars', () {
        // ARRANGE
        const String fileName = r'hello   world!!! test.png';
        const String expected = 'hello_world_test.png';
        
        // ACT
        final String result = ContentModerator.sanitizeFileName(fileName);
        
        // ASSERT
        expect(result, expected);
      });
    });

    group('Blocked Terms Detection', () {
      
      test('ARRANGE-ACT-ASSERT: Detect weapon term - gun', () {
        // ARRANGE
        const String text = 'This image contains a gun';
        
        // ACT
        final bool hasBlockedTerm = ContentModerator.containsBlockedTerm(text);
        
        // ASSERT
        expect(hasBlockedTerm, true);
      });

      test('ARRANGE-ACT-ASSERT: Detect drug term - cocaine', () {
        // ARRANGE
        const String text = 'cocaine use';
        
        // ACT
        final bool hasBlockedTerm = ContentModerator.containsBlockedTerm(text);
        
        // ASSERT
        expect(hasBlockedTerm, true);
      });

      test('ARRANGE-ACT-ASSERT: Case insensitive detection', () {
        // ARRANGE
        const String text = 'GUN and Knife';
        
        // ACT
        final bool hasBlockedTerm = ContentModerator.containsBlockedTerm(text);
        
        // ASSERT
        expect(hasBlockedTerm, true);
      });

      test('ARRANGE-ACT-ASSERT: Safe text passes', () {
        // ARRANGE
        const String text = 'Beautiful landscape with mountains';
        
        // ACT
        final bool hasBlockedTerm = ContentModerator.containsBlockedTerm(text);
        
        // ASSERT
        expect(hasBlockedTerm, false);
      });
    });

    group('Image Name Validation', () {
      
      test('ARRANGE-ACT-ASSERT: Reject empty image name', () {
        // ARRANGE
        const String name = '';
        
        // ACT
        final String? result = ContentModerator.validateImageName(name);
        
        // ASSERT
        expect(result, 'Image name is required');
      });

      test('ARRANGE-ACT-ASSERT: Reject name too short', () {
        // ARRANGE
        const String name = 'a';
        
        // ACT
        final String? result = ContentModerator.validateImageName(name);
        
        // ASSERT
        expect(result, 'Image name must be at least 2 characters');
      });

      test('ARRANGE-ACT-ASSERT: Reject name with blocked term', () {
        // ARRANGE
        const String name = 'gun_image';
        
        // ACT
        final String? result = ContentModerator.validateImageName(name);
        
        // ASSERT
        expect(result, 'Image name contains inappropriate content');
      });

      test('ARRANGE-ACT-ASSERT: Accept valid image name', () {
        // ARRANGE
        const String name = 'cute_animal';
        
        // ACT
        final String? result = ContentModerator.validateImageName(name);
        
        // ASSERT
        expect(result, isNull);
      });
    });

    group('File Extension Validation', () {
      
      test('ARRANGE-ACT-ASSERT: Accept PNG extension', () {
        // ARRANGE
        const String fileName = 'image.png';
        
        // ACT
        final bool isValid = ContentModerator.isAllowedExtension(fileName);
        
        // ASSERT
        expect(isValid, true);
      });

      test('ARRANGE-ACT-ASSERT: Accept SVG extension', () {
        // ARRANGE
        const String fileName = 'image.svg';
        
        // ACT
        final bool isValid = ContentModerator.isAllowedExtension(fileName);
        
        // ASSERT
        expect(isValid, true);
      });

      test('ARRANGE-ACT-ASSERT: Reject JPG extension', () {
        // ARRANGE
        const String fileName = 'image.jpg';
        
        // ACT
        final bool isValid = ContentModerator.isAllowedExtension(fileName);
        
        // ASSERT
        expect(isValid, false);
      });
    });
  });
}