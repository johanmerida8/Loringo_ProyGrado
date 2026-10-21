import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// ── League tiers ─────────────────────────────────────────────────────────────
// Single source of truth for league tier thresholds/colors/reward-eligibility.
// Previously duplicated verbatim in teacher_league_screen.dart and
// student_league_screen.dart — any tier change (like unlocking Bronze here)
// used to require editing both files in lockstep. Both screens now import
// this instead.

const List<Map<String, dynamic>> kLeagueTiers = [
  {
    'key':          'starter',
    'name':         'Starter',
    'range':        '0 – 199 XP',
    'min':          0,
    'max':          200,
    'color':        Color(0xFF9E9E9E),
    'image':        null,
    // Starter is the tier everyone begins in — no real achievement yet to
    // reward, so it stays locked even though Bronze below no longer is.
    'rewardLocked': true,
  },
  {
    'key':          'bronze',
    'name':         'Bronze',
    'range':        '200 – 499 XP',
    'min':          200,
    'max':          500,
    'color':        Color(0xFFCD7F32),
    'image':        'assets/leagues/bronze-league.png',
    'rewardLocked': false,
  },
  {
    'key':          'silver',
    'name':         'Silver',
    'range':        '500 – 999 XP',
    'min':          500,
    'max':          1000,
    'color':        Color(0xFF78909C),
    'image':        'assets/leagues/silver-league.png',
    'rewardLocked': false,
  },
  {
    'key':          'gold',
    'name':         'Gold',
    'range':        '1000 – 1999 XP',
    'min':          1000,
    'max':          2000,
    'color':        Color(0xFFFFB300),
    'image':        'assets/leagues/gold-league.png',
    'rewardLocked': false,
  },
  {
    'key':          'platinum',
    'name':         'Platinum',
    'range':        '2000 – 3999 XP',
    'min':          2000,
    'max':          4000,
    'color':        Color(0xFF00BCD4),
    'image':        'assets/leagues/platinum-league.png',
    'rewardLocked': false,
  },
  {
    'key':          'diamond',
    'name':         'Diamond',
    'range':        '4000+ XP',
    'min':          4000,
    'max':          999999,
    'color':        Color(0xFF1565C0),
    'image':        'assets/leagues/diamond-league.png',
    'rewardLocked': false,
  },
];

// The 'name' field above stays the stable English key used across
// screens/collections; this maps it to the translated display label.
// Mirrors taskTypeLabel() in task_type_option.dart.
String tierLabel(String key) => 'common.leagueTierNames.$key'.tr();

Map<String, dynamic> tierForXp(int xp) {
  for (final t in kLeagueTiers) {
    if (xp >= (t['min'] as int) && xp < (t['max'] as int)) return t;
  }
  return kLeagueTiers.last;
}

// ── Shared leaderboard row data ─────────────────────────────────────────────
// Used by both teacher_league_screen.dart (all tiers, teacher-side ranking)
// and student_league_screen.dart (current tier only, student-facing
// leaderboard) so the two screens build the same shape from the same
// students+roster-xp query pattern.
class LeagueStudentEntry {
  final String id;
  final String name;
  final int    xp;
  final String groupId;

  const LeagueStudentEntry({
    required this.id,
    required this.name,
    required this.xp,
    required this.groupId,
  });
}
