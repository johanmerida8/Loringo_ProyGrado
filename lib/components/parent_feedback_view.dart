import 'package:flutter/material.dart';
import 'package:loringo_app/components/feedback_tag_chip.dart';
import 'package:loringo_app/models/feedback_tag.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// Read-only teacher feedback (tag chip + comment) for the parent's view
/// of the review screens (ActivityReviewScreen / LessonQuizReviewScreen /
/// UnitQuizReviewScreen with readOnly: true). Shows [emptyMessage] when
/// there's nothing the parent is allowed to see yet.
class ParentFeedbackView extends StatelessWidget {
  const ParentFeedbackView({
    super.key,
    required this.tagKey,
    required this.comment,
    required this.emptyMessage,
  });

  final String? tagKey;
  final String comment;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final hasTag = feedbackTagFor(tagKey) != null;
    final hasComment = comment.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primarySoft(0.2)),
      ),
      child: !hasTag && !hasComment
          ? Text(
              emptyMessage,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasTag) FeedbackTagChip(tagKey: tagKey),
                if (hasTag && hasComment) const SizedBox(height: 10),
                if (hasComment)
                  Text(
                    comment,
                    style: const TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
    );
  }
}
