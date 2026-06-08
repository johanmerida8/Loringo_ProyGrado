// teacher_league_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/theme/app_theme.dart';

// ── League tiers ─────────────────────────────────────────────────────────────

const List<Map<String, dynamic>> kLeagueTiers = [
  {
    'key':          'starter',
    'name':         'Starter',
    'range':        '0 – 199 XP',
    'min':          0,
    'max':          200,
    'color':        Color(0xFF9E9E9E),
    'image':        null,
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
    'rewardLocked': true,
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

Map<String, dynamic> tierForXp(int xp) {
  for (final t in kLeagueTiers) {
    if (xp >= (t['min'] as int) && xp < (t['max'] as int)) return t;
  }
  return kLeagueTiers.last;
}

// ── Root ──────────────────────────────────────────────────────────────────────

class TeacherLeagueScreen extends StatefulWidget {
  const TeacherLeagueScreen({super.key});

  @override
  State<TeacherLeagueScreen> createState() => _TeacherLeagueScreenState();
}

class _TeacherLeagueScreenState extends State<TeacherLeagueScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.onPrimary),
        title: const Text('League & Ranking', style: AppText.appBarTitle),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.onPrimary,
          indicatorWeight: 3,
          labelColor: AppColors.onPrimary,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(icon: Icon(Icons.leaderboard_rounded), text: 'Ranking'),
            Tab(icon: Icon(Icons.card_giftcard_rounded), text: 'Rewards'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_RankingTab(), _RewardsTab()],
      ),
    );
  }
}

// ── Ranking Tab ───────────────────────────────────────────────────────────────

class _RankingTab extends StatefulWidget {
  const _RankingTab();

  @override
  State<_RankingTab> createState() => _RankingTabState();
}

class _RankingTabState extends State<_RankingTab> {
  int _selectedTierIndex = 0;

  static Color _parseHex(String hex) {
    try {
      return Color(
          int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('teacherGroups')
          .where('teacherId', isEqualTo: teacherId)
          .snapshots(),
      builder: (context, groupSnap) {
        if (groupSnap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (!groupSnap.hasData || groupSnap.data!.docs.isEmpty) {
          return const _LeagueEmptyState(
            icon: Icons.groups_rounded,
            message: 'No groups yet',
            hint: 'Create a group to see the ranking',
          );
        }

        final groups = {
          for (final doc in groupSnap.data!.docs)
            doc.id: {
              'name':  (doc.data() as Map<String, dynamic>)['name'] ?? '',
              'color': _parseHex(
                  (doc.data() as Map<String, dynamic>)['color'] ?? '#4CAF50'),
            }
        };

        return FutureBuilder<List<_StudentEntry>>(
          future: _loadStudents(groups.keys.toList()),
          builder: (context, studentSnap) {
            if (studentSnap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary));
            }

            final allStudents = studentSnap.data ?? [];
            final tier    = kLeagueTiers[_selectedTierIndex];
            final tierMin = tier['min'] as int;
            final tierMax = tier['max'] as int;

            final tierStudents = allStudents
                .where((s) => s.xp >= tierMin && s.xp < tierMax)
                .toList()
              ..sort((a, b) => b.xp.compareTo(a.xp));

            return Column(
              children: [
                _LeagueFilterBar(
                  selectedIndex: _selectedTierIndex,
                  onSelected: (i) => setState(() => _selectedTierIndex = i),
                ),
                Expanded(
                  child: tierStudents.isEmpty
                      ? _LeagueEmptyState(
                          icon: Icons.emoji_events_rounded,
                          message: 'No students in ${tier['name']}',
                          hint: 'Students reach this league by earning XP',
                        )
                      : FutureBuilder<String>(
                          future: _loadRewardForTier(
                            groupIds: groups.keys.toList(),
                            tierKey:  tier['key'] as String,
                          ),
                          builder: (context, rewardSnap) {
                            final reward = rewardSnap.data ?? '';
                            return ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.md, AppSpacing.sm,
                                  AppSpacing.md, AppSpacing.xl),
                              itemCount: tierStudents.length + 1,
                              itemBuilder: (context, index) {
                                if (index == 0) {
                                  return _LeagueHeaderCard(
                                      tier: tier, reward: reward);
                                }
                                final pos      = index;
                                final entry    = tierStudents[index - 1];
                                final info     = groups[entry.groupId];
                                final isWinner = pos == 1 &&
                                    !(tier['rewardLocked'] as bool) &&
                                    reward.isNotEmpty;
                                return _RankingRow(
                                  position:    pos,
                                  studentName: entry.name,
                                  xp:          entry.xp,
                                  groupName:   (info?['name']  as String?) ?? '',
                                  groupColor:  (info?['color'] as Color?)  ?? AppColors.primary,
                                  tierColor:   tier['color'] as Color,
                                  isWinner:    isWinner,
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<_StudentEntry>> _loadStudents(List<String> groupIds) async {
    if (groupIds.isEmpty) return [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('students')
          .where('groupId', whereIn: groupIds)
          .get();
      return snap.docs.map((doc) {
        final d = doc.data();
        return _StudentEntry(
          id:      doc.id,
          name:    (d['names'] as String?) ?? (d['name'] as String?) ?? 'Student',
          xp:      ((d['xp'] as num?) ?? 0).toInt(),
          groupId: (d['groupId'] as String?) ?? '',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<String> _loadRewardForTier({
    required List<String> groupIds,
    required String tierKey,
  }) async {
    for (final gid in groupIds) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('teacherGroups')
            .doc(gid)
            .collection('leagueRewards')
            .doc('config')
            .get();
        if (doc.exists) {
          final val = (doc.data() as Map<String, dynamic>)[tierKey] as String?;
          if (val != null && val.isNotEmpty) return val;
        }
      } catch (_) {}
    }
    return '';
  }
}

// ── League Filter Bar ─────────────────────────────────────────────────────────

class _LeagueFilterBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _LeagueFilterBar(
      {required this.selectedIndex, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: List.generate(kLeagueTiers.length, (i) {
            final tier       = kLeagueTiers[i];
            final isSelected = i == selectedIndex;
            final color      = tier['color'] as Color;
            final imagePath  = tier['image']  as String?;

            return GestureDetector(
              onTap: () => onSelected(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md - 2, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: isSelected ? color : color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(
                    color: isSelected ? color : color.withOpacity(0.3),
                    width: isSelected ? 2 : 1,
                  ),
                  boxShadow: isSelected
                      ? [BoxShadow(color: color.withOpacity(0.3),
                          blurRadius: 8, offset: const Offset(0, 3))]
                      : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 22, height: 22,
                      child: imagePath != null
                          ? Image.asset(imagePath, fit: BoxFit.contain)
                          : Icon(Icons.shield_outlined,
                              color: isSelected ? AppColors.onPrimary : color,
                              size: 18),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      tier['name'] as String,
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold,
                        color: isSelected ? AppColors.onPrimary : color,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ── League Header Card ────────────────────────────────────────────────────────

class _LeagueHeaderCard extends StatelessWidget {
  final Map<String, dynamic> tier;
  final String reward;

  const _LeagueHeaderCard({required this.tier, required this.reward});

  @override
  Widget build(BuildContext context) {
    final color     = tier['color'] as Color;
    final imagePath = tier['image'] as String?;
    final hasReward = reward.isNotEmpty && !(tier['rewardLocked'] as bool);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md, top: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.65)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: imagePath != null
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Image.asset(imagePath, fit: BoxFit.contain))
                : const Icon(Icons.shield_outlined,
                    color: AppColors.onPrimary, size: 30),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${tier['name']} League',
                    style: const TextStyle(
                      color: AppColors.onPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    )),
                const SizedBox(height: 4),
                Text(tier['range'] as String,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85), fontSize: 13)),
                if (hasReward) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm + 2, vertical: AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🏆', style: TextStyle(fontSize: 13)),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            '1st place: $reward',
                            style: const TextStyle(
                              color: AppColors.onPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Ranking Row ───────────────────────────────────────────────────────────────

class _RankingRow extends StatelessWidget {
  final int    position;
  final String studentName;
  final int    xp;
  final String groupName;
  final Color  groupColor;
  final Color  tierColor;
  final bool   isWinner;

  static const Color _gold = Color(0xFFFFB300);

  const _RankingRow({
    required this.position,
    required this.studentName,
    required this.xp,
    required this.groupName,
    required this.groupColor,
    required this.tierColor,
    required this.isWinner,
  });

  @override
  Widget build(BuildContext context) {
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
            : isTop
                ? tierColor.withOpacity(0.07)
                : Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md + 4),
        border: isWinner
            ? Border.all(color: _gold, width: 3)
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
                  if (isWinner) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 2),
                      decoration: BoxDecoration(
                          color: _gold,
                          borderRadius:
                              BorderRadius.circular(AppRadii.sm)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('🏆', style: TextStyle(fontSize: 10)),
                        SizedBox(width: 3),
                        Text('Winner',
                            style: TextStyle(
                              color: AppColors.onPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            )),
                      ]),
                    ),
                  ],
                ]),
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
              const Text('XP',
                  style: TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Rewards Tab ───────────────────────────────────────────────────────────────

class _RewardsTab extends StatefulWidget {
  const _RewardsTab();

  @override
  State<_RewardsTab> createState() => _RewardsTabState();
}

class _RewardsTabState extends State<_RewardsTab> {
  String? _selectedGroupId;
  String  _selectedGroupName = '';

  final Map<String, TextEditingController> _controllers = {
    for (final t in kLeagueTiers) t['key'] as String: TextEditingController(),
  };

  bool _isSaving         = false;
  bool _isLoadingRewards = false;

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _loadRewards(String groupId) async {
    setState(() => _isLoadingRewards = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(groupId)
          .collection('leagueRewards')
          .doc('config')
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        for (final key in _controllers.keys) {
          _controllers[key]!.text = (data[key] as String?) ?? '';
        }
      } else {
        for (final c in _controllers.values) c.clear();
      }
    } catch (e) {
      _showError('Could not load rewards: $e');
    } finally {
      if (mounted) setState(() => _isLoadingRewards = false);
    }
  }

  Future<void> _saveRewards() async {
    if (_selectedGroupId == null) return;
    setState(() => _isSaving = true);
    try {
      final data = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp()
      };
      for (final tier in kLeagueTiers) {
        final key    = tier['key']          as String;
        final locked = tier['rewardLocked'] as bool;
        data[key] = locked ? '' : _controllers[key]!.text.trim();
      }
      await FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(_selectedGroupId)
          .collection('leagueRewards')
          .doc('config')
          .set(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Rewards saved successfully'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md)),
        ));
      }
    } catch (e) {
      _showError('Could not save rewards: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.danger,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('teacherGroups')
          .where('teacherId', isEqualTo: teacherId)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const _LeagueEmptyState(
            icon: Icons.card_giftcard_rounded,
            message: 'No groups yet',
            hint: 'Create a group first to configure league rewards',
          );
        }

        final groupDocs = snap.data!.docs;

        if (_selectedGroupId == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final first = groupDocs.first;
            setState(() {
              _selectedGroupId   = first.id;
              _selectedGroupName =
                  (first.data() as Map<String, dynamic>)['name'] ?? '';
            });
            _loadRewards(first.id);
          });
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Multi-group selector
              if (groupDocs.length > 1) ...[
                Text('Select Group',
                    style: AppText.caption.copyWith(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: AppSpacing.sm),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: groupDocs.map((doc) {
                      final data       = doc.data() as Map<String, dynamic>;
                      final id         = doc.id;
                      final name       = (data['name'] as String?) ?? '';
                      final isSelected = _selectedGroupId == id;
                      Color chipColor;
                      try {
                        chipColor = Color(int.parse(
                          'FF${(data['color'] as String? ?? '#4CAF50').replaceAll('#', '')}',
                          radix: 16,
                        ));
                      } catch (_) {
                        chipColor = AppColors.primary;
                      }
                      return Padding(
                        padding:
                            const EdgeInsets.only(right: AppSpacing.sm),
                        child: GestureDetector(
                          onTap: () {
                            if (_selectedGroupId == id) return;
                            setState(() {
                              _selectedGroupId   = id;
                              _selectedGroupName = name;
                            });
                            _loadRewards(id);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? chipColor
                                  : chipColor.withOpacity(0.1),
                              borderRadius:
                                  BorderRadius.circular(AppRadii.pill),
                              border: Border.all(
                                color: isSelected
                                    ? chipColor
                                    : chipColor.withOpacity(0.3),
                              ),
                            ),
                            child: Text(name,
                                style: TextStyle(
                                  color: isSelected
                                      ? AppColors.onPrimary
                                      : chipColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                )),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              // Info banner
              Container(
                padding: const EdgeInsets.all(AppSpacing.md - 2),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft(0.08),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.primarySoft(0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _selectedGroupId == null
                          ? 'Loading...'
                          : 'Rewards for $_selectedGroupName — '
                              '1st place of Silver and above wins the prize.',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: AppSpacing.lg),

              if (_isLoadingRewards)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else
                ...kLeagueTiers.map((tier) => _LeagueTierRewardField(
                      tier:       tier,
                      controller: _controllers[tier['key']]!,
                    )),

              const SizedBox(height: AppSpacing.lg),

              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton.icon(
                  onPressed:
                      (_isSaving || _selectedGroupId == null) ? null : _saveRewards,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.onPrimary))
                      : const Icon(Icons.save_rounded, color: AppColors.onPrimary),
                  label: Text(
                    _isSaving ? 'Saving...' : 'Save Rewards',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.onPrimary),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primarySoft(0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.md)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── League Tier Reward Field ──────────────────────────────────────────────────

class _LeagueTierRewardField extends StatelessWidget {
  final Map<String, dynamic>  tier;
  final TextEditingController controller;

  const _LeagueTierRewardField(
      {required this.tier, required this.controller});

  @override
  Widget build(BuildContext context) {
    final color        = tier['color']        as Color;
    final imagePath    = tier['image']        as String?;
    final isLocked     = tier['rewardLocked'] as bool;
    final displayColor = isLocked ? AppColors.muted : color;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md - 2),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isLocked ? Colors.grey[50] : Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isLocked ? 0.03 : 0.05),
            blurRadius: 8, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // League icon
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              color: displayColor.withOpacity(0.10),
              shape: BoxShape.circle,
              border: Border.all(color: displayColor.withOpacity(0.3), width: 1.5),
            ),
            child: imagePath != null
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: isLocked
                        ? ColorFiltered(
                            colorFilter: const ColorFilter.matrix(<double>[
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0, 0, 0, 1, 0,
                            ]),
                            child: Image.asset(imagePath, fit: BoxFit.contain),
                          )
                        : Image.asset(imagePath, fit: BoxFit.contain),
                  )
                : Icon(Icons.shield_outlined, color: displayColor, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),

          // Label
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tier['name'] as String,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: displayColor)),
            Text(tier['range'] as String, style: AppText.caption),
          ]),
          const SizedBox(width: AppSpacing.md),

          // Input or locked
          Expanded(
            child: isLocked
                ? Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(children: [
                      Icon(Icons.lock_outline_rounded,
                          size: 14, color: Colors.grey[400]),
                      const SizedBox(width: AppSpacing.xs),
                      Text('No reward',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[400])),
                    ]),
                  )
                : TextField(
                    controller: controller,
                    maxLength: 60,
                    decoration: InputDecoration(
                      hintText: 'e.g. A sticker 🌟',
                      hintStyle:
                          TextStyle(fontSize: 13, color: Colors.grey[400]),
                      counterText: '',
                      filled: true,
                      fillColor: AppColors.scaffoldBackground,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        borderSide: BorderSide(color: AppColors.divider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        borderSide: BorderSide(color: color, width: 1.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                        borderSide: BorderSide(color: AppColors.divider),
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _StudentEntry {
  final String id;
  final String name;
  final int    xp;
  final String groupId;

  const _StudentEntry({
    required this.id,
    required this.name,
    required this.xp,
    required this.groupId,
  });
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _LeagueEmptyState extends StatelessWidget {
  final IconData icon;
  final String   message;
  final String   hint;

  const _LeagueEmptyState({
    required this.icon,
    required this.message,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 72, color: AppColors.divider),
              const SizedBox(height: AppSpacing.md),
              Text(message,
                  style: AppText.subtitle.copyWith(
                      fontWeight: FontWeight.w600, fontSize: 17)),
              const SizedBox(height: AppSpacing.sm),
              Text(hint,
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(fontSize: 13)),
            ],
          ),
        ),
      );
}