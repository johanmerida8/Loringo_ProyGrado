import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// ── Feedback tags ────────────────────────────────────────────────────────────
// Quick one-tap ratings a teacher can attach to a student's activity,
// Lesson Quiz or Unit Quiz review (activity_review_screen.dart,
// lesson_quiz_review_screen.dart, unit_quiz_review_screen.dart), with the
// written comment now optional. Stored as the stable `key` in the
// `feedbackTag` field (progress doc / unit report doc) and translated at
// display time, so a wording change never touches stored data.
//
// Every label is phrased positively on purpose: the Unit Quiz tag is shown
// to parents in their report (child_report_detail_screen.dart and the PDF),
// so even the lowest level reads as "still growing", never "bad".

const List<Map<String, dynamic>> kFeedbackTags = [
  {'key': 'getting_started', 'emoji': '🌱', 'color': Color(0xFFEF6C00)},
  {'key': 'learning',        'emoji': '📚', 'color': Color(0xFFF9A825)},
  {'key': 'good_progress',   'emoji': '👍', 'color': Color(0xFF1E88E5)},
  {'key': 'great_work',      'emoji': '⭐', 'color': Color(0xFF43A047)},
  {'key': 'excellent',       'emoji': '🏆', 'color': Color(0xFF2E7D32)},
];

/// The tag entry for [key], or null for a missing/unknown key (older
/// reviews saved before tags existed have no `feedbackTag` at all).
Map<String, dynamic>? feedbackTagFor(String? key) {
  if (key == null || key.isEmpty) return null;
  for (final t in kFeedbackTags) {
    if (t['key'] == key) return t;
  }
  return null;
}

/// Localized label for a tag key, e.g. 'great_work' -> "¡Muy bien!".
String feedbackTagLabel(String key) => 'common.feedbackTags.$key'.tr();
