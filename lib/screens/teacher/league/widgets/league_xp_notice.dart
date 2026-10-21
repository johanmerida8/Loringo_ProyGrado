import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/screens/teacher/league/teacher_league_screen.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// Shown under an XP field (activity / quiz forms). XP always adds to a
/// student's Total XP, but only counts toward the league (seasonXp) while
/// a campaign is running — see Database._isLeagueCampaignActiveForGroup.
/// Purely informational: it never blocks saving the form.
class LeagueXpNotice extends StatefulWidget {
  const LeagueXpNotice({super.key});

  @override
  State<LeagueXpNotice> createState() => _LeagueXpNoticeState();
}

class _LeagueXpNoticeState extends State<LeagueXpNotice> {
  final Database _db = Database();
  late Future<Map<String, dynamic>?> _campaignFuture;

  String get _teacherId => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _campaignFuture = _db.getActiveLeagueCampaign(_teacherId);
  }

  Future<void> _openRewards() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TeacherLeagueScreen(initialTab: 1)),
    );
    // The teacher may have just created a campaign — re-check.
    if (mounted) {
      setState(() => _campaignFuture = _db.getActiveLeagueCampaign(_teacherId));
    }
  }

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _campaignFuture,
      builder: (context, snap) {
        // Loading or failed: show nothing rather than a misleading notice.
        if (snap.connectionState != ConnectionState.done || snap.hasError) {
          return const SizedBox.shrink();
        }
        final campaign = snap.data;
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: campaign == null ? _noCampaign() : _active(campaign),
        );
      },
    );
  }

  Widget _active(Map<String, dynamic> campaign) {
    final end = (campaign['endDate'] as Timestamp?)?.toDate();
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.1),
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.emoji_events_rounded,
              size: 14, color: AppColors.success),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              end == null
                  ? 'teacher.league_xp_notice.active'.tr()
                  : 'teacher.league_xp_notice.activeUntil'
                      .tr(namedArgs: {'date': _formatDate(end)}),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _noCampaign() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.warning.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 18, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'teacher.league_xp_notice.noCampaign'.tr(),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'teacher.league_xp_notice.noCampaignHint'.tr(),
                  style: AppText.caption,
                ),
                const SizedBox(height: AppSpacing.xs),
                TextButton.icon(
                  onPressed: _openRewards,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.card_giftcard_rounded, size: 16),
                  label: Text('teacher.league_xp_notice.createCampaign'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
