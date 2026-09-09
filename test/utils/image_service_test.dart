// test/utils/image_service_test.dart
//
// Replaces test/admin/admin_image_validation_test.dart and
// test/services/image_service_test.dart, both of which reimplemented their
// own private moderation/validation classes (`ImageUploadValidator`,
// `ContentModerator`) with blocked-term lists and sanitization rules that
// don't match lib/. The real filename-level moderation check is
// ImageService.checkImageNameForBlockedTerms (lib/utils/image_service.dart),
// backed by the real blocked-term list in lib/utils/moderation_terms.dart —
// both pure, synchronous, and fully real-code testable with no Firebase
// involved. (The second moderation layer, checkImageWithGoogleVision, calls
// a Cloud Function and is out of scope — Cloud Functions aren't covered by
// this test suite.)
import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/utils/image_service.dart';
import 'package:loringo_app/utils/moderation_terms.dart';

void main() {
  group('ImageService.checkImageNameForBlockedTerms - AAA Pattern', () {
    late ImageService imageService;

    setUp(() {
      imageService = ImageService();
    });

    test('ARRANGE-ACT-ASSERT: a filename containing a blocked term as its own word is rejected',
        () {
      // ARRANGE
      const fileName = 'my_naked_photo.png';

      // ACT
      final isBlocked = imageService.checkImageNameForBlockedTerms(fileName);

      // ASSERT
      expect(isBlocked, true);
    });

    test('ARRANGE-ACT-ASSERT: a filename containing a blocked term as a substring is rejected',
        () {
      // ARRANGE - "xxx" appears inside the word, not as its own token
      const fileName = 'xxxrated.png';

      // ACT
      final isBlocked = imageService.checkImageNameForBlockedTerms(fileName);

      // ASSERT
      expect(isBlocked, true);
    });

    test('ARRANGE-ACT-ASSERT: a safe, kid-appropriate filename passes', () {
      // ARRANGE
      const fileName = 'cute_elephant.png';

      // ACT
      final isBlocked = imageService.checkImageNameForBlockedTerms(fileName);

      // ASSERT
      expect(isBlocked, false);
    });

    test('ARRANGE-ACT-ASSERT: blocked term matching is case-insensitive', () {
      // ARRANGE
      const fileName = 'NUDE_drawing.svg';

      // ACT
      final isBlocked = imageService.checkImageNameForBlockedTerms(fileName);

      // ASSERT
      expect(isBlocked, true);
    });

    test('ARRANGE-ACT-ASSERT: every real blocked term in the moderation list is individually caught',
        () {
      // ARRANGE & ACT & ASSERT - exercises the actual production list, not
      // a hand-copied one, so this test keeps working if the list changes.
      for (final term in kidsafeModerationBlockedTerms) {
        final isBlocked = imageService.checkImageNameForBlockedTerms('$term.png');
        expect(isBlocked, true, reason: 'Expected "$term.png" to be blocked');
      }
    });
  });
}
