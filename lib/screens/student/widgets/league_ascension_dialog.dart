// lib/screens/student/widgets/league_ascension_dialog.dart
//
// Celebratory pop-up shown when a student's league tier goes up — plays
// assets/sound/celebration.mp3 and shows the new tier's badge from
// assets/leagues/. Triggered from student_activities_screen.dart right
// after returning from an activity/quiz, by comparing the student's tier
// (derived from seasonXp — see models/league_tier.dart) before and after.

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/services/audio/feedback_sound_service.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// Plays the celebration sound and shows the ascension card. Fire this
/// after confirming (by comparing tierForXp before/after) that the
/// student's tier actually went up — this function itself doesn't check.
Future<void> showLeagueAscensionDialog(
  BuildContext context, {
  required String leagueName,
  required String? leagueImage,
  required Color leagueColor,
}) {
  FeedbackSoundService.instance.playAsset(
    'assets/sound/level-up.mp3',
    volume: 0.6,
  );
  return showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black54,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: _LeagueAscensionCard(
        leagueName: leagueName,
        leagueImage: leagueImage,
        leagueColor: leagueColor,
      ),
    ),
  );
}

class _LeagueAscensionCard extends StatelessWidget {
  final String leagueName;
  final String? leagueImage;
  final Color leagueColor;

  const _LeagueAscensionCard({
    required this.leagueName,
    required this.leagueImage,
    required this.leagueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
              color: leagueColor.withOpacity(0.35),
              blurRadius: 24,
              offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96, height: 96,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [leagueColor, leagueColor.withOpacity(0.6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: leagueImage != null
                ? Image.asset(leagueImage!, fit: BoxFit.contain)
                : Icon(Icons.shield_rounded, size: 56, color: Colors.white),
          ),
          const SizedBox(height: 20),
          Text('student.student_activities_screen.newLeagueTitle'.tr(),
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold,
                  color: leagueColor)),
          const SizedBox(height: 8),
          Text(
            'student.student_activities_screen.newLeagueMessage'
                .tr(namedArgs: {'league': leagueName}),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: Colors.black87),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: leagueColor,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('common.continue'.tr(),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
