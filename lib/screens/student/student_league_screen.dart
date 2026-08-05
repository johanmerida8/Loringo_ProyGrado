import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/models/league_tier.dart';
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
      final myDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.studentId)
          .get();
      if (!myDoc.exists) return;

      final myXp = ((myDoc.data()?['xp'] as num?) ?? 0).toInt();
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
      if (!campaignDoc.exists) {
        if (mounted) setState(_clearCampaign);
        return;
      }

      final campaign = campaignDoc.data() as Map<String, dynamic>;
      final scope = (campaign['scope'] as String?) ?? 'all';
      final campaignGroupId = campaign['groupId'] as String?;

      // A 'single'-scope campaign only ever applies to the one group it
      // targets — a student in any other group of the same teacher isn't
      // part of this competition at all, so nothing about it (dates,
      // prize list, winner check) is shown to them.
      if (scope == 'single' && campaignGroupId != gid) {
        if (mounted) setState(_clearCampaign);
        return;
      }

      final rewardsMap = (campaign['rewards'] as Map<String, dynamic>?) ?? {};
      final startDate = (campaign['startDate'] as Timestamp?)?.toDate();
      final endDate   = (campaign['endDate'] as Timestamp?)?.toDate();

      // Winner check only makes sense for an unlocked tier — Starter never
      // has a prize to win regardless of the campaign, so there's nothing
      // to compute here, but the period/prize list above still applies.
      var isWinner = false;
      var reward   = '';
      if (!isLocked) {
        // Which groups feed the ranking: just this one for 'single', every
        // group belonging to the same teacher for 'all' — mirrors
        // _RankingTab._loadStudents on the teacher side of
        // teacher_league_screen.dart.
        List<String> groupIds;
        if (scope == 'single') {
          groupIds = [gid];
        } else {
          final teacherGroupsSnap = await FirebaseFirestore.instance
              .collection('teacherGroups')
              .where('teacherId', isEqualTo: teacherId)
              .get();
          groupIds = teacherGroupsSnap.docs.map((d) => d.id).toList();
        }

        final studentsSnap = await FirebaseFirestore.instance
            .collection('students')
            .where('groupId', whereIn: groupIds)
            .get();

        final sameLeague = studentsSnap.docs
            .where((d) {
              final xp = ((d.data()['xp'] as num?) ?? 0).toInt();
              return xp >= tierMin && xp < tierMax;
            })
            .toList()
          ..sort((a, b) {
            final ax = ((a.data()['xp'] as num?) ?? 0).toInt();
            final bx = ((b.data()['xp'] as num?) ?? 0).toInt();
            return bx.compareTo(ax);
          });

        isWinner = sameLeague.isNotEmpty &&
            sameLeague.first.id == widget.studentId;
        reward = isWinner ? ((rewardsMap[tierKey] as String?) ?? '') : '';
      }

      if (mounted) {
        setState(() {
          _isLeagueWinner = isWinner && reward.isNotEmpty;
          _leagueReward = reward;
          _campaignApplies = true;
          _campaignStartDate = startDate;
          _campaignEndDate = endDate;
          _campaignRewards = rewardsMap.map(
              (key, value) => MapEntry(key, (value as String?) ?? ''));
        });
      }
    } catch (e) {
      debugPrint('Error loading league status: $e');
    }
  }

  void _clearCampaign() {
    _leagueReward = '';
    _isLeagueWinner = false;
    _campaignApplies = false;
    _campaignStartDate = null;
    _campaignEndDate = null;
    _campaignRewards = {};
  }

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE8F5E9), Colors.white],
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('students')
              .doc(widget.studentId)
              .snapshots(),
          builder: (context, studentSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('students')
                  .doc(widget.studentId)
                  .collection('progress')
                  .snapshots(),
              builder: (context, progressSnap) {
                final int totalXP = studentSnap.hasData && studentSnap.data!.exists
                    ? (((studentSnap.data!.data() as Map<String, dynamic>)['xp'])
                            as num? ??
                        0)
                        .toInt()
                    : 0;

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

                final leagueData = tierForXp(totalXP);
                final String leagueName = leagueData['name'] as String;
                final int leagueMin = leagueData['min'] as int;
                final int leagueMax = leagueData['max'] as int;
                final Color leagueColor = leagueData['color'] as Color;
                final String? leagueImage = leagueData['image'] as String?;
                final double progress = leagueMax > leagueMin
                    ? ((totalXP - leagueMin) / (leagueMax - leagueMin))
                        .clamp(0.0, 1.0)
                    : 1.0;

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLeagueHeader(leagueName, leagueColor, leagueImage),

                      if (_campaignApplies &&
                          (_campaignStartDate != null || _campaignEndDate != null)) ...[
                        const SizedBox(height: 16),
                        _buildRewardsPeriodBanner(),
                      ],

                      if (_isLeagueWinner && _leagueReward.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        WinnerBanner(
                          leagueName: leagueName,
                          reward: _leagueReward,
                          color: leagueColor,
                        ),
                      ],

                      const SizedBox(height: 32),
                      _buildXpCard(totalXP, leagueName, leagueColor, leagueMin, leagueMax, progress),
                      const SizedBox(height: 20),
                      _buildStatsRow(activitiesCompleted, quizzesCompleted),
                      const SizedBox(height: 28),
                      _buildLeagueTiersList(leagueName),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildLeagueHeader(String leagueName, Color leagueColor, String? leagueImage) {
    return Center(
      child: Column(
        children: [
          Container(
            width: 108, height: 108,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: leagueColor.withOpacity(0.35),
                  blurRadius: 20, offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [leagueColor, leagueColor.withOpacity(0.6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: leagueImage != null
                  ? Image.asset(leagueImage,
                      width: 64, height: 64, fit: BoxFit.contain)
                  : Icon(Icons.shield_rounded,
                      size: 52, color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          Text(leagueName,
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold,
                  color: leagueColor)),
          const SizedBox(height: 4),
          Text(widget.studentName,
              style: const TextStyle(
                  fontSize: 15, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildRewardsPeriodBanner() {
    final now = DateTime.now();
    final isFinished = _campaignEndDate != null && _campaignEndDate!.isBefore(now);
    final color = isFinished ? Colors.grey.shade500 : const Color(0xFF4CAF50);

    final String title;
    final String subtitle;
    if (isFinished) {
      title = 'Rewards finished';
      subtitle = _formatDate(_campaignEndDate!);
    } else if (_campaignEndDate != null) {
      title = 'Rewards active';
      subtitle = 'Until ${_formatDate(_campaignEndDate!)}';
    } else {
      title = 'Rewards active';
      subtitle = 'Since ${_formatDate(_campaignStartDate!)}';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10, offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
                color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(
                isFinished ? Icons.event_busy_rounded : Icons.emoji_events_rounded,
                size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold, color: color)),
                Text(subtitle,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildXpCard(int totalXP, String leagueName, Color leagueColor, int leagueMin, int leagueMax, double progress) {
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
              const Text('Total XP',
                  style: TextStyle(
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
              Text('$totalXP',
                  style: TextStyle(
                      fontSize: 48, fontWeight: FontWeight.bold,
                      color: leagueColor, height: 1)),
              const Padding(
                padding: EdgeInsets.only(bottom: 8, left: 6),
                child: Text('XP',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w600,
                        color: Colors.grey)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$leagueMin XP',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.grey)),
              Text(
                leagueMax == 999999 ? 'Max League' : '$leagueMax XP',
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
            Text('${leagueMax - totalXP} XP to next league',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey[600])),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsRow(int activitiesCompleted, int quizzesCompleted) {
    return Row(
      children: [
        Expanded(child: LeagueStatCard(
            icon: Icons.star_rounded,
            label: 'Activities',
            value: '$activitiesCompleted',
            color: const Color(0xFF4CAF50))),
        const SizedBox(width: 12),
        Expanded(child: LeagueStatCard(
            icon: Icons.quiz_rounded,
            label: 'Quizzes',
            value: '$quizzesCompleted',
            color: const Color(0xFF7C3AED))),
        const SizedBox(width: 12),
        Expanded(child: LeagueStatCard(
            icon: Icons.bolt_rounded,
            label: 'Total',
            value: '${activitiesCompleted + quizzesCompleted}',
            color: const Color(0xFFFF9800))),
      ],
    );
  }

  Widget _buildLeagueTiersList(String currentLeagueName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('League Tiers',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold,
                color: Colors.black87)),
        const SizedBox(height: 12),
        ...kLeagueTiers.map((tier) {
          final bool isCurrent = tier['name'] == currentLeagueName;
          final bool isLocked  = tier['rewardLocked'] as bool;
          final String reward  =
              isLocked ? '' : (_campaignRewards[tier['key']] ?? '');
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isCurrent
                  ? (tier['color'] as Color).withOpacity(0.12)
                  : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: isCurrent
                  ? Border.all(
                      color: (tier['color'] as Color)
                          .withOpacity(0.5),
                      width: 2)
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
                      ? Image.asset(tier['image'] as String,
                          fit: BoxFit.contain)
                      : Icon(Icons.shield_rounded,
                          color: tier['color'] as Color,
                          size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tier['name'] as String,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: isCurrent
                                  ? tier['color'] as Color
                                  : Colors.black87)),
                      Text(tier['range'] as String,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      if (reward.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (tier['color'] as Color).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.card_giftcard_rounded,
                                  size: 12, color: tier['color'] as Color),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(reward,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: tier['color'] as Color)),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: tier['color'] as Color,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('YOU',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

}