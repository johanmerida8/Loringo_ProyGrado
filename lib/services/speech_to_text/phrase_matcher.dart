// lib/services/speech_to_text/phrase_matcher.dart
//
// Decides whether what the speech recognizer heard counts as the student
// saying the target phrase. Shared by SpeechToTextService (the pass/fail
// verdict for repeat_after_me, listen_and_speak and slow_reveal) and
// ScreenNine's live word highlighting, so both use the exact same rule.
//
// THE RULE (agreed with the product owner):
//   - The words of the phrase must be said, in order. Phrases of 4+ words
//     may miss ONE word (3/4 passes) so a word the recognizer never heard
//     doesn't fail an otherwise complete answer; shorter phrases need
//     every word.
//   - Each word only has to be ~70% right, not perfect: the device
//     recognizer (no AI tuned for kids or for a Spanish accent) often
//     mishears a letter or two of a word the student did say, e.g.
//     "red" -> "rad", "dress" -> "dres". Up to 30% of a word's letters
//     may differ, and always at least 1 letter, so short words still get
//     a one-letter margin.
//   - At most a quarter of the words (min. 1) may be "flawed" in total —
//     missing OR only approximately said, counted together — so a phrase
//     can't pass with several loose words (see [maxFlawedWords]).
//   - Extra words the recognizer adds ("um", a repeated word) are ignored.
//
// Before comparing, both sides are normalized so formatting differences
// the student can't control never count as mistakes: case, punctuation,
// digits vs. words ("2" == "two") and contractions ("don't" == "do not").

class PhraseMatchResult {
  const PhraseMatchResult({
    required this.isCorrect,
    required this.matchedCount,
    required this.totalCount,
    required this.matchedTargetIndexes,
    this.missedWords = const [],
    this.approximateWords = const [],
    this.approximateIndexes = const [],
  });

  final bool isCorrect;
  final int matchedCount;
  final int totalCount;

  /// Target words that were not heard (normalized). Non-empty with
  /// [isCorrect] means a "almost perfect" pass.
  final List<String> missedWords;

  /// Target words that were heard but only approximately (within the
  /// letter tolerance, e.g. "gross" for "grass") — they pass, but the
  /// answer was not exact.
  final List<String> approximateWords;

  /// Same words as [approximateWords], as indexes into the target's words.
  final List<int> approximateIndexes;

  /// Passed, but with a word missing (3/4) — not a perfect answer.
  bool get isPartial => isCorrect && missedWords.isNotEmpty;

  /// Passed, but not exactly: a word is missing or only approximately
  /// pronounced. Only an answer that is NOT imperfect deserves "Perfect!".
  bool get isImperfect =>
      isCorrect && (missedWords.isNotEmpty || approximateWords.isNotEmpty);

  /// Indexes (into the target's words, in order) that were heard — used
  /// for highlighting which words the student already got.
  final List<int> matchedTargetIndexes;

  double get accuracy => totalCount == 0 ? 1.0 : matchedCount / totalCount;
}

class PhraseMatcher {
  PhraseMatcher._();

  /// Fraction of a word's letters that may be wrong and still count.
  static const double letterTolerance = 0.3;

  /// Phrases of at least this many words may miss one word and still pass.
  static const int minWordsToAllowMiss = 4;

  /// How many target words may go unheard and still count as correct:
  /// one for phrases of [minWordsToAllowMiss]+ words, none for shorter ones.
  static int allowedMissing(int totalWords) =>
      totalWords >= minWordsToAllowMiss ? 1 : 0;

  /// Fraction of a phrase's words that may be flawed (missing or only
  /// approximately said) and still pass — about 75 % of the words must be
  /// right, since device recognizers are noticeably worse with children.
  static const double flawTolerance = 0.25;

  /// How many words in total may be flawed for a phrase of [totalWords]
  /// words: 25 % rounded down, but never less than 1 — so 1 to 7 words
  /// allow 1, 8 to 11 allow 2, 12 or more allow 3.
  static int maxFlawedWords(int totalWords) {
    final allowed = (totalWords * flawTolerance).floor();
    return allowed < 1 ? 1 : allowed;
  }

  /// Matches [spoken] against [target] under the rule above.
  static PhraseMatchResult match(String spoken, String target) {
    final targetWords = words(target);
    if (targetWords.isEmpty) {
      return const PhraseMatchResult(
        isCorrect: true,
        matchedCount: 0,
        totalCount: 0,
        matchedTargetIndexes: [],
      );
    }
    final spokenWords = words(spoken);

    // Walk the target in order; for each target word, look forward in
    // what was heard for the first word close enough to it. Skipped
    // spoken words are extras and simply ignored.
    //
    // The recognizer sometimes joins or splits a word ("ice cream" vs
    // "icecream", "backpack" vs "back pack"), so two NEIGHBOURING words
    // may also be glued together on either side — never more than two,
    // so a missing word can't hide inside a long glued string.
    final matched = <int>[];
    final approximate = <int>[];
    var si = 0;
    var ti = 0;
    while (ti < targetWords.length) {
      var advancedTarget = 1;
      var found = false;
      var exact = true;
      for (var k = si; k < spokenWords.length; k++) {
        if (wordsMatch(spokenWords[k], targetWords[ti])) {
          si = k + 1;
          found = true;
          exact = normalizeWord(spokenWords[k]) == normalizeWord(targetWords[ti]);
        } else if (k + 1 < spokenWords.length &&
            wordsMatch(spokenWords[k] + spokenWords[k + 1], targetWords[ti])) {
          si = k + 2; // target word heard split in two
          found = true;
          exact = normalizeWord(spokenWords[k] + spokenWords[k + 1]) ==
              normalizeWord(targetWords[ti]);
        } else if (ti + 1 < targetWords.length &&
            wordsMatch(spokenWords[k], targetWords[ti] + targetWords[ti + 1])) {
          si = k + 1; // two target words heard glued into one
          advancedTarget = 2;
          found = true;
          exact = normalizeWord(spokenWords[k]) ==
              normalizeWord(targetWords[ti] + targetWords[ti + 1]);
        }
        if (found) break;
      }
      if (found) {
        for (var j = 0; j < advancedTarget; j++) {
          matched.add(ti + j);
          if (!exact) approximate.add(ti + j);
        }
      }
      ti += advancedTarget;
    }

    final missedCount = targetWords.length - matched.length;
    // Enough words present AND not too many flawed ones (missing +
    // approximately said, counted together).
    final isCorrect = missedCount <= allowedMissing(targetWords.length) &&
        missedCount + approximate.length <= maxFlawedWords(targetWords.length);

    return PhraseMatchResult(
      isCorrect: isCorrect,
      matchedCount: matched.length,
      totalCount: targetWords.length,
      matchedTargetIndexes: matched,
      missedWords: [
        for (var i = 0; i < targetWords.length; i++)
          if (!matched.contains(i)) targetWords[i],
      ],
      approximateWords: [for (final i in approximate) targetWords[i]],
      approximateIndexes: approximate,
    );
  }

  /// Joins what was heard in earlier listening segments with the current
  /// one, so a student who pauses mid-phrase still gets judged on the whole
  /// phrase ("the sky" + "is blue").
  static String joinSegments(String committed, String current) {
    final a = committed.trim();
    final b = current.trim();
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    return '$a $b';
  }

  /// Whether [next] (the recognizer's latest text) starts a NEW utterance
  /// instead of continuing/revising [prev]. After a pause the engine can
  /// drop its old text and begin again ("the sky" -> "is"), and then
  /// "is" -> "blue": when that happens the old text must be kept or its
  /// words are lost. Erring towards "new" is harmless (repeated words are
  /// ignored by [match]); erring towards "same" loses words.
  static bool startsNewUtterance(String prev, String next) {
    final p = words(prev);
    final n = words(next);
    if (p.isEmpty || n.isEmpty) return false;
    if (n.length < p.length) return true;
    for (var i = 0; i < p.length; i++) {
      if (!wordsMatch(n[i], p[i])) return true;
    }
    return false;
  }

  /// Whether a single heard word is close enough to the expected one.
  static bool wordsMatch(String heard, String expected) {
    final a = normalizeWord(heard);
    final b = normalizeWord(expected);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    final longest = a.length > b.length ? a.length : b.length;
    var allowed = (longest * letterTolerance).floor();
    if (allowed < 1) allowed = 1;
    return _levenshtein(a, b) <= allowed;
  }

  /// Normalized word list for a phrase (contractions expanded, digits
  /// spelled out, punctuation dropped).
  static List<String> words(String text) {
    var t = text.toLowerCase().replaceAll('’', "'");
    _contractions.forEach((short, long) {
      t = t.replaceAll(RegExp("\\b${RegExp.escape(short)}\\b"), long);
    });
    t = t.replaceAll(RegExp(r"[^a-z0-9'\s]"), ' ').replaceAll("'", '');
    return t
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        // expand, not map: "100" spells out to two words.
        .expand((w) => (_numbers[w] ?? w).split(' '))
        .toList();
  }

  /// Single-word normalization (lowercase, letters/digits only, digits
  /// spelled out) — for comparing one word at a time.
  static String normalizeWord(String word) {
    final w = word.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return (_numbers[w] ?? w).replaceAll(' ', '');
  }

  static int _levenshtein(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        final del = prev[j] + 1;
        final ins = cur[j - 1] + 1;
        final sub = prev[j - 1] + cost;
        cur[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  // Applied before punctuation is stripped, so the apostrophe is still
  // there to match on.
  static const Map<String, String> _contractions = {
    "don't": 'do not',
    "doesn't": 'does not',
    "didn't": 'did not',
    "can't": 'can not',
    "cannot": 'can not',
    "won't": 'will not',
    "isn't": 'is not',
    "aren't": 'are not',
    "wasn't": 'was not',
    "weren't": 'were not',
    "i'm": 'i am',
    "you're": 'you are',
    "we're": 'we are',
    "they're": 'they are',
    "it's": 'it is',
    "he's": 'he is',
    "she's": 'she is',
    "that's": 'that is',
    "what's": 'what is',
    "let's": 'let us',
    "i'll": 'i will',
    "you'll": 'you will',
    "i've": 'i have',
    "i'd": 'i would',
  };

  static const Map<String, String> _numbers = {
    '0': 'zero', '1': 'one', '2': 'two', '3': 'three', '4': 'four',
    '5': 'five', '6': 'six', '7': 'seven', '8': 'eight', '9': 'nine',
    '10': 'ten', '11': 'eleven', '12': 'twelve', '13': 'thirteen',
    '14': 'fourteen', '15': 'fifteen', '16': 'sixteen',
    '17': 'seventeen', '18': 'eighteen', '19': 'nineteen', '20': 'twenty',
    '30': 'thirty', '40': 'forty', '50': 'fifty', '60': 'sixty',
    '70': 'seventy', '80': 'eighty', '90': 'ninety', '100': 'one hundred',
  };
}
