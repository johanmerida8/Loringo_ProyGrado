import 'package:flutter/material.dart';

class HighlightTextWidget extends StatelessWidget {
  final String text;
  final List<String> wordsToHighlight;
  final TextStyle normalStyle;
  final TextStyle highlightStyle;
  final TextAlign textAlign;

  const HighlightTextWidget({
    super.key,
    required this.text,
    required this.wordsToHighlight,
    required this.normalStyle,
    required this.highlightStyle,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    final List<TextSpan> spans = [];
    final words = text.split(' ');
    
    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final isHighlighted = wordsToHighlight.contains(word);
      
      spans.add(
        TextSpan(
          text: word,
          style: isHighlighted ? highlightStyle : normalStyle,
        ),
      );
      
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