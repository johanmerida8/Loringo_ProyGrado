import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/app_loading_indicator.dart';
import 'package:loringo_app/components/avatar_image.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/models/teacher/student_progress.dart';
import 'package:loringo_app/screens/teacher/report_preview_screen.dart';
import 'package:loringo_app/screens/teacher/student_detail_progress_screen.dart';
import 'package:loringo_app/screens/teacher/student_report_history_screen.dart';
// import 'package:loringo_app/screens/teacher/student_reports_history_screen.dart';

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

class _StudentProgressDashboardState extends State<StudentProgressDashboard> {
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
    // Guards every setState() below. _loadData is a long chain of awaited
    // Firestore calls (several nested Future.wait blocks) — if the user
    // navigates away from this screen while any of those are still in
    // flight, this State object gets disposed but the async function
    // keeps running to completion. Without checking `mounted` before each
    // setState(), the eventual setState() call after that point throws
    // "setState() called after dispose()" — exactly the crash in the
    // logs, hitting both the success-path setState (~line 199) and the
    // catch-path setState. Checking `mounted` right before each call is
    // the standard fix: skip the state update entirely once the widget
    // is gone, since there's nothing left to update.
    if (!mounted) return;
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
                lessonsSnap.docs.map(
                  (lessonDoc) => db
                      .collection('content')
                      .doc(contentId)
                      .collection('units')
                      .doc(unitId)
                      .collection('lessons')
                      .doc(lessonDoc.id)
                      .collection('activities')
                      .get(),
                ),
              );

              final activityIds = activitySnaps
                  .expand((snap) => snap.docs.map((d) => d.id))
                  .toList();

              final lessonQuizSnaps = await Future.wait(
                lessonsSnap.docs.map(
                  (lessonDoc) => db
                      .collection('content')
                      .doc(contentId)
                      .collection('units')
                      .doc(unitId)
                      .collection('lessons')
                      .doc(lessonDoc.id)
                      .collection('quizzes')
                      .get(),
                ),
              );
              final lessonQuizIds = lessonQuizSnaps
                  .expand((snap) => snap.docs.map((d) => d.id))
                  .toList();

              final unitQuizzesSnap = await db
                  .collection('content')
                  .doc(contentId)
                  .collection('units')
                  .doc(unitId)
                  .collection('quizzes')
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

      await Future.wait(
        widget.students.map((student) async {
          final studentId = student['id'] as String;

          final rosterRef = db
              .collection('teacherGroups')
              .doc(widget.groupId)
              .collection('students')
              .doc(studentId);
          final results = await Future.wait([
            rosterRef.get(),
            rosterRef.collection('progress').get(),
          ]);

          final rosterDoc = results[0] as DocumentSnapshot;
          final progressSnap = results[1] as QuerySnapshot;

          final xp =
              (rosterDoc.data() as Map<String, dynamic>?)?['xp'] as int? ?? 0;
          final byUnit = <String, UnitRawData>{};
          final Map<String, Set<String>> completedActivityIdsPerUnit = {};

          for (final doc in progressSnap.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final unitId = (data['unitId'] as String?) ?? '';
            if (unitId.isEmpty) continue;

            byUnit.putIfAbsent(unitId, () => UnitRawData());
            completedActivityIdsPerUnit.putIfAbsent(unitId, () => {});

            if (data['type'] == 'activity' && data['isCompleted'] == true) {
              final activityId = doc.id;
              if (!completedActivityIdsPerUnit[unitId]!.contains(activityId)) {
                completedActivityIdsPerUnit[unitId]!.add(activityId);
                byUnit[unitId]!.completedActivities++;
                byUnit[unitId]!.activityScoreSum +=
                    (data['bestScore'] as int?) ?? 0;
              }
            }

            if (data['type'] == 'quiz' && data['isCompleted'] == true) {
              final quizId = doc.id;
              final correct = (data['correctAnswers'] as int?) ?? 0;
              final total = (data['totalQuestions'] as int?) ?? 0;

              // The quiz's own scope determines lesson vs. unit — not the
              // doc ID (quiz IDs are all 'quiz_<timestamp>', no prefix to
              // match on). unitInfo already carries which quiz IDs belong
              // to each bucket, built from the scope-filtered queries above.
              UnitInfo? unitInfo;
              for (final u in units) {
                if (u.unitId == unitId) {
                  unitInfo = u;
                  break;
                }
              }

              if (unitInfo != null && unitInfo.lessonQuizIds.contains(quizId)) {
                byUnit[unitId]!.completedLessonQuizzes++;
                byUnit[unitId]!.lessonQuizScoreSum += total == 0
                    ? 0
                    : (correct / total * 100).round();
              } else if (unitInfo != null && unitInfo.unitQuizId == quizId) {
                byUnit[unitId]!.unitQuizScore = correct;
                byUnit[unitId]!.unitQuizTotal = total;
              }
            }
          }

          rawProgress[studentId] = RawProgress(xp: xp, byUnit: byUnit);
        }),
      );

      // Long async chain finished — re-check mounted before touching
      // instance state or calling setState. _buildStats() itself also
      // calls setState() internally, so it must not run on a disposed
      // widget either; see the mounted guard added inside it below.
      if (!mounted) return;

      if (_selectedUnit != null &&
          !units.any((u) => u.unitId == _selectedUnit!.unitId)) {
        _selectedUnit = null;
      }

      _units = units;
      _rawProgress = rawProgress;
      _buildStats();

      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _buildStats() {
    // Called both from _loadData() (already mounted-guarded above) and
    // from _unitChip()'s onTap (always mounted, since it only fires from
    // a live gesture on an on-screen widget) — guarding here too makes
    // this method safe to call from either place without relying on the
    // caller to remember.
    if (!mounted) return;

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
      // Summed across every unit in targetUnits, not just a single
      // selected one -- this used to only populate when _selectedUnit !=
      // null, so under "All Units" the unit-quiz component silently
      // dropped out of overallScore's 30% weight for every student, even
      // though the "Quizzes" summary count still counted those same unit
      // quizzes. Summing generalizes correctly to both cases: with one
      // unit selected, targetUnits has exactly one entry, so the sum is
      // trivially that unit's own score/total, same as before.
      int unitQuizScoreSum = 0;
      int unitQuizTotalSum = 0;
      // Tracks how much of the ASSIGNED work (not just scored work) is
      // actually done, across all three kinds -- feeds hasIncompleteWork
      // below, independent of score.
      int totalUnitQuizzesAssigned = 0;
      int completedUnitQuizzes = 0;

      for (final unit in targetUnits) {
        totalActivities += unit.totalActivities;
        totalLessonQuizzes += unit.totalLessonQuizzes;
        if (unit.hasUnitQuiz) totalUnitQuizzesAssigned++;

        if (raw.byUnit.containsKey(unit.unitId)) {
          final u = raw.byUnit[unit.unitId]!;
          completedActivities += u.completedActivities;
          completedLessonQuizzes += u.completedLessonQuizzes;

          if (u.completedActivities > 0) {
            activityScoreSum += u.activityScoreSum;
            activitiesWithScore += u.completedActivities;
          }
          lessonQuizScoreSum += u.lessonQuizScoreSum;

          if (u.unitQuizScore != null &&
              u.unitQuizTotal != null &&
              u.unitQuizTotal! > 0) {
            unitQuizScoreSum += u.unitQuizScore!;
            unitQuizTotalSum += u.unitQuizTotal!;
            completedUnitQuizzes++;
          }
        }
      }

      final unitQuizScore = unitQuizTotalSum > 0 ? unitQuizScoreSum : null;
      final unitQuizTotal = unitQuizTotalSum > 0 ? unitQuizTotalSum : null;

      final avgActivityScore = activitiesWithScore == 0
          ? 0
          : (activityScoreSum / activitiesWithScore).round();
      final avgLessonQuizScore = completedLessonQuizzes == 0
          ? 0
          : (lessonQuizScoreSum / completedLessonQuizzes).round();
      final unitQuizPercent = unitQuizTotalSum > 0
          ? (unitQuizScoreSum / unitQuizTotalSum * 100).round()
          : 0;

      // Weighted average over only the components this unit actually HAS
      // -- a unit with no lesson/unit quiz no longer drags a student who
      // aced every activity down to 40% just because two-thirds of the
      // weights had nothing to average in. Each present component keeps
      // its original 40/30/30 relative weight, renormalized against
      // however many are actually present.
      double weightSum = 0;
      double scoreSum = 0;
      if (activitiesWithScore > 0) {
        weightSum += 0.4;
        scoreSum += 0.4 * avgActivityScore;
      }
      if (completedLessonQuizzes > 0) {
        weightSum += 0.3;
        scoreSum += 0.3 * avgLessonQuizScore;
      }
      if (unitQuizTotalSum > 0) {
        weightSum += 0.3;
        scoreSum += 0.3 * unitQuizPercent;
      }
      final overallScore = weightSum == 0 ? 0 : (scoreSum / weightSum).round();
      final overallStars = overallScore >= 90
          ? 3
          : (overallScore >= 70 ? 2 : 1);

      // Needs Attention, independent of the vanity score display: a
      // student who's engaged with this unit (done SOMETHING -- so one
      // who hasn't started yet isn't lumped in) and either (a) still has
      // assigned work left undone, or (b) is scoring low on what they
      // HAVE completed. Either condition alone is enough -- a student
      // who's behind but acing everything so far still needs a nudge to
      // catch up, same as one who's finished everything but struggling.
      final totalAssignedItems =
          totalActivities + totalLessonQuizzes + totalUnitQuizzesAssigned;
      final totalCompletedItems =
          completedActivities + completedLessonQuizzes + completedUnitQuizzes;
      final hasIncompleteWork =
          totalAssignedItems > 0 && totalCompletedItems < totalAssignedItems;
      final hasEngagedThisUnit =
          completedActivities > 0 ||
          completedLessonQuizzes > 0 ||
          unitQuizTotalSum > 0;
      final needsAttention =
          hasEngagedThisUnit && (hasIncompleteWork || overallScore < 70);

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
        needsAttention: needsAttention,
      );
    }).toList()..sort((a, b) => b.overallScore.compareTo(a.overallScore));

    setState(() => _stats = stats);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Scaffold(
      backgroundColor: Colors.grey[50],
      // showAppBar is always false when embedded inside navigation_group_screen
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: _green,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'teacher.student_progress_dashboard.progressDashboard'
                        .tr(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    widget.groupName,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                  onPressed: _loadData,
                  tooltip: 'common.refresh'.tr(),
                ),
              ],
            )
          : null,
      body: _loading
          ? const AppLoadingIndicator()
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
            Text(
              'teacher.student_progress_dashboard.couldNotLoadProgress'.tr(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
              label: Text('common.retry'.tr()),
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
            Icon(
              Icons.people_outline_rounded,
              size: 72,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'teacher.student_progress_dashboard.noStudentsInGroup'.tr(),
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

  Widget _buildUnitSelector() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'teacher.student_progress_dashboard.filterByUnit'.tr(),
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
                _unitChip(null,
                    'teacher.student_progress_dashboard.allUnits'.tr()),
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
            border: Border.all(color: isSelected ? _green : Colors.grey[300]!),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey[700],
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    if (_stats.isEmpty) return const SizedBox.shrink();

    // Completion: average, across students, of how much of the assigned
    // work (activities + lesson quizzes) they've actually done -- an
    // engagement signal, distinct from Avg Score's performance signal. A
    // group can have a great average score from the few who've started
    // while most students haven't touched the unit yet; this metric
    // surfaces that instead of hiding it behind the score average.
    final avgCompletion =
        (_stats
                    .map((s) {
                      final total = s.totalActivities + s.totalLessonQuizzes;
                      final completed =
                          s.completedActivities + s.completedLessonQuizzes;
                      return total == 0 ? 0.0 : completed / total;
                    })
                    .reduce((a, b) => a + b) /
                _stats.length *
                100)
            .round();

    // Needs attention: flagged per-student in _buildStats() -- engaged
    // with the unit AND either still has assigned work left undone, or is
    // scoring low on what they've completed (see StudentStats
    // .needsAttention's doc comment for the exact conditions).
    final needsAttention = _stats.where((s) => s.needsAttention).length;

    final unitLabel = _selectedUnit?.unitTitle ??
        'teacher.student_progress_dashboard.allUnits'.tr();

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
              const Icon(
                Icons.bar_chart_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                unitLabel,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _loadData,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'common.refresh'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
                  label: 'teacher.student_progress_dashboard.students'.tr(),
                  value: '${_stats.length}',
                ),
              ),
              _verticalDivider(),
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.trending_up_rounded,
                  label: 'teacher.student_progress_dashboard.completion'.tr(),
                  value: '$avgCompletion%',
                ),
              ),
              _verticalDivider(),
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.flag_rounded,
                  label:
                      'teacher.student_progress_dashboard.needsAttention'.tr(),
                  value: '$needsAttention',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider() =>
      Container(width: 1, height: 48, color: Colors.white.withOpacity(0.3));

  Widget _buildStudentList() {
    if (_stats.isEmpty) {
      return Center(
        child: Text(
          'teacher.student_progress_dashboard.noProgressDataYet'.tr(),
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
          groupId: widget.groupId,
          // El filtro de unidad actual determina si "Report" muestra un
          // solo reporte (unidad específica) o el histórico completo
          // (All Units, selectedUnitId == null).
          selectedUnitId: _selectedUnit?.unitId,
          selectedUnitTitle: _selectedUnit?.unitTitle,
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
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
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
  // null = "All Units" seleccionado → el botón Report abre el histórico.
  // no-null = unidad específica → el botón Report abre solo ese reporte.
  final String? selectedUnitId;
  final String? selectedUnitTitle;

  const _StudentProgressCard({
    required this.stats,
    required this.rank,
    required this.groupId,
    required this.selectedUnitId,
    required this.selectedUnitTitle,
  });

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

  Future<void> _exportStudentReport(BuildContext context) async {
    try {
      final studentDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(stats.studentId)
          .get();
      final studentData = studentDoc.data() ?? {};

      // ── "All Units": abre el histórico completo de reportes ──────────
      if (selectedUnitId == null) {
        if (!context.mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentReportsHistoryScreen(
              studentId: stats.studentId,
              studentName: stats.name,
              studentData: studentData,
            ),
          ),
        );
        return;
      }

      // ── Unidad específica: busca el reporte de ESA unidad únicamente ──
      // reports/{unitId} usa unitId como ID fijo del documento, así que
      // esto es una lectura directa, no una query — solo puede existir
      // un reporte por unidad.
      final reportDoc = await FirebaseFirestore.instance
          .collection('teacherGroups')
          .doc(groupId)
          .collection('students')
          .doc(stats.studentId)
          .collection('reports')
          .doc(selectedUnitId)
          .get();

      if (!reportDoc.exists) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
              'teacher.student_progress_dashboard.noReportSentYet'.tr())),
        );
        return;
      }

      final report = reportDoc.data()!;

      if (!context.mounted) return;
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
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(
          'teacher.student_progress_dashboard.errorLoadingReport'
              .tr(namedArgs: {'error': '$e'}))));
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final avatar = stats.avatar;
    // Progress bar reflects activities completed vs total
    final progressPercent = (stats.activityPercent * 100).round().clamp(0, 100);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  backgroundColor: const Color(0xFF4CAF50).withOpacity(0.15),
                  backgroundImage: avatar.isNotEmpty
                      ? avatarImageProvider(avatar)
                      : null,
                  onBackgroundImageError: avatar.isNotEmpty ? (_, __) {} : null,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stats.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                // XP chip
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFFFCA28),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.bolt_rounded,
                        size: 14,
                        color: Color(0xFFFFCA28),
                      ),
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
                      // Fixed green, not score-derived -- this bar shows
                      // activities COMPLETED, not performance, so a
                      // student who finished everything (e.g. 9/9) always
                      // reads as a clean green regardless of quiz scores
                      // elsewhere. Previously colored by overallScore,
                      // which could show red here even at 100% completion
                      // whenever the unit had no lesson/unit quiz to
                      // average in (missing components counted as 0%).
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF4CAF50),
                      ),
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
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4CAF50),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),

            // Caption under progress bar so it is unambiguous
            Text(
              'teacher.student_progress_dashboard.activitiesCompleted'.tr(),
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
                            // Mismo filtro que ya está activo en el
                            // dashboard (All Units → null, o la unidad
                            // seleccionada) — Details respeta ese alcance
                            // en vez de mostrar siempre todo.
                            unitId: selectedUnitId,
                            unitTitle: selectedUnitTitle,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.list_alt, size: 18),
                    label: Text('teacher.student_progress_dashboard.details'.tr()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blueGrey,
                      side: const BorderSide(color: Colors.blueGrey),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _exportStudentReport(context),
                    icon: Icon(
                      selectedUnitId == null
                          ? Icons.history_rounded
                          : Icons.picture_as_pdf_rounded,
                      size: 18,
                    ),
                    label: Text(selectedUnitId == null
                        ? 'teacher.student_progress_dashboard.reports'.tr()
                        : 'teacher.student_progress_dashboard.report'.tr()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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
