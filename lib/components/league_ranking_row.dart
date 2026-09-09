import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/theme/app_theme.dart';

/// A single leaderboard row: medal/position, student name, optional group
/// badge, and XP. Shared by teacher_league_screen.dart (full ranking, every
/// tier) and student_league_screen.dart (current-tier-only leaderboard) so
/// both screens render identically.
class LeagueRankingRow extends StatelessWidget {
  final int    position;
  final String studentName;
  final int    xp;
  final String groupName;
  final Color  groupColor;
  final Color  tierColor;
  final bool   isWinner;

  /// Highlights this row (border/background) as the viewing student's own
  /// entry. Always false on the teacher side.
  final bool isMe;

  /// Hides the group badge — used by the student leaderboard when the
  /// league campaign is scoped to a single group, since every row would
  /// show the same group name.
  final bool showGroupBadge;

  static const Color _gold = Color(0xFFFFB300);

  const LeagueRankingRow({
    super.key,
    required this.position,
    required this.studentName,
    required this.xp,
    required this.groupName,
    required this.groupColor,
    required this.tierColor,
    required this.isWinner,
    this.isMe = false,
    this.showGroupBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final String posLabel = switch (position) {
      1 => '🥇', 2 => '🥈', 3 => '🥉', _ => '#$position',
    };
    final bool isTop = position <= 3;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.md - 4),
      decoration: BoxDecoration(
        color: isWinner
            ? const Color(0xFFFFFDE7)
            : isMe
                ? tierColor.withOpacity(0.1)
                : isTop
                    ? tierColor.withOpacity(0.07)
                    : Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md + 4),
        border: isWinner
            ? Border.all(color: _gold, width: 3)
            : isMe
                ? Border.all(color: tierColor, width: 2)
                : isTop
                    ? Border.all(color: tierColor.withOpacity(0.25), width: 1.5)
                    : null,
        boxShadow: isWinner
            ? [
                BoxShadow(
                    color: _gold.withOpacity(0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4)),
                BoxShadow(
                    color: _gold.withOpacity(0.12),
                    blurRadius: 4,
                    offset: const Offset(0, 1)),
              ]
            : [
                BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2)),
              ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(posLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isTop ? 24 : 14,
                  fontWeight: FontWeight.bold,
                  color: isTop ? null : Colors.grey[500],
                )),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(
                      studentName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isWinner ? _gold : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isMe && !isWinner) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 2),
                      decoration: BoxDecoration(
                          color: tierColor,
                          borderRadius:
                              BorderRadius.circular(AppRadii.sm)),
                      child: Text('common.you'.tr(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          )),
                    ),
                  ],
                  if (isWinner) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 2),
                      decoration: BoxDecoration(
                          color: _gold,
                          borderRadius:
                              BorderRadius.circular(AppRadii.sm)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Text('🏆', style: TextStyle(fontSize: 10)),
                        const SizedBox(width: 3),
                        Text('teacher.teacher_league_screen.winner'.tr(),
                            style: const TextStyle(
                              color: AppColors.onPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            )),
                      ]),
                    ),
                  ],
                ]),
                if (showGroupBadge) ...[
                  const SizedBox(height: 4),
                  IntrinsicWidth(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 2),
                      decoration: BoxDecoration(
                        color: groupColor.withOpacity(0.13),
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        border: Border.all(color: groupColor.withOpacity(0.35)),
                      ),
                      child: Text(groupName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: groupColor,
                          )),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // XP
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$xp',
                  style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold,
                    color: isWinner ? _gold : tierColor,
                  )),
              Text('common.xp'.tr(),
                  style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}
