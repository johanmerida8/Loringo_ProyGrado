import 'package:flutter/material.dart';

/// Renders [text] word by word, optionally masking each word behind
/// dashes until the student reveals it.
///
/// USAGE CHANGE (repeat_after_me redesign): previously this widget only
/// had one job — show the phrase and highlight words the student had
/// already said. Now it has two states:
///
/// - [isRevealed] == false: every word is masked as a dash placeholder
///   (Duolingo-style "_ _____ _____."), EXCEPT words that are already
///   present in [wordsToHighlight] — those are shown in full, in
///   [highlightStyle]. This is what makes the "guess as you speak"
///   mechanic work: the student never sees the answer up front, but as
///   speech_to_text recognizes each word correctly, it "un-masks" in
///   place instead of staying a dash. That's real-time feedback without
///   ever revealing the full sentence.
/// - [isRevealed] == true: normal behavior, full text shown, matched
///   words highlighted. This is the state after the student taps
///   "Reveal" or after result feedback is shown.
///
/// Dash length is derived from each word's own length so the mask gives
/// a rough sense of word length/rhythm (helps younger readers keep a
/// mental placeholder) without giving away letters.
class HighlightTextWidget extends StatelessWidget {
  final String text;
  final List<String> wordsToHighlight;
  final TextStyle normalStyle;
  final TextStyle highlightStyle;
  final TextAlign textAlign;

  /// When false, un-matched words render as dash placeholders instead
  /// of their real text. Defaults to true to preserve old behavior for
  /// any other screen still using this widget without opting in.
  final bool isRevealed;

  /// Style used for the dash placeholders. Falls back to [normalStyle]
  /// if not provided.
  final TextStyle? maskedStyle;

  const HighlightTextWidget({
    super.key,
    required this.text,
    required this.wordsToHighlight,
    required this.normalStyle,
    required this.highlightStyle,
    this.textAlign = TextAlign.center,
    this.isRevealed = true,
    this.maskedStyle,
  });

  /// Builds a dash placeholder proportional to word length, stripping
  /// trailing punctuation first so e.g. "please." becomes "_____." with
  /// the period preserved (helps the sentence still read as a sentence).
  String _maskFor(String word) {
    final match = RegExp(r'^([\w]*)(\W*)$').firstMatch(word);
    final core = match?.group(1) ?? word;
    final trailingPunct = match?.group(2) ?? '';
    if (core.isEmpty) return word; // pure punctuation token, leave as-is
    return '${'_' * core.length}$trailingPunct';
  }

  @override
  Widget build(BuildContext context) {
    final List<TextSpan> spans = [];
    final words = text.split(' ');
    final effectiveMaskedStyle = maskedStyle ?? normalStyle;

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final isMatched = wordsToHighlight.contains(word);

      final String displayText;
      final TextStyle style;

      if (isRevealed) {
        displayText = word;
        style = isMatched ? highlightStyle : normalStyle;
      } else if (isMatched) {
        // Recognized correctly even though the phrase is still hidden —
        // un-mask this specific word as positive feedback.
        displayText = word;
        style = highlightStyle;
      } else {
        displayText = _maskFor(word);
        style = effectiveMaskedStyle;
      }

      spans.add(TextSpan(text: displayText, style: style));

      if (i < words.length - 1) {
        spans.add(TextSpan(text: ' ', style: normalStyle));
      }
    }

    return RichText(
      textAlign: textAlign,
      text: TextSpan(children: spans),
    );
  }
}