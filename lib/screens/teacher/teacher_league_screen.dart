// teacher_league_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/league_ranking_row.dart';
import 'package:loringo_app/models/league_tier.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/teacher/widgets/teacher_screen_header.dart';
import 'package:loringo_app/services/database/database.dart';
import 'package:loringo_app/theme/app_theme.dart';

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
    context.watch<LocaleProvider>();
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          TeacherScreenHeader(
              title: 'teacher.teacher_league_screen.title'.tr()),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.mdAll,
              boxShadow: AppShadows.card,
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              dividerColor: Colors.transparent,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              tabs: [
                Tab(
                    icon: const Icon(Icons.leaderboard_rounded),
                    text: 'teacher.teacher_league_screen.rankingTab'.tr()),
                Tab(
                    icon: const Icon(Icons.card_giftcard_rounded),
                    text: 'teacher.teacher_league_screen.rewardsTab'.tr()),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [_RankingTab(), _RewardsTab()],
            ),
          ),
        ],
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
  final Database _db = Database();

  late final String _teacherId;
  late final Stream<QuerySnapshot> _groupsStream;
  late final Future<DocumentSnapshot> _campaignFuture;

  // Memoized by resolved group-id set: tapping a league tier chip only
  // changes _selectedTierIndex, which must never re-trigger a Firestore
  // read (that was causing the whole tab to flash back to a loading
  // spinner on every tap). Only re-fetches when the actual group scope
  // changes.
  Future<List<LeagueStudentEntry>>? _studentsFuture;
  String _studentsFutureKey = '';

  @override
  void initState() {
    super.initState();
    _teacherId = FirebaseAuth.instance.currentUser?.uid ?? '';
    _groupsStream = FirebaseFirestore.instance
        .collection('teacherGroups')
        .where('teacherId', isEqualTo: _teacherId)
        .snapshots();
    _campaignFuture = _db.getLeagueCampaign(_teacherId);
  }

  static Color _parseHex(String hex) {
    try {
      return Color(
          int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  Future<List<LeagueStudentEntry>> _studentsFor(List<String> groupIds) {
    final key = groupIds.join(',');
    if (_studentsFuture == null || _studentsFutureKey != key) {
      _studentsFutureKey = key;
      _studentsFuture = _loadStudents(groupIds);
    }
    return _studentsFuture!;
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return StreamBuilder<QuerySnapshot>(
      stream: _groupsStream,
      builder: (context, groupSnap) {
        if (groupSnap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (!groupSnap.hasData || groupSnap.data!.docs.isEmpty) {
          return _LeagueEmptyState(
            icon: Icons.groups_rounded,
            message: 'teacher.teacher_league_screen.noGroupsYet'.tr(),
            hint: 'teacher.teacher_league_screen.noGroupsRankingHint'.tr(),
          );
        }

        // Archived groups are hidden from the ranking, matching
        // teacher_home_screen.dart's "My Groups" filter — otherwise a
        // group's students keep showing up here indefinitely even after
        // the group itself is archived and no longer shown anywhere else.
        final groups = {
          for (final doc in groupSnap.data!.docs)
            if ((doc.data() as Map<String, dynamic>)['archived'] != true)
              doc.id: {
                'name':  (doc.data() as Map<String, dynamic>)['name'] ?? '',
                'color': _parseHex(
                    (doc.data() as Map<String, dynamic>)['color'] ?? '#4CAF50'),
              }
        };

        // The campaign decides which groups feed the ranking: 'single'
        // narrows it down to one specific group, 'all' (or no campaign
        // configured yet) keeps merging every group this teacher has,
        // same as the always-on behavior before this screen had a scope
        // setting at all.
        return FutureBuilder<DocumentSnapshot>(
          future: _campaignFuture,
          builder: (context, campaignSnap) {
            final campaign = campaignSnap.data?.exists == true
                ? campaignSnap.data!.data() as Map<String, dynamic>
                : null;
            final scope = (campaign?['scope'] as String?) ?? 'all';
            final campaignGroupId = campaign?['groupId'] as String?;
            final rewards =
                (campaign?['rewards'] as Map<String, dynamic>?) ?? const {};

            final activeGroupIds =
                (scope == 'single' && groups.containsKey(campaignGroupId))
                    ? [campaignGroupId!]
                    : groups.keys.toList();

            return FutureBuilder<List<LeagueStudentEntry>>(
              future: _studentsFor(activeGroupIds),
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

                final reward = (rewards[tier['key']] as String?) ?? '';

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
                              message: 'teacher.teacher_league_screen.noStudentsInTier'
                                  .tr(namedArgs: {
                                'tier': tierLabel(tier['key'] as String)
                              }),
                              hint: 'teacher.teacher_league_screen.noStudentsHint'.tr(),
                            )
                          : ListView.builder(
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
                                return LeagueRankingRow(
                                  position:    pos,
                                  studentName: entry.name,
                                  xp:          entry.xp,
                                  groupName:   (info?['name']  as String?) ?? '',
                                  groupColor:  (info?['color'] as Color?)  ?? AppColors.primary,
                                  tierColor:   tier['color'] as Color,
                                  isWinner:    isWinner,
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
      },
    );
  }

  Future<List<LeagueStudentEntry>> _loadStudents(List<String> groupIds) async {
    if (groupIds.isEmpty) return [];
    try {
      // Names/groupId still come from the root students collection, but
      // seasonXp now lives on each group's own roster doc — so it's
      // fetched separately, per group, and merged in below. The ranking
      // and league tier read seasonXp (resets each campaign), not the
      // lifetime `xp` field — see resetLeagueSeasons.ts.
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('students')
            .where('groupId', whereIn: groupIds)
            .get(),
        for (final groupId in groupIds)
          FirebaseFirestore.instance
              .collection('teacherGroups')
              .doc(groupId)
              .collection('students')
              .where('status', isEqualTo: 'active')
              .get(),
      ]);

      final studentsSnap = results.first as QuerySnapshot<Map<String, dynamic>>;
      final xpByStudentId = <String, int>{};
      for (final rosterSnap in results.skip(1)) {
        for (final doc in (rosterSnap as QuerySnapshot).docs) {
          final d = doc.data() as Map<String, dynamic>;
          xpByStudentId[doc.id] = ((d['seasonXp'] as num?) ?? 0).toInt();
        }
      }

      return studentsSnap.docs.map((doc) {
        final d = doc.data();
        return LeagueStudentEntry(
          id:      doc.id,
          name:    (d['names'] as String?) ?? (d['name'] as String?) ?? 'Student',
          xp:      xpByStudentId[doc.id] ?? 0,
          groupId: (d['groupId'] as String?) ?? '',
        );
      }).toList();
    } catch (_) {
      return [];
    }
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
    context.watch<LocaleProvider>();
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
                      tierLabel(tier['key'] as String),
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
    context.watch<LocaleProvider>();
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
                Text(
                    'teacher.teacher_league_screen.tierLeagueTitle'
                        .tr(namedArgs: {'tier': tierLabel(tier['key'] as String)}),
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
                            'teacher.teacher_league_screen.firstPlaceReward'
                                .tr(namedArgs: {'reward': reward}),
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

// ── Rewards Tab ───────────────────────────────────────────────────────────────

class _RewardsTab extends StatefulWidget {
  const _RewardsTab();

  @override
  State<_RewardsTab> createState() => _RewardsTabState();
}

class _RewardsTabState extends State<_RewardsTab> {
  final Database _db = Database();

  // 'single' = one specific group; 'all' = every group ("paralelos") this
  // teacher has — merged the same way _RankingTab already merges them.
  String _scope = 'all';
  String? _selectedGroupId;
  DateTime? _startDate;
  DateTime? _endDate;

  final Map<String, TextEditingController> _controllers = {
    for (final t in kLeagueTiers) t['key'] as String: TextEditingController(),
  };

  bool _isSaving  = false;
  bool _isLoading = true;

  // Snapshot of what's actually saved, taken once _loadCampaign finishes —
  // compared against the live form by _hasChanges so Save can tell
  // "nothing changed" apart from a real edit (same pattern as _hasChanges
  // in create_quiz_screen.dart).
  String _originalScope = 'all';
  String? _originalGroupId;
  DateTime? _originalStartDate;
  DateTime? _originalEndDate;
  Map<String, String> _originalRewards = {};

  // Whether a campaign currently exists in Firestore — drives the save
  // button's label (Create vs Update). resetLeagueSeasons.ts deletes the
  // campaign doc once its season ends, so this naturally goes back to
  // false then, with no separate teacher-facing delete action needed.
  bool _hasActiveCampaign = false;

  @override
  void initState() {
    super.initState();
    _loadCampaign();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _loadCampaign() async {
    final teacherId = FirebaseAuth.instance.currentUser?.uid;
    if (teacherId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final doc = await _db.getLeagueCampaign(teacherId);
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        _scope = (data['scope'] as String?) ?? 'all';
        _selectedGroupId = data['groupId'] as String?;
        _startDate = (data['startDate'] as Timestamp?)?.toDate();
        _endDate = (data['endDate'] as Timestamp?)?.toDate();
        final rewardsMap = (data['rewards'] as Map<String, dynamic>?) ?? {};
        for (final key in _controllers.keys) {
          _controllers[key]!.text = (rewardsMap[key] as String?) ?? '';
        }
      }
    } catch (e) {
      _showError('teacher.teacher_league_screen.couldNotLoadRewards'
          .tr(namedArgs: {'error': '$e'}));
    } finally {
      _originalScope = _scope;
      _originalGroupId = _selectedGroupId;
      _originalStartDate = _startDate;
      _originalEndDate = _endDate;
      _originalRewards = {
        for (final key in _controllers.keys) key: _controllers[key]!.text,
      };
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasActiveCampaign = _originalEndDate != null;
        });
      }
    }
  }

  bool _hasChanges() {
    if (_scope != _originalScope) return true;
    if (_scope == 'single' && _selectedGroupId != _originalGroupId) return true;
    if (_startDate != _originalStartDate) return true;
    if (_endDate != _originalEndDate) return true;
    for (final key in _controllers.keys) {
      if (_controllers[key]!.text.trim() != (_originalRewards[key] ?? '')) {
        return true;
      }
    }
    return false;
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _endDate) ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _saveRewards() async {
    final teacherId = FirebaseAuth.instance.currentUser?.uid;
    if (teacherId == null) return;

    if (_scope == 'single' && _selectedGroupId == null) {
      _showError('teacher.teacher_league_screen.selectGroupFirst'.tr(),
          color: AppColors.warning);
      return;
    }
    // A campaign now always drives a real season: seasonXp resets and
    // league standings promote/demote when it ends, so an open-ended
    // "lifetime" campaign with no end date no longer makes sense — see
    // resetLeagueSeasons.ts.
    if (_startDate == null || _endDate == null) {
      _showError('teacher.teacher_league_screen.durationRequired'.tr(),
          color: AppColors.warning);
      return;
    }
    if (_startDate != null && _endDate != null && _endDate!.isBefore(_startDate!)) {
      _showError('teacher.teacher_league_screen.endDateAfterStart'.tr(),
          color: AppColors.warning);
      return;
    }

    if (!_hasChanges()) {
      _showError('teacher.teacher_league_screen.noChangesMade'.tr(),
          color: AppColors.muted);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final rewards = {
        for (final tier in kLeagueTiers)
          (tier['key'] as String): (tier['rewardLocked'] as bool)
              ? ''
              : _controllers[tier['key']]!.text.trim(),
      };
      await _db.saveLeagueCampaign(
        teacherId: teacherId,
        scope: _scope,
        groupId: _scope == 'single' ? _selectedGroupId : null,
        startDate: _startDate,
        endDate: _endDate,
        rewards: rewards,
      );
      _originalScope = _scope;
      _originalGroupId = _selectedGroupId;
      _originalStartDate = _startDate;
      _originalEndDate = _endDate;
      _originalRewards = rewards;
      _hasActiveCampaign = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('teacher.teacher_league_screen.rewardsSavedSuccess'.tr()),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md)),
        ));
      }
    } catch (e) {
      _showError('teacher.teacher_league_screen.couldNotSaveRewards'
          .tr(namedArgs: {'error': '$e'}));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String msg, {Color color = AppColors.danger}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final teacherId = FirebaseAuth.instance.currentUser?.uid;

    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

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
          return _LeagueEmptyState(
            icon: Icons.card_giftcard_rounded,
            message: 'teacher.teacher_league_screen.noGroupsYet'.tr(),
            hint: 'teacher.teacher_league_screen.noGroupsRewardsHint'.tr(),
          );
        }

        // Archived groups aren't pickable targets — matches the Ranking
        // tab's filter above, so a teacher can't set "This group only" to
        // a group that's no longer active anywhere else.
        final groupDocs = snap.data!.docs
            .where((d) => (d.data() as Map<String, dynamic>)['archived'] != true)
            .toList();

        if (groupDocs.isEmpty) {
          return _LeagueEmptyState(
            icon: Icons.card_giftcard_rounded,
            message: 'teacher.teacher_league_screen.noGroupsYet'.tr(),
            hint: 'teacher.teacher_league_screen.noGroupsRewardsHint'.tr(),
          );
        }

        // If scope is 'single' but nothing (or a since-deleted group) is
        // selected yet, default to the first available group so the
        // dropdown never starts empty.
        if (_scope == 'single' &&
            (_selectedGroupId == null ||
                !groupDocs.any((d) => d.id == _selectedGroupId))) {
          _selectedGroupId = groupDocs.first.id;
        }

        final selectedGroupName = _selectedGroupId == null
            ? ''
            : (groupDocs
                    .firstWhere((d) => d.id == _selectedGroupId)
                    .data() as Map<String, dynamic>)['name'] as String? ??
                '';

        final now = DateTime.now();
        final hasDuration = _startDate != null || _endDate != null;
        final isFinished = _endDate != null && _endDate!.isBefore(now);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Scope: single group vs. all this teacher's groups ──────
              Text('teacher.teacher_league_screen.appliesTo'.tr(),
                  style: AppText.caption.copyWith(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: AppSpacing.sm),
              Row(children: [
                Expanded(
                  child: _ScopeChip(
                    label: 'teacher.teacher_league_screen.thisGroupOnly'.tr(),
                    selected: _scope == 'single',
                    onTap: () => setState(() => _scope = 'single'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _ScopeChip(
                    label: 'teacher.teacher_league_screen.allMyGroups'.tr(),
                    selected: _scope == 'all',
                    onTap: () => setState(() => _scope = 'all'),
                  ),
                ),
              ]),

              if (_scope == 'single') ...[
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  // Deliberately using `value` (not the newer
                  // `initialValue`): this field must reflect
                  // _selectedGroupId on every rebuild, including when the
                  // "default to first group" fallback above sets it
                  // outside of onChanged — `initialValue` only seeds the
                  // field once and would miss that.
                  value: _selectedGroupId,
                  items: groupDocs.map((doc) {
                    final name =
                        (doc.data() as Map<String, dynamic>)['name'] as String? ?? '';
                    return DropdownMenuItem(value: doc.id, child: Text(name));
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedGroupId = v),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.sm)),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),

              // ── Duration — required. Defines this campaign's season:
              // seasonXp resets and league standings promote/demote for
              // every student in scope once the end date passes (see
              // resetLeagueSeasons.ts). ──
              Text('teacher.teacher_league_screen.duration'.tr(),
                  style: AppText.caption.copyWith(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: AppSpacing.sm),
              Row(children: [
                Expanded(
                  child: _DateField(
                    label: 'teacher.teacher_league_screen.from'.tr(),
                    date: _startDate,
                    formatter: _formatDate,
                    onTap: () => _pickDate(isStart: true),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _DateField(
                    label: 'teacher.teacher_league_screen.until'.tr(),
                    date: _endDate,
                    formatter: _formatDate,
                    onTap: () => _pickDate(isStart: false),
                  ),
                ),
              ]),
              if (hasDuration) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md - 2, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: (isFinished ? AppColors.muted : AppColors.success)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Row(children: [
                    Icon(
                      isFinished
                          ? Icons.event_busy_rounded
                          : Icons.event_available_rounded,
                      size: 18,
                      color: isFinished ? AppColors.muted : AppColors.success,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      isFinished
                          ? 'teacher.teacher_league_screen.finishedOn'.tr(
                              namedArgs: {'date': _formatDate(_endDate!)})
                          : _endDate != null
                              ? 'teacher.teacher_league_screen.activeUntil'.tr(
                                  namedArgs: {'date': _formatDate(_endDate!)})
                              : 'teacher.teacher_league_screen.activeNoEndDate'
                                  .tr(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isFinished ? AppColors.muted : AppColors.success,
                      ),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),

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
                      _scope == 'single'
                          ? 'teacher.teacher_league_screen.infoSingleScope'.tr(
                              namedArgs: {
                                'group': selectedGroupName,
                                'tier': tierLabel('bronze'),
                              })
                          : 'teacher.teacher_league_screen.infoAllScope'.tr(
                              namedArgs: {'tier': tierLabel('bronze')}),
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

              ...kLeagueTiers.map((tier) => _LeagueTierRewardField(
                    tier:       tier,
                    controller: _controllers[tier['key']]!,
                  )),

              const SizedBox(height: AppSpacing.lg),

              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveRewards,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.onPrimary))
                      : const Icon(Icons.flag_rounded, color: AppColors.onPrimary),
                  label: Text(
                    _isSaving
                        ? 'teacher.teacher_league_screen.saving'.tr()
                        : (_hasActiveCampaign
                            ? 'teacher.teacher_league_screen.updateCampaign'
                            : 'teacher.teacher_league_screen.createCampaign')
                            .tr(),
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

// ── Scope chip (this group only / all my groups) ────────────────────────────

class _ScopeChip extends StatelessWidget {
  final String label;
  final bool   selected;
  final VoidCallback onTap;

  const _ScopeChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.primarySoft(0.08),
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.primarySoft(0.3),
          ),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? AppColors.onPrimary : AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            )),
      ),
    );
  }
}

// ── Date field (From / Until pickers) ────────────────────────────────────────

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final String Function(DateTime) formatter;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.date,
    required this.formatter,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(children: [
          const Icon(Icons.calendar_today_rounded,
              size: 16, color: AppColors.muted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              date != null ? formatter(date!) : label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: date != null ? FontWeight.w600 : FontWeight.normal,
                color: date != null ? Colors.black87 : AppColors.muted,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ),
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
    context.watch<LocaleProvider>();
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
            Text(tierLabel(tier['key'] as String),
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
                      Text('teacher.teacher_league_screen.noReward'.tr(),
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[400])),
                    ]),
                  )
                : TextField(
                    controller: controller,
                    maxLength: 60,
                    decoration: InputDecoration(
                      hintText: 'teacher.teacher_league_screen.rewardHint'.tr(),
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