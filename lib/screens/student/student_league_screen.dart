import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/league_ranking_row.dart';
import 'package:loringo_app/models/league_tier.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/student/widgets/league_stat_card.dart';
import 'package:loringo_app/screens/student/widgets/winner_banner.dart';


class StudentLeagueTab extends StatefulWidget {
  final String studentId;
  final String studentName;

  const StudentLeagueTab({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<StudentLeagueTab> createState() => _StudentLeagueTabState();
}

class _StudentLeagueTabState extends State<StudentLeagueTab> {
  String? groupId;
  String _leagueReward = '';
  bool _isLeagueWinner = false;

  // The teacher's league campaign (leagueCampaigns/{teacherId}) — kept
  // separate from the winner-only fields above, since the reward period
  // and the full prize list are shown regardless of whether this student
  // happens to be winning their tier right now.
  Map<String, String> _campaignRewards = {};
  DateTime? _campaignStartDate;
  DateTime? _campaignEndDate;
  bool _campaignApplies = false;

  // Leaderboard: every student sharing this student's current tier,
  // scoped the same way the reward campaign decides who competes with
  // whom (single group vs. every group this teacher has) — falls back to
  // just this student's own group when no campaign applies to them, so
  // "who am I competing against" always shows something.
  List<LeagueStudentEntry> _tierLeaderboard = [];
  Map<String, Map<String, dynamic>> _groupInfo = {};
  bool _showGroupBadge = false;

  @override
  void initState() {
    super.initState();
    _loadStudentGroup();
  }

  Future<void> _loadStudentGroup() async {
    try {
      final studentDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.studentId)
          .get();

      if (studentDoc.exists) {
        final studentData = studentDoc.data();
        final fetchedGroupId = studentData?['groupId'] as String?;

        if (fetchedGroupId != null) {
          setState(() {
            groupId = fetchedGroupId;
          });
          await _loadLeagueStatus(fetchedGroupId);
        }
      }
    } catch (e) {
      debugPrint('Error loading student group: $e');
    }
  }

  Future<void> _loadLeagueStatus(String gid) async {
    try {
      final myRosterDoc = await FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(gid)
          .collection('students')
          .doc(widget.studentId)
          .get();
      if (!myRosterDoc.exists) return;

      // League tier is driven by seasonXp (resets each campaign), not the
      // lifetime `xp` field — see resetLeagueSeasons.ts.
      final myXp = ((myRosterDoc.data()?['seasonXp'] as num?) ?? 0).toInt();
      final myTier = tierForXp(myXp);
      final tierKey = myTier['key'] as String;
      final tierMin = myTier['min'] as int;
      final tierMax = myTier['max'] as int;
      final isLocked = myTier['rewardLocked'] as bool;

      // Rewards live per-teacher now (leagueCampaigns/{teacherId}), not
      // per-group — find this student's teacher first via their own
      // group doc.
      final groupDoc = await FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(gid)
          .get();
      final teacherId = groupDoc.data()?['teacherId'] as String?;
      if (teacherId == null) return;

      final campaignDoc = await FirebaseFirestore.instance
          .collection('leagueCampaigns')
          .doc(teacherId)
          .get();

      // Whether a real reward campaign applies to this student — decides
      // the reward/duration info AND which groups feed the leaderboard.
      // A 'single'-scope campaign targeting a different group doesn't
      // apply at all (nothing about it is shown), but the leaderboard
      // still falls back to just this student's own group below, so
      // "who am I competing against" always shows something even with
      // no campaign configured yet.
      var applies = false;
      var scope = 'single';
      var groupIds = [gid];

      if (campaignDoc.exists) {
        final campaign = campaignDoc.data() as Map<String, dynamic>;
        final campaignScope = (campaign['scope'] as String?) ?? 'all';
        final campaignGroupId = campaign['groupId'] as String?;

        if (!(campaignScope == 'single' && campaignGroupId != gid)) {
          applies = true;
          scope = campaignScope;
          if (scope == 'all') {
            final teacherGroupsSnap = await FirebaseFirestore.instance
                .collection('teacherGroups')
                .where('teacherId', isEqualTo: teacherId)
                .get();
            groupIds = teacherGroupsSnap.docs.map((d) => d.id).toList();
          }
        }
      }

      // Group name/color for the leaderboard's group badge — only ever
      // shown when scope == 'all' (competing across several groups).
      final groupDocsSnap = await Future.wait([
        for (final id in groupIds)
          FirebaseFirestore.instance.collection('teacherGroups').doc(id).get(),
      ]);
      final groupInfo = {
        for (final doc in groupDocsSnap)
          if (doc.exists)
            doc.id: {
              'name': (doc.data() as Map<String, dynamic>)['name'] ?? '',
              'color': _parseHex(
                  (doc.data() as Map<String, dynamic>)['color'] ?? '#4CAF50'),
            }
      };

      // Names/groupId come from the root students collection; xp lives on
      // each group's own roster doc — same split saveActivityCompletion
      // writes to. Mirrors _RankingTab._loadStudents on the teacher side
      // of teacher_league_screen.dart.
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('students')
            .where('groupId', whereIn: groupIds)
            .get(),
        for (final id in groupIds)
          FirebaseFirestore.instance
              .collection('teacherGroups')
              .doc(id)
              .collection('students')
              .where('status', isEqualTo: 'active')
              .get(),
      ]);
      final studentsSnap = results.first;
      final xpByStudentId = <String, int>{};
      for (final rosterSnap in results.skip(1)) {
        for (final doc in rosterSnap.docs) {
          final d = doc.data() as Map<String, dynamic>;
          xpByStudentId[doc.id] = ((d['seasonXp'] as num?) ?? 0).toInt();
        }
      }
      final allStudents = studentsSnap.docs.map((doc) {
        final d = doc.data();
        return LeagueStudentEntry(
          id: doc.id,
          name: (d['names'] as String?) ?? (d['name'] as String?) ?? 'Student',
          xp: xpByStudentId[doc.id] ?? 0,
          groupId: (d['groupId'] as String?) ?? '',
        );
      }).toList();

      final tierEntries = allStudents
          .where((s) => s.xp >= tierMin && s.xp < tierMax)
          .toList()
        ..sort((a, b) => b.xp.compareTo(a.xp));

      // Winner check only makes sense for an unlocked tier — Starter never
      // has a prize to win regardless of the campaign.
      var isWinner = false;
      var reward = '';
      var rewardsMap = <String, String>{};
      DateTime? startDate;
      DateTime? endDate;

      if (applies) {
        final campaign = campaignDoc.data() as Map<String, dynamic>;
        final rawRewards = (campaign['rewards'] as Map<String, dynamic>?) ?? {};
        rewardsMap = rawRewards.map(
            (key, value) => MapEntry(key, (value as String?) ?? ''));
        startDate = (campaign['startDate'] as Timestamp?)?.toDate();
        endDate = (campaign['endDate'] as Timestamp?)?.toDate();

        if (!isLocked) {
          isWinner = tierEntries.isNotEmpty &&
              tierEntries.first.id == widget.studentId;
          reward = isWinner ? (rewardsMap[tierKey] ?? '') : '';
        }
      }

      if (mounted) {
        setState(() {
          _isLeagueWinner = isWinner && reward.isNotEmpty;
          _leagueReward = reward;
          _campaignApplies = applies;
          _campaignStartDate = startDate;
          _campaignEndDate = endDate;
          _campaignRewards = rewardsMap;
          _tierLeaderboard = tierEntries;
          _groupInfo = groupInfo;
          _showGroupBadge = scope == 'all';
        });
      }
    } catch (e) {
      debugPrint('Error loading league status: $e');
    }
  }

  static Color _parseHex(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return const Color(0xFF4CAF50);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE8F5E9), Colors.white],
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: groupId == null
            ? const Center(child: CircularProgressIndicator())
            : StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('teacherGroups')
              .doc(groupId)
              .collection('students')
              .doc(widget.studentId)
              .snapshots(),
          builder: (context, studentSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('teacherGroups')
                  .doc(groupId)
                  .collection('students')
                  .doc(widget.studentId)
                  .collection('progress')
                  .snapshots(),
              builder: (context, progressSnap) {
                // Total XP is lifetime — only ever grows, feeds just the
                // Total XP stat card. League tier/progress below is driven
                // by seasonXp instead, which resets each campaign (see
                // resetLeagueSeasons.ts) — the two are deliberately
                // different numbers doing different jobs.
                final Map<String, dynamic>? rosterData =
                    studentSnap.hasData && studentSnap.data!.exists
                        ? studentSnap.data!.data() as Map<String, dynamic>
                        : null;
                final int totalXP =
                    ((rosterData?['xp'] as num?) ?? 0).toInt();
                final int seasonXp =
                    ((rosterData?['seasonXp'] as num?) ?? 0).toInt();

                int activitiesCompleted = 0;
                int quizzesCompleted = 0;
                if (progressSnap.hasData) {
                  for (final doc in progressSnap.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (data['isCompleted'] == true) {
                      if (data['type'] == 'activity') activitiesCompleted++;
                      else if (data['type'] == 'quiz') quizzesCompleted++;
                    }
                  }
                }

                final leagueData = tierForXp(seasonXp);
                final String leagueKey = leagueData['key'] as String;
                final String leagueName = tierLabel(leagueKey);
                final int leagueMin = leagueData['min'] as int;
                final int leagueMax = leagueData['max'] as int;
                final Color leagueColor = leagueData['color'] as Color;
                final String? leagueImage = leagueData['image'] as String?;
                final bool isLocked = leagueData['rewardLocked'] as bool;
                final double progress = leagueMax > leagueMin
                    ? ((seasonXp - leagueMin) / (leagueMax - leagueMin))
                        .clamp(0.0, 1.0)
                    : 1.0;
                final String tierReward = _campaignRewards[leagueKey] ?? '';

                return RefreshIndicator(
                  onRefresh: () => _loadLeagueStatus(groupId!),
                  child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Stats icon + league chip (tap for every league's
                      // prizes) + days-left chip, all on one row so the
                      // leaderboard below stays reachable without
                      // scrolling even with more members in it.
                      Row(
                        children: [
                          _StatsIconButton(
                            onTap: () => _showStatsSheet(
                              context, seasonXp, totalXP, leagueName, leagueColor,
                              leagueMin, leagueMax, progress,
                              activitiesCompleted, quizzesCompleted,
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => _showLeagueInfoSheet(context, leagueKey),
                            child: _buildLeagueChip(leagueName, leagueColor, leagueImage),
                          ),
                          const Spacer(),
                          _buildDaysChip(),
                        ],
                      ),

                      // 🏆 Who am I competing against
                      const SizedBox(height: 16),
                      _buildLeaderboard(leagueColor),

                      // 🎁 What do I win
                      if (_campaignApplies && !isLocked && tierReward.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildRewardCard(leagueColor, tierReward),
                      ],
                      if (_isLeagueWinner && _leagueReward.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        WinnerBanner(
                          leagueName: leagueName,
                          reward: _leagueReward,
                          color: leagueColor,
                        ),
                      ],
                    ],
                  ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Compact league badge (icon + name) — replaces the old hero-sized
  /// circular graphic so the header takes one line instead of most of a
  /// screen, keeping the leaderboard below reachable without scrolling.
  Widget _buildLeagueChip(String leagueName, Color leagueColor, String? leagueImage) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: leagueColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: leagueColor.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18, height: 18,
            child: leagueImage != null
                ? Image.asset(leagueImage, fit: BoxFit.contain)
                : Icon(Icons.shield_rounded, size: 16, color: leagueColor),
          ),
          const SizedBox(width: 6),
          Text(leagueName,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, color: leagueColor)),
        ],
      ),
    );
  }

  /// Compact "days left" chip — replaces the old full-width rewards
  /// banner. Empty when no campaign applies or it has no dates set,
  /// matching the old banner's visibility rule.
  Widget _buildDaysChip() {
    if (!_campaignApplies ||
        (_campaignStartDate == null && _campaignEndDate == null)) {
      return const SizedBox.shrink();
    }
    final now = DateTime.now();
    final isFinished = _campaignEndDate != null && _campaignEndDate!.isBefore(now);
    final color = isFinished ? Colors.grey.shade500 : const Color(0xFF4CAF50);

    final String label;
    if (isFinished) {
      label = 'student.student_league_screen.rewardsFinished'.tr();
    } else if (_campaignEndDate != null) {
      final days = _campaignEndDate!.difference(now).inDays;
      label = 'student.student_league_screen.daysLeft'
          .tr(namedArgs: {'days': '$days'});
    } else {
      label = 'student.student_league_screen.rewardsActive'.tr();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isFinished ? Icons.event_busy_rounded : Icons.timer_outlined,
              size: 13, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  /// Opens the total-XP/progress and activities/quizzes/total cards in a
  /// bottom sheet, triggered by the top-left stats icon.
  void _showStatsSheet(
    BuildContext context,
    int seasonXp,
    int totalXP,
    String leagueName,
    Color leagueColor,
    int leagueMin,
    int leagueMax,
    double progress,
    int activitiesCompleted,
    int quizzesCompleted,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        decoration: const BoxDecoration(
          color: Color(0xFFF3F8F3),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            _buildXpCard(seasonXp, totalXP, leagueName, leagueColor,
                leagueMin, leagueMax, progress),
            const SizedBox(height: 16),
            _buildStatsRow(activitiesCompleted, quizzesCompleted),
          ],
        ),
      ),
    );
  }

  /// Opens every league tier with its prize, triggered by tapping the
  /// league chip — brings back what used to be an always-visible tier
  /// ladder, now on demand so it doesn't compete with the leaderboard for
  /// screen space.
  void _showLeagueInfoSheet(BuildContext context, String currentLeagueKey) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: Color(0xFFF3F8F3),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('common.leagueTiers'.tr(),
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold,
                    color: Colors.black87)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final tier in kLeagueTiers)
                    _LeagueTierRow(
                      tier: tier,
                      isCurrent: tier['key'] == currentLeagueKey,
                      reward: (tier['rewardLocked'] as bool)
                          ? ''
                          : (_campaignRewards[tier['key']] ?? ''),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildXpCard(int seasonXp, int totalXP, String leagueName, Color leagueColor, int leagueMin, int leagueMax, double progress) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 12, offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('common.seasonXp'.tr(),
                  style: const TextStyle(
                      fontSize: 14, color: Colors.grey,
                      fontWeight: FontWeight.w600)),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: leagueColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(leagueName,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: leagueColor)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$seasonXp',
                  style: TextStyle(
                      fontSize: 48, fontWeight: FontWeight.bold,
                      color: leagueColor, height: 1)),
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 6),
                child: Text('common.xp'.tr(),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w600,
                        color: Colors.grey)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  'student.student_league_screen.xpValue'
                      .tr(namedArgs: {'value': '$leagueMin'}),
                  style: const TextStyle(
                      fontSize: 11, color: Colors.grey)),
              Text(
                leagueMax == 999999
                    ? 'common.maxLeague'.tr()
                    : 'student.student_league_screen.xpValue'
                        .tr(namedArgs: {'value': '$leagueMax'}),
                style: const TextStyle(
                    fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(leagueColor),
            ),
          ),
          if (leagueMax < 999999) ...[
            const SizedBox(height: 8),
            Text('${leagueMax - seasonXp} ${'common.nextLeague'.tr()}',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey[600])),
          ],
          const SizedBox(height: 14),
          Divider(color: Colors.grey[200], height: 1),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('common.totalXp'.tr(),
                  style: const TextStyle(fontSize: 13, color: Colors.grey)),
              Text('$totalXP ${'common.xp'.tr()}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(int activitiesCompleted, int quizzesCompleted) {
    return Row(
      children: [
        Expanded(child: LeagueStatCard(
            icon: Icons.star_rounded,
            label: 'common.activities'.tr(),
            value: '$activitiesCompleted',
            color: const Color(0xFF4CAF50))),
        const SizedBox(width: 12),
        Expanded(child: LeagueStatCard(
            icon: Icons.quiz_rounded,
            label: 'common.quizzes'.tr(),
            value: '$quizzesCompleted',
            color: const Color(0xFF7C3AED))),
        const SizedBox(width: 12),
        Expanded(child: LeagueStatCard(
            icon: Icons.bolt_rounded,
            label: 'common.total'.tr(),
            value: '${activitiesCompleted + quizzesCompleted}',
            color: const Color(0xFFFF9800))),
      ],
    );
  }

  /// "Who am I competing against?" — every student sharing the current
  /// tier, scoped to just this student's group or every group this
  /// teacher has (see _loadLeagueStatus / _showGroupBadge). The league
  /// chip above this list already identifies the tier, so this only
  /// renders the rows themselves.
  Widget _buildLeaderboard(Color leagueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_tierLeaderboard.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text('student.student_league_screen.noOneElseYet'.tr(),
                  style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ),
          )
        else
          ..._tierLeaderboard.asMap().entries.map((e) {
            final pos = e.key + 1;
            final entry = e.value;
            final info = _groupInfo[entry.groupId];
            final isWinner = pos == 1 &&
                _isLeagueWinner &&
                entry.id == widget.studentId;
            return LeagueRankingRow(
              position: pos,
              studentName: entry.name,
              xp: entry.xp,
              groupName: (info?['name'] as String?) ?? '',
              groupColor: (info?['color'] as Color?) ?? leagueColor,
              tierColor: leagueColor,
              isWinner: isWinner,
              isMe: entry.id == widget.studentId,
              showGroupBadge: _showGroupBadge,
            );
          }),
      ],
    );
  }

  /// "What do I win?" — the current tier's configured prize, shown
  /// whenever a campaign applies to this student regardless of whether
  /// they're currently in first place (that celebratory state is
  /// WinnerBanner, shown separately).
  Widget _buildRewardCard(Color leagueColor, String reward) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: leagueColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: leagueColor.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
                color: leagueColor.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(Icons.card_giftcard_rounded,
                size: 18, color: leagueColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('student.student_league_screen.whatDoIWin'.tr(),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: leagueColor)),
                Text(reward,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Top-left stats icon that opens the XP/progress + activities/quizzes
/// sheet — kept as its own tiny widget just for the tap-affordance circle.
class _StatsIconButton extends StatelessWidget {
  final VoidCallback onTap;

  const _StatsIconButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: Colors.black26,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.bar_chart_rounded, size: 22, color: Colors.black54),
        ),
      ),
    );
  }
}

/// One row in the league-info sheet: a tier's icon, name, XP range, and
/// prize (if any) — "you" tag on whichever tier the student is currently
/// in.
class _LeagueTierRow extends StatelessWidget {
  final Map<String, dynamic> tier;
  final bool isCurrent;
  final String reward;

  const _LeagueTierRow({
    required this.tier,
    required this.isCurrent,
    required this.reward,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = tier['color'] as Color;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isCurrent ? color.withOpacity(0.12) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isCurrent
            ? Border.all(color: color.withOpacity(0.5), width: 2)
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36, height: 36,
            child: (tier['image'] as String?) != null
                ? Image.asset(tier['image'] as String, fit: BoxFit.contain)
                : Icon(Icons.shield_rounded, color: color, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tierLabel(tier['key'] as String),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isCurrent ? color : Colors.black87)),
                Text(tier['range'] as String,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                if (reward.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.card_giftcard_rounded, size: 12, color: color),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(reward,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: color)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isCurrent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('common.you'.tr(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }
}