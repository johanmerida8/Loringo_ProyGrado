import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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
      final myTier = _getTierForXp(myXp);
      final tierKey = myTier['key'] as String;
      final tierMin = myTier['min'] as int;
      final tierMax = myTier['max'] as int;
      final isLocked = myTier['rewardLocked'] as bool;

      if (isLocked) {
        if (mounted) setState(() {
          _leagueReward = '';
          _isLeagueWinner = false;
        });
        return;
      }

      final groupSnap = await FirebaseFirestore.instance
          .collection('students')
          .where('groupId', isEqualTo: gid)
          .get();

      final sameLeague = groupSnap.docs
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

      final isWinner = sameLeague.isNotEmpty &&
          sameLeague.first.id == widget.studentId;

      String reward = '';
      if (isWinner) {
        final rewardDoc = await FirebaseFirestore.instance
            .collection('teacherGroups')
            .doc(gid)
            .collection('leagueRewards')
            .doc('config')
            .get();
        if (rewardDoc.exists) {
          reward = (rewardDoc.data()?[tierKey] as String?) ?? '';
        }
      }

      if (mounted) {
        setState(() {
          _isLeagueWinner = isWinner && reward.isNotEmpty;
          _leagueReward = reward;
        });
      }
    } catch (e) {
      debugPrint('Error loading league status: $e');
    }
  }

  Map<String, dynamic> _getTierForXp(int xp) {
    for (final t in _leagueTiers()) {
      final min = t['min'] as int? ?? 0;
      final max = t['max'] as int? ?? 0;
      if (xp >= min && xp < max) return t;
    }
    return _leagueTiers().last;
  }

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
                      if (data.containsKey('activityId')) activitiesCompleted++;
                      else if (data.containsKey('quizId')) quizzesCompleted++;
                    }
                  }
                }

                final leagueData = _getLeagueLevel(totalXP);
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
            width: 100, height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [leagueColor, leagueColor.withOpacity(0.6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: leagueColor.withOpacity(0.35),
                  blurRadius: 20, offset: const Offset(0, 8),
                ),
              ],
            ),
            child: leagueImage != null
                ? Image.asset(leagueImage,
                    width: 64, height: 64, fit: BoxFit.contain)
                : Icon(Icons.shield_rounded,
                    size: 52, color: Colors.white),
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
        ..._leagueTiers().map((tier) {
          final bool isCurrent = tier['name'] == currentLeagueName;
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

  Map<String, dynamic> _getLeagueLevel(int xp) {
    for (final tier in _leagueTiers()) {
      final min = tier['min'] as int? ?? 0;
      final max = tier['max'] as int? ?? 0;
      if (xp >= min && xp < max) return tier;
    }
    return _leagueTiers().last;
  }

  List<Map<String, dynamic>> _leagueTiers() => [
    {'name': 'Starter',  'min': 0,    'max': 200,    'range': '0 – 199 XP',
    'color': const Color(0xFF9E9E9E), 'image': null, 'key': 'starter', 'rewardLocked': true},
    {'name': 'Bronze',   'min': 200,  'max': 500,    'range': '200 – 499 XP',
    'color': const Color(0xFFCD7F32), 'image': 'assets/leagues/bronze-league.png', 
    'key': 'bronze', 'rewardLocked': true},
    {'name': 'Silver',   'min': 500,  'max': 1000,   'range': '500 – 999 XP',
    'color': const Color(0xFF78909C), 'image': 'assets/leagues/silver-league.png',
    'key': 'silver', 'rewardLocked': false},
    {'name': 'Gold',     'min': 1000, 'max': 2000,   'range': '1000 – 1999 XP',
    'color': const Color(0xFFFFB300), 'image': 'assets/leagues/gold-league.png',
    'key': 'gold', 'rewardLocked': false},
    {'name': 'Platinum', 'min': 2000, 'max': 4000,   'range': '2000 – 3999 XP',
    'color': const Color(0xFF00BCD4), 'image': 'assets/leagues/platinum-league.png',
    'key': 'platinum', 'rewardLocked': false},
    {'name': 'Diamond',  'min': 4000, 'max': 999999, 'range': '4000+ XP',
    'color': const Color(0xFF1565C0), 'image': 'assets/leagues/diamond-league.png',
    'key': 'diamond', 'rewardLocked': false},
  ];
}