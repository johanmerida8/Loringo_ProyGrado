import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:loringo_app/models/teacher/student_progress.dart';
import 'package:loringo_app/screens/teacher/report_preview_screen.dart';
import 'package:loringo_app/screens/teacher/student_detail_progress_screen.dart';

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

  List<UnitInfo> _units = [];
  UnitInfo? _selectedUnit;
  Map<String, RawProgress> _rawProgress = {};
  List<StudentStats> _stats = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = FirebaseFirestore.instance;

      final contentSnap = await db
          .collection('content')
          .where('assignedTo', arrayContains: widget.groupId)
          .get();

      final allUnitResults = await Future.wait(
        contentSnap.docs.map((contentDoc) async {
          final contentId = contentDoc.id;
          final unitsSnap = await db
              .collection('content')
              .doc(contentId)
              .collection('units')
              .orderBy('order')
              .get();

          return await Future.wait(
            unitsSnap.docs.map((unitDoc) async {
              final unitId = unitDoc.id;
              final unitTitle = (unitDoc.data()['title'] as String?) ?? 'Unit';

              final lessonsSnap = await db
                  .collection('content')
                  .doc(contentId)
                  .collection('units')
                  .doc(unitId)
                  .collection('lessons')
                  .get();

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

              final lessonQuizzesSnap = await db
                  .collection('quizzes')
                  .where('type', isEqualTo: 'lesson')
                  .where('contentId', isEqualTo: contentId)
                  .where('unitId', isEqualTo: unitId)
                  .get();
              final lessonQuizIds = lessonQuizzesSnap.docs.map((d) => d.id).toList();

              final unitQuizzesSnap = await db
                  .collection('quizzes')
                  .where('type', isEqualTo: 'unit')
                  .where('contentId', isEqualTo: contentId)
                  .where('unitId', isEqualTo: unitId)
                  .limit(1)
                  .get();
              final unitQuizId = unitQuizzesSnap.docs.isNotEmpty
                  ? unitQuizzesSnap.docs.first.id
                  : null;

              return UnitInfo(
                contentId: contentId,
                unitId: unitId,
                unitTitle: unitTitle,
                activityIds: activityIds,
                lessonQuizIds: lessonQuizIds,
                unitQuizId: unitQuizId,
              );
            }),
          );
        }),
      );

      final units = allUnitResults.expand((list) => list).toList();

      final rawProgress = <String, RawProgress>{};

      await Future.wait(widget.students.map((student) async {
        final studentId = student['id'] as String;

        final results = await Future.wait([
          db.collection('students').doc(studentId).get(),
          db.collection('students').doc(studentId).collection('progress').get(),
        ]);

        final studentDoc = results[0] as DocumentSnapshot;
        final progressSnap = results[1] as QuerySnapshot;

        final xp = (studentDoc.data() as Map<String, dynamic>?)?['xp'] as int? ?? 0;
        final byUnit = <String, UnitRawData>{};
        final Map<String, Set<String>> completedActivityIdsPerUnit = {};

        for (final doc in progressSnap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final unitId = (data['unitId'] as String?) ?? '';
          if (unitId.isEmpty) continue;

          byUnit.putIfAbsent(unitId, () => UnitRawData());
          completedActivityIdsPerUnit.putIfAbsent(unitId, () => {});

          if (data.containsKey('activityId') && data['isCompleted'] == true) {
            final activityId = data['activityId'] as String;
            if (!completedActivityIdsPerUnit[unitId]!.contains(activityId)) {
              completedActivityIdsPerUnit[unitId]!.add(activityId);
              byUnit[unitId]!.completedActivities++;
              byUnit[unitId]!.activityScoreSum += (data['bestScore'] as int?) ?? 0;
            }
          }

          if (data.containsKey('quizId') && data['isCompleted'] == true) {
            final quizId = data['quizId'] as String;
            final score = (data['score'] as int?) ?? 0;
            final total = (data['totalQuestions'] as int?) ?? 0;

            if (quizId.startsWith('lesson_quiz_')) {
              byUnit[unitId]!.completedLessonQuizzes++;
              byUnit[unitId]!.lessonQuizScoreSum += (score / total * 100).round();
            } else if (quizId.startsWith('unit_quiz_')) {
              byUnit[unitId]!.unitQuizScore = score;
              byUnit[unitId]!.unitQuizTotal = total;
            }
          }
        }

        rawProgress[studentId] = RawProgress(xp: xp, byUnit: byUnit);
      }));

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

  void _buildStats() {
    final targetUnits = _selectedUnit != null ? [_selectedUnit!] : _units;

    final stats = widget.students.map((s) {
      final studentId = s['id'] as String;
      final raw = _rawProgress[studentId] ?? RawProgress.empty();

      int completedActivities = 0;
      int totalActivities = 0;
      int activityScoreSum = 0;
      int activitiesWithScore = 0;
      int completedLessonQuizzes = 0;
      int totalLessonQuizzes = 0;
      int lessonQuizScoreSum = 0;
      int? unitQuizScore;
      int? unitQuizTotal;

      for (final unit in targetUnits) {
        totalActivities += unit.totalActivities;
        totalLessonQuizzes += unit.totalLessonQuizzes;

        if (raw.byUnit.containsKey(unit.unitId)) {
          final u = raw.byUnit[unit.unitId]!;
          completedActivities += u.completedActivities;
          completedLessonQuizzes += u.completedLessonQuizzes;

          if (u.completedActivities > 0) {
            activityScoreSum += u.activityScoreSum;
            activitiesWithScore += u.completedActivities;
          }
          lessonQuizScoreSum += u.lessonQuizScoreSum;

          if (_selectedUnit != null) {
            unitQuizScore = u.unitQuizScore;
            unitQuizTotal = u.unitQuizTotal;
          }
        }
      }

      final avgActivityScore = activitiesWithScore == 0
          ? 0
          : (activityScoreSum / activitiesWithScore).round();
      final avgLessonQuizScore = completedLessonQuizzes == 0
          ? 0
          : (lessonQuizScoreSum / completedLessonQuizzes).round();
      final unitQuizPercent = (unitQuizTotal != null &&
              unitQuizTotal! > 0 &&
              unitQuizScore != null)
          ? (unitQuizScore! / unitQuizTotal! * 100).round()
          : 0;

      final overallScore = ((avgActivityScore * 0.4) +
              (avgLessonQuizScore * 0.3) +
              (unitQuizPercent * 0.3))
          .round();
      final overallStars =
          overallScore >= 90 ? 3 : (overallScore >= 70 ? 2 : 1);

      return StudentStats(
        studentId: studentId,
        name: s['name'] as String,
        avatar: s['avatar'] as String,
        xp: raw.xp,
        completedActivities: completedActivities,
        totalActivities: totalActivities,
        avgActivityScore: avgActivityScore,
        completedLessonQuizzes: completedLessonQuizzes,
        totalLessonQuizzes: totalLessonQuizzes,
        avgLessonQuizScore: avgLessonQuizScore,
        unitQuizScore: unitQuizScore,
        unitQuizTotal: unitQuizTotal,
        unitQuizPercent: unitQuizPercent,
        overallScore: overallScore,
        overallStars: overallStars,
      );
    }).toList()
      ..sort((a, b) => b.overallScore.compareTo(a.overallScore));

    setState(() => _stats = stats);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      // showAppBar is always false when embedded inside navigation_group_screen
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
                  const Text('Progress Dashboard',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                  Text(widget.groupName,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                  onPressed: _loadData,
                  tooltip: 'Refresh',
                ),
              ],
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _error != null
              ? _buildError()
              : _buildContent(),
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
            const Text('Could not load progress data',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _green, foregroundColor: Colors.white),
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
            Text('No students in this group yet',
                style: TextStyle(fontSize: 16, color: Colors.grey[600])),
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

  Widget _buildUnitSelector() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('FILTER BY UNIT',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[500],
                  letterSpacing: 0.8)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _unitChip(null, 'All Units'),
                ...List.generate(
                    _units.length,
                    (i) => _unitChip(_units[i], _units[i].unitTitle)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _unitChip(UnitInfo? unit, String label) {
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
                color: isSelected ? _green : Colors.grey[300]!),
          ),
          child: Text(label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              )),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    if (_stats.isEmpty) return const SizedBox.shrink();

    final avgOverallScore = _stats
            .map((s) => s.overallScore)
            .reduce((a, b) => a + b) ~/
        _stats.length;
    final totalActivities = _selectedUnit != null
        ? _selectedUnit!.totalActivities
        : _units.fold(0, (sum, u) => sum + u.totalActivities);
    final totalQuizzes = _selectedUnit != null
        ? (_selectedUnit!.totalLessonQuizzes +
            (_selectedUnit!.hasUnitQuiz ? 1 : 0))
        : _units.fold(
            0,
            (sum, u) =>
                sum + u.totalLessonQuizzes + (u.hasUnitQuiz ? 1 : 0));
    final unitLabel = _selectedUnit?.unitTitle ?? 'All Units';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [_green, _greenLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: _green.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6))
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
              Text(unitLabel,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              const Spacer(),
              GestureDetector(
                onTap: _loadData,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12)),
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
                      value: '${_stats.length}')),
              _verticalDivider(),
              Expanded(
                  child: _SummaryMetric(
                      icon: Icons.assessment_rounded,
                      label: 'Avg Score',
                      value: '$avgOverallScore%')),
              _verticalDivider(),
              Expanded(
                  child: _SummaryMetric(
                      icon: Icons.assignment_turned_in_rounded,
                      label: 'Activities',
                      value: '$totalActivities')),
              _verticalDivider(),
              Expanded(
                  child: _SummaryMetric(
                      icon: Icons.quiz_rounded,
                      label: 'Quizzes',
                      value: '$totalQuizzes')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider() => Container(
      width: 1, height: 48, color: Colors.white.withOpacity(0.3));

  Widget _buildStudentList() {
    if (_stats.isEmpty) {
      return Center(
          child: Text('No progress data available yet',
              style: TextStyle(color: Colors.grey[600], fontSize: 14)));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _stats.length,
      itemBuilder: (context, index) {
        return _StudentProgressCard(
          stats: _stats[index],
          rank: index + 1,
          groupId: widget.groupId,
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

  const _SummaryMetric(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 10)),
      ],
    );
  }
}

// ── Simplified student card ───────────────────────────────────────────────
// Removed: stats chips row (activities / quizzes / avg scores)
// Kept: rank, avatar, name, overall score badge, XP, progress bar, action buttons

class _StudentProgressCard extends StatelessWidget {
  final StudentStats stats;
  final int rank;
  final String groupId;

  const _StudentProgressCard({
    required this.stats,
    required this.rank,
    required this.groupId,
  });

  Color get _scoreColor => stats.overallScoreColor;

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
              color: Colors.grey[200], shape: BoxShape.circle),
          child: Center(
              child: Text('$rank',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey))),
        );
    }
  }

  Future<void> _exportStudentReport(BuildContext context) async {
    try {
      final studentDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(stats.studentId)
          .get();
      final studentData = studentDoc.data() ?? {};

      final reportsSnap = await FirebaseFirestore.instance
          .collection('students')
          .doc(stats.studentId)
          .collection('reports')
          .orderBy('generatedAt', descending: true)
          .limit(1)
          .get();

      if (reportsSnap.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No report found for this student')),
        );
        return;
      }

      final report = reportsSnap.docs.first.data();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReportPreviewScreen(
            studentName: stats.name,
            studentData: studentData,
            report: report,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading report: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatar = stats.avatar;
    // Progress bar reflects activities completed vs total
    final progressPercent =
        (stats.activityPercent * 100).round().clamp(0, 100);

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
            // ── Top row: rank · avatar · name + score · XP ───────────
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
                              fontSize: 16))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stats.name,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      // Score badge — labelled clearly as "Overall"
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: _scoreColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          'Overall ${stats.overallScore}%',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _scoreColor),
                        ),
                      ),
                    ],
                  ),
                ),
                // XP chip
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
                      Text('${stats.xp} XP',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF795548))),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── Progress bar (activities completed) ───────────────────
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: stats.activityPercent,
                      minHeight: 10,
                      backgroundColor: Colors.grey[200],
                      valueColor:
                          AlwaysStoppedAnimation<Color>(_scoreColor),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 44,
                  child: Text(
                    // Clear label: completed/total activities
                    '${stats.completedActivities}/${stats.totalActivities}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _scoreColor),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),

            // Caption under progress bar so it is unambiguous
            Text(
              'Activities completed',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),

            const SizedBox(height: 12),

            // ── Action buttons ─────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StudentDetailedProgressScreen(
                            studentId: stats.studentId,
                            studentName: stats.name,
                            groupId: groupId,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.list_alt, size: 18),
                    label: const Text('Details'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blueGrey,
                      side: const BorderSide(color: Colors.blueGrey),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _exportStudentReport(context),
                    icon: const Icon(Icons.picture_as_pdf_rounded,
                        size: 18),
                    label: const Text('Report'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}