import 'package:flutter_test/flutter_test.dart';
import 'package:loringo_app/services/speech_to_text/phrase_matcher.dart';

void main() {
  group('PhraseMatcher — ~70% per word, one miss allowed from 4 words', () {
    test('exact phrase is correct', () {
      expect(PhraseMatcher.match('The cat is red', 'The cat is red.').isCorrect,
          isTrue);
    });

    test('one misheard letter in a word still counts', () {
      // "red" heard as "rad" — 1 letter off.
      expect(PhraseMatcher.match('the cat is rad', 'The cat is red').isCorrect,
          isTrue);
      // "dress" heard as "dres".
      expect(PhraseMatcher.match('I wear a dres', 'I wear a dress').isCorrect,
          isTrue);
    });

    test('one missing word is accepted in phrases of 4+ words (3/4)', () {
      final r = PhraseMatcher.match('the cat is', 'The cat is red');
      expect(r.isCorrect, isTrue);
      expect(r.matchedCount, 3);
      expect(r.totalCount, 4);
    });

    test('a 3/4 pass reports the missed word as partial', () {
      final r = PhraseMatcher.match('the sky is white', 'The sky is blue');
      expect(r.isCorrect, isTrue);
      expect(r.isPartial, isTrue);
      expect(r.missedWords, ['blue']);
      final perfect = PhraseMatcher.match('the sky is blue', 'The sky is blue');
      expect(perfect.isPartial, isFalse);
      expect(perfect.missedWords, isEmpty);
    });

    test('two missing words are wrong', () {
      expect(PhraseMatcher.match('the cat', 'The cat is red').isCorrect,
          isFalse);
    });

    test('short phrases (<4 words) need every word', () {
      expect(PhraseMatcher.match('the cat', 'The cat is').isCorrect, isFalse);
    });

    test('a clearly different word is wrong', () {
      // "red" vs "rat": 2 of 3 letters differ — beyond the margin, so it
      // counts as a miss. Alone that's 3/4 (passes); two such words fail.
      expect(PhraseMatcher.match('the cat is rat', 'The cat is red').isCorrect,
          isTrue);
      expect(PhraseMatcher.match('the dog is rat', 'The cat is red').isCorrect,
          isFalse);
      expect(PhraseMatcher.match('the dog is blue', 'The cat is red').isCorrect,
          isFalse);
    });

    test('extra filler words are ignored', () {
      expect(
          PhraseMatcher.match('um the cat is red', 'The cat is red').isCorrect,
          isTrue);
    });

    test('digits and contractions are normalized', () {
      expect(PhraseMatcher.match('I have 2 dogs', 'I have two dogs').isCorrect,
          isTrue);
      expect(PhraseMatcher.match('I do not like it', "I don't like it")
          .isCorrect, isTrue);
    });

    test('joined/split words still match', () {
      expect(PhraseMatcher.match('I like icecream', 'I like ice cream')
          .isCorrect, isTrue);
    });

    test('a short word missing next to a long one counts as one miss', () {
      // Reported bug: "apple" alone was accepted as "apple"+"is" glued
      // together, hiding the skipped "is". It must still count as a miss:
      // one miss passes (3/4), two misses fail.
      for (final heard in [
        'the apple red',
        'apple is red',
        'the apple is',
        'the is red',
      ]) {
        final r = PhraseMatcher.match(heard, 'The apple is red');
        expect(r.matchedCount, 3, reason: '"$heard" is missing one word');
      }
      expect(PhraseMatcher.match('apple red', 'The apple is red').isCorrect,
          isFalse);
    });

    test('segments heard across pauses are joined into one phrase', () {
      expect(PhraseMatcher.joinSegments('', 'the sky'), 'the sky');
      expect(PhraseMatcher.joinSegments('the sky', ''), 'the sky');
      expect(PhraseMatcher.joinSegments('the sky ', ' is blue'),
          'the sky is blue');
      final joined = PhraseMatcher.joinSegments('the sky', 'is blue');
      final r = PhraseMatcher.match(joined, 'The sky is blue');
      expect(r.isCorrect, isTrue);
      expect(r.missedWords, isEmpty);
    });

    test('startsNewUtterance tells a restart from a continuation', () {
      expect(PhraseMatcher.startsNewUtterance('the sky', 'is'), isTrue);
      expect(PhraseMatcher.startsNewUtterance('is', 'blue'), isTrue);
      expect(PhraseMatcher.startsNewUtterance('the', 'sky'), isTrue);
      expect(PhraseMatcher.startsNewUtterance('the', 'the sky'), isFalse);
      expect(PhraseMatcher.startsNewUtterance('to', 'two'), isFalse);
      expect(PhraseMatcher.startsNewUtterance('the sky', 'the sky is'),
          isFalse);
      expect(PhraseMatcher.startsNewUtterance('', 'the'), isFalse);
      expect(PhraseMatcher.startsNewUtterance('the', ''), isFalse);
    });

    test('words said one at a time all add up (no word is dropped)', () {
      // Mirrors the service: the engine drops its old text after each
      // pause, so each earlier piece is committed when a new one starts.
      var committed = '';
      var segment = '';
      for (final heard in ['the', 'the sky', 'is', 'blue']) {
        if (PhraseMatcher.startsNewUtterance(segment, heard)) {
          committed = PhraseMatcher.joinSegments(committed, segment);
        }
        segment = heard;
      }
      final all = PhraseMatcher.joinSegments(committed, segment);
      final r = PhraseMatcher.match(all, 'The sky is blue');
      expect(r.isCorrect, isTrue);
      expect(r.missedWords, isEmpty);
    });

    test('a word accepted only by tolerance is reported as approximate', () {
      final gross =
          PhraseMatcher.match('the gross is green', 'The grass is green');
      expect(gross.isCorrect, isTrue);
      expect(gross.missedWords, isEmpty);
      expect(gross.approximateWords, ['grass']);
      expect(gross.isImperfect, isTrue);

      final rad = PhraseMatcher.match('the cat is rad', 'The cat is red');
      expect(rad.approximateWords, ['red']);
    });

    test('exact answers have nothing approximate or missed', () {
      final r = PhraseMatcher.match('The grass is green', 'The grass is green');
      expect(r.approximateWords, isEmpty);
      expect(r.missedWords, isEmpty);
      expect(r.isImperfect, isFalse);
      // Digits and contractions are normalized, so they are still exact.
      expect(PhraseMatcher.match('I have 2 dogs', 'I have two dogs')
          .approximateWords, isEmpty);
      // Joined/split words heard exactly are not approximate either.
      expect(PhraseMatcher.match('I like icecream', 'I like ice cream')
          .approximateWords, isEmpty);
    });

    test('an extra heard word and a changed word: only target words count', () {
      // The recognizer added "in" (never said) and heard "rat" for "red".
      final r = PhraseMatcher.match('in the apple is rat', 'The apple is red');
      expect(r.isCorrect, isTrue);
      expect(r.matchedTargetIndexes, [0, 1, 2]);
      expect(r.missedWords, ['red']);
      expect(r.approximateIndexes, isEmpty);

      final g = PhraseMatcher.match('the gross is green', 'The grass is green');
      expect(g.approximateIndexes, [1]);
      expect(g.matchedTargetIndexes, [0, 1, 2, 3]);
    });

    test('a missing word is missed, not approximate', () {
      final r = PhraseMatcher.match('the sky is', 'The sky is blue');
      expect(r.missedWords, ['blue']);
      expect(r.approximateWords, isEmpty);
      expect(r.isImperfect, isTrue);
    });

    test('nothing heard is wrong', () {
      expect(PhraseMatcher.match('', 'Hello').isCorrect, isFalse);
    });
  });
}
