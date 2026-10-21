import 'package:flutter/material.dart';
import 'package:loringo_app/models/feedback_tag.dart';

/// Read-only display of a teacher's feedback tag (emoji + label in the
/// tag's color). Renders nothing for a null/unknown key, so callers can
/// pass `report['feedbackTag']` straight through for older reports too.
class FeedbackTagChip extends StatelessWidget {
  const FeedbackTagChip({super.key, required this.tagKey});

  final String? tagKey;

  @override
  Widget build(BuildContext context) {
    final tag = feedbackTagFor(tagKey);
    if (tag == null) return const SizedBox.shrink();
    final color = tag['color'] as Color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '${tag['emoji']} ${feedbackTagLabel(tag['key'] as String)}',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
