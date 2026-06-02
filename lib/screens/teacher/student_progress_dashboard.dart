import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ───────────────────────────────── Models ─────────────────────────────────

class _UnitInfo {
  final String contentId;
  final String unitId;
  final String unitTitle;
  final List<String> activityIds;

  const _UnitInfo({
    required this.contentId,
    required this.unitId,
    required this.unitTitle,
    required this.activityIds,
  });
}

class _UnitRawData {
  int completedCount = 0;
  int scoreSum = 0;
  int starsEarned = 0;
}

class _RawProgress {
  final int xp;
  final Map<String, _UnitRawData> byUnit;
  _RawProgress({required this.xp, required this.byUnit});
}

class _StudentStats {
  final String studentId;
  final String name;
  final String avatar;
  final int xp;
  final int completedActivities;
  final int totalActivities;
  final int starsEarned;
  final int avgScore;

  const _StudentStats({
    required this.studentId,
    required this.name,
    required this.avatar,
    required this.xp,
    required this.completedActivities,
    required this.totalActivities,
    required this.starsEarned,
    required this.avgScore,
  });

  double get percent =>
      totalActivities == 0 ? 0.0 : completedActivities / totalActivities;
}

// ───────────────────────────── Dashboard Screen ───────────────────────────

class StudentProgressDashboard extends StatefulWidget {
  final String groupId;
  final String groupName;
  final List<Map<String, dynamic>> students;
  final bool showAppBar;

  const StudentProgressDashboard({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.students,
    this.showAppBar = true,
  });

  @override
  State<StudentProgressDashboard> createState() =>
      _StudentProgressDashboardState();
}

class _StudentProgressDashboardState
    extends State<StudentProgressDashboard> {
  static const _green = Color(0xFF4CAF50);
  static const _greenLight = Color(0xFF81C784);

  bool _loading = true;
  String? _error;

  List<_UnitInfo> _units = [];
  _UnitInfo? _selectedUnit;
  Map<String, _RawProgress> _rawProgress = {};
  List<_StudentStats> _stats = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ── Data loading — fully parallelised ────────────────────────────────
  // All Firestore calls at the same level are fired simultaneously with
  // Future.wait, reducing wall-clock time from O(N*M) to O(depth).

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = FirebaseFirestore.instance;

      // ── Step 1: content docs ──────────────────────────────────────────
      final contentSnap = await db
          .collection('content')
          .where('assignedTo', arrayContains: widget.groupId)
          .where('status', isEqualTo: 'approved')
          .get();

      // ── Step 2: all units for every content doc — parallel ────────────
      final allUnitResults = await Future.wait(
        contentSnap.docs.map((contentDoc) async {
          final contentId = contentDoc.id;

          final unitsSnap = await db
              .collection('content')
              .doc(contentId)
              .collection('units')
              .orderBy('order')
              .get();

          // ── Step 3: lessons for every unit — parallel ─────────────────
          final unitInfoList = await Future.wait(
            unitsSnap.docs.map((unitDoc) async {
              final unitId = unitDoc.id;
              final unitTitle =
                  (unitDoc.data()['title'] as String?) ?? 'Unit';

              final lessonsSnap = await db
                  .collection('content')
                  .doc(contentId)
                  .collection('units')
                  .doc(unitId)
                  .collection('lessons')
                  .get();

              // ── Step 4: activities for every lesson — parallel ─────────
              final activitySnaps = await Future.wait(
                lessonsSnap.docs.map((lessonDoc) => db
                    .collection('content')
                    .doc(contentId)
                    .collection('units')
                    .doc(unitId)
                    .collection('lessons')
                    .doc(lessonDoc.id)
                    .collection('activities')
                    .get()),
              );

              final activityIds = activitySnaps
                  .expand((snap) => snap.docs.map((d) => d.id))
                  .toList();

              return _UnitInfo(
                contentId: contentId,
                unitId: unitId,
                unitTitle: unitTitle,
                activityIds: activityIds,
              );
            }),
          );

          return unitInfoList;
        }),
      );

      final units = allUnitResults.expand((list) => list).toList();

      // ── Step 5: XP + progress for every student — parallel ────────────
      final rawProgress = <String, _RawProgress>{};

      await Future.wait(widget.students.map((student) async {
        final studentId = student['id'] as String;

        // Fetch student doc and progress subcollection simultaneously
        final results = await Future.wait([
          db.collection('students').doc(studentId).get(),
          db
              .collection('students')
              .doc(studentId)
              .collection('progress')
              .get(),
        ]);

        final studentDoc = results[0] as DocumentSnapshot;
        final progressSnap = results[1] as QuerySnapshot;

        final xp =
            (studentDoc.data() as Map<String, dynamic>?)?['xp'] as int? ?? 0;

        final byUnit = <String, _UnitRawData>{};

        for (final doc in progressSnap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final unitId = (data['unitId'] as String?) ?? '';
          if (unitId.isEmpty) continue;

          byUnit.putIfAbsent(unitId, _UnitRawData.new);

          if (data.containsKey('activityId') &&
              data['isCompleted'] == true) {
            byUnit[unitId]!.completedCount++;
            byUnit[unitId]!.scoreSum +=
                (data['bestScore'] as int?) ?? 0;
          } else if (data.containsKey('quizId') &&
              data['isCompleted'] == true) {
            byUnit[unitId]!.starsEarned +=
                (data['stars'] as int?) ?? 0;
          }
        }

        rawProgress[studentId] = _RawProgress(xp: xp, byUnit: byUnit);
      }));

      // Reset selected unit if it no longer exists in the new data
      if (_selectedUnit != null &&
          !units.any((u) => u.unitId == _selectedUnit!.unitId)) {
        _selectedUnit = null;
      }

      _units = units;
      _rawProgress = rawProgress;
      _buildStats();

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── Stats computation (pure, no async) ───────────────────────────────
  void _buildStats() {
    final targetUnits =
        _selectedUnit != null ? [_selectedUnit!] : _units;

    final stats = widget.students.map((s) {
      final studentId = s['id'] as String;
      final raw = _rawProgress[studentId];

      int completedActivities = 0;
      int totalActivities = 0;
      int starsEarned = 0;
      int scoreSum = 0;
      int activitiesWithScore = 0;

      for (final unit in targetUnits) {
        totalActivities += unit.activityIds.length;
        if (raw != null && raw.byUnit.containsKey(unit.unitId)) {
          final u = raw.byUnit[unit.unitId]!;
          completedActivities += u.completedCount;
          starsEarned += u.starsEarned;
          if (u.completedCount > 0) {
            scoreSum += u.scoreSum;
            activitiesWithScore += u.completedCount;
          }
        }
      }

      final avgScore = activitiesWithScore == 0
          ? 0
          : (scoreSum / activitiesWithScore).round();

      return _StudentStats(
        studentId: studentId,
        name: s['name'] as String,
        avatar: s['avatar'] as String,
        xp: raw?.xp ?? 0,
        completedActivities: completedActivities,
        totalActivities: totalActivities,
        starsEarned: starsEarned,
        avgScore: avgScore,
      );
    }).toList()
      ..sort((a, b) {
        final pct = b.percent.compareTo(a.percent);
        if (pct != 0) return pct;
        return b.xp.compareTo(a.xp);
      });

    setState(() => _stats = stats);
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: _green,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Progress Dashboard',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    widget.groupName,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded,
                      color: Colors.white),
                  onPressed: _loadData,
                  tooltip: 'Refresh',
                ),
              ],
            )
          : null,
      body: _loading
          ? _buildLoading()
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: _green),
          SizedBox(height: 16),
          Text(
            'Loading progress data...',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Could not load progress data',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (widget.students.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline_rounded,
                size: 72, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No students in this group yet',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildUnitSelector(),
        _buildSummaryCard(),
        Expanded(child: _buildStudentList()),
      ],
    );
  }

  // ── Unit selector chips ───────────────────────────────────────────────

  Widget _buildUnitSelector() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FILTER BY UNIT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey[500],
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _unitChip(null, 'All Units'),
                ...List.generate(
                  _units.length,
                  (i) => _unitChip(_units[i], _units[i].unitTitle),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _unitChip(_UnitInfo? unit, String label) {
    final isSelected = _selectedUnit?.unitId == unit?.unitId;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          _selectedUnit = unit;
          _buildStats();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? _green : Colors.grey[100],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? _green : Colors.grey[300]!,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey[700],
              fontWeight:
                  isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  // ── Summary card ──────────────────────────────────────────────────────

  Widget _buildSummaryCard() {
    if (_stats.isEmpty) return const SizedBox.shrink();

    final avgPercent =
        _stats.map((s) => s.percent).reduce((a, b) => a + b) /
            _stats.length;

    final totalActivities = _selectedUnit != null
        ? _selectedUnit!.activityIds.length
        : _units.fold(0, (sum, u) => sum + u.activityIds.length);

    final unitLabel = _selectedUnit?.unitTitle ?? 'All Units';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_green, _greenLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _green.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(
                unitLabel,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              // Manual refresh button — useful since data is cached
              GestureDetector(
                onTap: _loadData,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded,
                          color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text('Refresh',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.people_rounded,
                  label: 'Students',
                  value: '${_stats.length}',
                ),
              ),
              _verticalDivider(),
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.trending_up_rounded,
                  label: 'Avg Progress',
                  value: '${(avgPercent * 100).round()}%',
                ),
              ),
              _verticalDivider(),
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.assignment_turned_in_rounded,
                  label: 'Activities',
                  value: '$totalActivities',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider() => Container(
        width: 1,
        height: 48,
        color: Colors.white.withOpacity(0.3),
      );

  // ── Student list ──────────────────────────────────────────────────────

  Widget _buildStudentList() {
    if (_stats.isEmpty) {
      return Center(
        child: Text(
          'No progress data available yet',
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _stats.length,
      itemBuilder: (context, index) {
        return _StudentProgressCard(
          stats: _stats[index],
          rank: index + 1,
        );
      },
    );
  }
}

// ─────────────────────────── Sub-widgets ──────────────────────────────────

class _SummaryMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}

class _StudentProgressCard extends StatelessWidget {
  final _StudentStats stats;
  final int rank;

  const _StudentProgressCard({
    required this.stats,
    required this.rank,
  });

  Color get _barColor {
    final pct = stats.percent;
    if (pct >= 0.9) return const Color(0xFF4CAF50);
    if (pct >= 0.6) return const Color(0xFF8BC34A);
    if (pct >= 0.3) return const Color(0xFFFFC107);
    return const Color(0xFFFF7043);
  }

  Widget _rankWidget() {
    switch (rank) {
      case 1:
        return const Text('🥇', style: TextStyle(fontSize: 24));
      case 2:
        return const Text('🥈', style: TextStyle(fontSize: 24));
      case 3:
        return const Text('🥉', style: TextStyle(fontSize: 24));
      default:
        return Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$rank',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final percentInt = (stats.percent * 100).round();
    final avatar = stats.avatar;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: rank · avatar · name · XP badge
            Row(
              children: [
                _rankWidget(),
                const SizedBox(width: 10),
                CircleAvatar(
                  radius: 22,
                  backgroundColor:
                      const Color(0xFF4CAF50).withOpacity(0.15),
                  backgroundImage:
                      avatar.isNotEmpty ? AssetImage(avatar) : null,
                  child: avatar.isEmpty
                      ? Text(
                          stats.name.isNotEmpty
                              ? stats.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Color(0xFF4CAF50),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    stats.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // XP badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFFFCA28), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt_rounded,
                          size: 14, color: Color(0xFFFFCA28)),
                      const SizedBox(width: 2),
                      Text(
                        '${stats.xp} XP',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF795548),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Progress bar
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: stats.percent,
                      minHeight: 10,
                      backgroundColor: Colors.grey[200],
                      valueColor:
                          AlwaysStoppedAnimation<Color>(_barColor),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 40,
                  child: Text(
                    '$percentInt%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _barColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Stats chips
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _statChip(
                  icon: Icons.check_circle_rounded,
                  label:
                      '${stats.completedActivities}/${stats.totalActivities} activities',
                  color: const Color(0xFF4CAF50),
                ),
                if (stats.starsEarned > 0)
                  _statChip(
                    icon: Icons.star_rounded,
                    label: '${stats.starsEarned} stars',
                    color: const Color(0xFFFFCA28),
                  ),
                if (stats.avgScore > 0)
                  _statChip(
                    icon: Icons.analytics_rounded,
                    label: 'Avg ${stats.avgScore}%',
                    color: Colors.blueAccent,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}