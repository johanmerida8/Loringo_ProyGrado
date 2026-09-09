import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/app_loading_indicator.dart';
import 'package:loringo_app/models/league_tier.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/initials/activity_play_screen.dart';
import 'package:loringo_app/screens/initials/quiz_play_screen.dart';
import 'package:loringo_app/screens/student/widgets/league_ascension_dialog.dart';
import 'package:loringo_app/theme/app_theme.dart';

// CHANGE LOG (lesson quiz removal):
// - Import of quiz_lesson_play_screen.dart removed — that file is being
//   deleted from the project (confirmed not in use going forward).
// - _navigateToActivity: the branch that routed to LessonQuizPlayScreen
//   based on `item['lessonId']` being empty/non-empty is gone. Every
//   quiz item now only ever means "unit quiz" (that's the only kind
//   that exists), so this always navigates to QuizPlayScreen.
// - _loadAssignedContent: the entire lesson-quiz block per lesson
//   (querying collection('quizzes').where('type', isEqualTo: 'lesson'),
//   building 'isQuizUnlocked' off unitActivitiesCompleted, and adding
//   those items to allItems) was deleted. The remaining unit-quiz block
//   dropped its `.where('type', isEqualTo: 'unit')` filter — new quiz
//   documents don't carry a 'type' field anymore (see database.dart),
//   so filtering by it would silently return zero results for anything
//   created after the migration. Filtering by contentId + unitId alone
//   is sufficient now that quizzes are unconditionally unit-scoped.
// - completedQuizzes / quizProgressDetails parsing in the progress-load
//   block is unchanged — it was never branching on quiz type, only on
//   whether a progress doc had a 'quizId' key, which still applies
//   identically to every quiz now.
//
// CHANGE LOG (scheduled activity availability):
// - Activities can now optionally carry a scheduledDate (Firestore
//   Timestamp, set by the teacher in create_activity_screen.dart).
//   _loadAssignedContent's per-activity isUnlocked computation ANDs in
//   an isScheduleReady check alongside the existing requiredActivityId
//   prerequisite check — see the inline comment at that call site for
//   the full rationale. This is the ONLY change for this feature; unit
//   unlock logic, quiz logic, and the prerequisite chain itself are
//   untouched.

// ── Raw-fetch result shapes for _loadAssignedContent's parallel fetch
// phase (see that method's doc comment) — just bundles a snapshot with
// its lesson/unit doc so the later sequential compute phase never has to
// await anything, only read from these.
class _LessonFetchResult {
  final QueryDocumentSnapshot<Map<String, dynamic>> lessonDoc;
  final QuerySnapshot<Map<String, dynamic>> activitiesSnap;
  final QuerySnapshot<Map<String, dynamic>> lessonQuizSnap;
  _LessonFetchResult(this.lessonDoc, this.activitiesSnap, this.lessonQuizSnap);
}

class _UnitFetchResult {
  final QueryDocumentSnapshot<Map<String, dynamic>> unitDoc;
  final QuerySnapshot<Map<String, dynamic>> unitQuizzesSnap;
  final List<_LessonFetchResult> lessons;
  _UnitFetchResult(this.unitDoc, this.unitQuizzesSnap, this.lessons);
}

class StudentActivitiesTab extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String? studentAvatar;

  /// true when hosted inside StudentMainScreen's bottom-nav/drawer chrome
  /// (the normal case). false is the distraction-free "Full Screen" mode
  /// (see _buildHeader's button) — pushed as its own bare route with no
  /// nav bar, drawer, or header, same pattern as TeacherActivityScreen's
  /// embedded flag in group_navigation_screen.dart.
  final bool embedded;

  const StudentActivitiesTab({
    super.key,
    required this.studentId,
    required this.studentName,
    this.studentAvatar,
    this.embedded = true,
  });

  @override
  State<StudentActivitiesTab> createState() => _StudentActivitiesTabState();
}

class _StudentActivitiesTabState extends State<StudentActivitiesTab> {
  String? groupId;

  // Archived groups keep every student's existing xp/progress/reports
  // fully intact (nothing here touches stored data) — this only stops
  // rendering the actionable content list, so no new work can be started
  // in a group the teacher has retired. Refetched whenever groupId
  // changes (see _listenToStudentDoc), and re-checked on every load, so
  // un-archiving is picked up immediately without any extra action.
  bool _isGroupArchived = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _studentSub;
  Future<List<Map<String, dynamic>>>? _assignedContentFuture;

  // The last successfully-loaded list, kept around so a refresh (e.g.
  // returning from an activity) can keep showing it while the new fetch
  // is in flight, instead of blanking to a full-screen spinner and
  // re-triggering every Lottie mascot animation on screen — see
  // _startLoad/build's FutureBuilder for how this is used.
  List<Map<String, dynamic>>? _lastLoadedActivities;

  // Persistent per-item keys (survive rebuilds since they're keyed by
  // stable activity/quiz id, not list index) so _scrollToCurrentItem can
  // find each bubble's on-screen position via Scrollable.ensureVisible.
  final Map<String, GlobalKey> _itemKeys = {};

  // Guards against re-triggering the auto-scroll on every unrelated
  // rebuild — FutureBuilder's builder re-runs whenever this widget
  // rebuilds, not just when _assignedContentFuture actually changes, so
  // without this a rebuild mid-manual-scroll would yank the student back.
  // Only a genuinely new future (fresh load / _refreshContent after
  // completing something) should trigger another auto-scroll.
  Future<List<Map<String, dynamic>>>? _scrolledForFuture;

  @override
  void initState() {
    super.initState();
    _listenToStudentDoc();
  }

  @override
  void dispose() {
    _studentSub?.cancel();
    super.dispose();
  }

  void _listenToStudentDoc() {
    _studentSub = FirebaseFirestore.instance
        .collection('students')
        .doc(widget.studentId)
        .snapshots()
        .listen((studentDoc) async {
      if (!studentDoc.exists) return;

      final studentData = studentDoc.data();
      final fetchedGroupId = studentData?['groupId'] as String?;

      final isFirstLoad = _assignedContentFuture == null;
      final groupChanged = fetchedGroupId != groupId;

      // Only re-check archived status when the group actually changes (or
      // on first load) — this listener otherwise fires on every student
      // doc write (e.g. xp increments), and re-fetching the group doc on
      // each of those would be wasted reads.
      bool archived = _isGroupArchived;
      if (isFirstLoad || groupChanged) {
        archived = false;
        if (fetchedGroupId != null) {
          final groupDoc = await FirebaseFirestore.instance
              .collection('teacherGroups')
              .doc(fetchedGroupId)
              .get();
          archived = groupDoc.data()?['archived'] == true;
        }
      }

      if (!mounted) return;
      setState(() {
        groupId = fetchedGroupId;
        _isGroupArchived = archived;
        if (isFirstLoad || groupChanged) {
          _startLoad();
        }
      });
    }, onError: (e) => debugPrint('Error listening to student doc: $e'));
  }

  /// Forces a real reload of assigned content. Reassigns
  /// _assignedContentFuture to a brand-new Future so unlock/completion
  /// state is recomputed from fresh Firestore data — a plain
  /// setState(() {}) does nothing here since an already-resolved Future
  /// never re-runs. This is what fixes the "need hot reload to see unit 2"
  /// bug. Called after returning from any activity or quiz screen.
  ///
  /// Also naturally picks up scheduled activities that have crossed
  /// their unlock date since the tab was last loaded — every call re-runs
  /// the isScheduleReady comparison in _loadAssignedContent against the
  /// current time, so no separate polling/timer is needed for that case.
  void _refreshContent() {
    if (!mounted) return;
    setState(_startLoad);
  }

  /// Kicks off a fresh load and, once it resolves, updates
  /// _lastLoadedActivities — done via .then() rather than inside
  /// FutureBuilder's builder (which runs during build and can't call
  /// setState) so build() can keep rendering the previous list until the
  /// new one is actually ready, instead of flashing to a blank spinner
  /// on every refresh. Must be called from inside a setState(){} block
  /// (both call sites above do this) since it reassigns
  /// _assignedContentFuture.
  void _startLoad() {
    final future = _loadAssignedContent();
    _assignedContentFuture = future;
    future.then((data) {
      if (!mounted || !identical(_assignedContentFuture, future)) return;
      setState(() => _lastLoadedActivities = data);
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final content = SafeArea(
      child: Column(
        children: [
          if (widget.embedded) _buildHeader(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _isGroupArchived
                  ? _buildArchivedGroupState()
                  : FutureBuilder<List<Map<String, dynamic>>>(
                future: _assignedContentFuture,
                builder: (context, snapshot) {
                  final bool isWaiting =
                      snapshot.connectionState == ConnectionState.waiting;

                  // True first load: nothing to show yet at all, not even
                  // a stale list — the only case that should show the
                  // full-screen spinner.
                  if (_assignedContentFuture == null ||
                      (isWaiting && _lastLoadedActivities == null)) {
                    return const AppLoadingIndicator();
                  }

                  // A refresh (returning from an activity, group change,
                  // a newly-crossed schedule date) while content is
                  // already on screen: keep showing it instead of
                  // flashing to blank and re-triggering every mascot
                  // animation — only swap once the new data actually
                  // lands (see _startLoad).
                  final List<Map<String, dynamic>> activities =
                      (isWaiting ? _lastLoadedActivities : snapshot.data) ??
                          const [];

                  if (activities.isEmpty) return _buildEmptyState();

                  // Only re-trigger the auto-scroll once this load has
                  // actually finished (not while still showing stale
                  // data during a background refresh) and only for a
                  // genuinely new future — FutureBuilder's builder also
                  // re-runs on unrelated rebuilds, and re-scrolling then
                  // would yank the student away from wherever they'd
                  // manually scrolled to.
                  if (!isWaiting &&
                      !identical(_scrolledForFuture, _assignedContentFuture)) {
                    _scrolledForFuture = _assignedContentFuture;
                    WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _scrollToCurrentItem(activities));
                  }

                  return Stack(children: [
                    _buildActivityList(activities),
                    if (isWaiting)
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(
                          color: AppColors.primary,
                          minHeight: 3,
                        ),
                      ),
                  ]);
                },
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.embedded) return content;
    return Scaffold(backgroundColor: AppColors.scaffoldBackground, body: content);
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          const Text("Loringo",
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
          const Spacer(),
          // Distraction-free mode — pushes this same tab as its own bare
          // route (embedded: false), outside StudentMainScreen's bottom
          // nav/drawer. Mirrors the teacher's "Full Screen" pill in
          // group_navigation_screen.dart.
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            elevation: 2,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StudentActivitiesTab(
                    studentId: widget.studentId,
                    studentName: widget.studentName,
                    studentAvatar: widget.studentAvatar,
                    embedded: false,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.fullscreen_rounded,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 4),
                  Text('student.student_activities_screen.fullScreen'.tr(),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      )),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The next thing the student should do: the first item (in the
  /// content's natural order) that's unlocked and not yet completed.
  /// Falls back to the last completed item if everything unlocked is
  /// already done, then to the very first item as a last resort.
  Map<String, dynamic>? _findCurrentItem(List<Map<String, dynamic>> activities) {
    for (final item in activities) {
      if ((item['isUnlocked'] ?? false) && !(item['isCompleted'] ?? false)) {
        return item;
      }
    }
    for (final item in activities.reversed) {
      if (item['isCompleted'] ?? false) return item;
    }
    return activities.isNotEmpty ? activities.first : null;
  }

  String _itemKeyId(Map<String, dynamic> item) => item['type'] == 'quiz'
      ? 'quiz_${item['quizId']}'
      : 'activity_${item['activityId']}';

  /// Scrolls so the "up next" bubble is centered on screen, instead of
  /// leaving the view wherever SingleChildScrollView's reverse:true
  /// happens to land by default (the end of the whole path — i.e. the
  /// latest-created activity, regardless of whether the student has
  /// reached it yet).
  void _scrollToCurrentItem(List<Map<String, dynamic>> activities) {
    final target = _findCurrentItem(activities);
    if (target == null) return;
    final ctx = _itemKeys[_itemKeyId(target)]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  Widget _buildArchivedGroupState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.archive_rounded, size: 100, color: AppColors.muted),
            const SizedBox(height: 24),
            Text('student.student_activities_screen.groupArchivedTitle'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
            const SizedBox(height: 12),
            Text('student.student_activities_screen.groupArchivedSubtitle'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.assignment_rounded, size: 100, color: AppColors.primary),
            const SizedBox(height: 24),
            Text('common.noActivitiesAvailable'.tr(),
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
            const SizedBox(height: 12),
            Text('common.contactTeacher'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityList(List<Map<String, dynamic>> activities) {
    final Map<String, int> unitItemCounts = {};
    final List<String> unitOrder = [];

    for (final item in activities) {
      final uid = item['unitId'] as String? ?? '';
      if (!unitItemCounts.containsKey(uid)) {
        unitOrder.add(uid);
        unitItemCounts[uid] = 0;
      }
      unitItemCounts[uid] = unitItemCounts[uid]! + 1;
    }

    final List<String> mascots = [
      'assets/animation/animation.json',
      'assets/animation/animation3.json',
      'assets/animation/animation1.json',
      'assets/animation/animation2.json',
    ];

    int activityIndex = 0;
    final Map<String, int> unitProgress = {};
    final List<Widget> activityWidgets = [];

    for (final item in activities) {
      final uid = item['unitId'] as String? ?? '';
      final count = unitItemCounts[uid] ?? 0;
      final progress = unitProgress[uid] ?? 0;
      final midPoint = count ~/ 2;
      final unitOrdinal = unitOrder.indexOf(uid) + 1;
      final mascotPath = mascots[(unitOrdinal - 1) % mascots.length];
      final bool isLeft = activityIndex % 2 == 0;
      activityIndex++;

      final bool isUnlocked = item['isUnlocked'] ?? false;
      final String itemType = item['type'] ?? 'activity';
      final bool isQuiz = itemType == 'quiz';
      final bool isLessonQuiz = isQuiz && item['quizScope'] == 'lesson';
      final bool isCompleted = item['isCompleted'] ?? false;
      final int stars = item['stars'] ?? 0;
      final bool isClosedAfterAttempts = item['isClosedAfterAttempts'] ?? false;
      final bool isOverdue = item['isOverdue'] ?? false;
      final bool isTurnInClosed = item['isClosed'] ?? false;

      final itemKey = _itemKeys.putIfAbsent(_itemKeyId(item), () => GlobalKey());

      activityWidgets.add(KeyedSubtree(
        key: itemKey,
        child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment:
              isLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
          children: [
            Column(
              children: [
                GestureDetector(
                  onTap:
                      isUnlocked ? () => _navigateToActivity(item, isQuiz) : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // Lesson Quiz: blue (matches AppColors.info used
                      // for it everywhere in the teacher UI). Unit Quiz:
                      // orange, unchanged from before.
                      gradient: isUnlocked
                          ? (isLessonQuiz
                              ? const LinearGradient(
                                  colors: [Color(0xFF64B5F6), AppColors.info])
                              : (isQuiz
                                  ? const LinearGradient(
                                      colors: [Color(0xFFFFB74D), Color(0xFFFF9800)])
                                  : const LinearGradient(colors: [
                                      AppColors.primary,
                                      AppColors.primaryLight
                                    ])))
                          : LinearGradient(
                              colors: [Colors.grey[400]!, Colors.grey[600]!]),
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    width: 80,
                    height: 80,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            !isUnlocked && isClosedAfterAttempts
                                ? Icons.check_circle
                                : (isUnlocked
                                    ? (isLessonQuiz
                                        ? Icons.school_outlined
                                        : (isQuiz ? Icons.quiz : Icons.star))
                                    : Icons.lock),
                            color: Colors.white,
                            size: 28,
                          ),
                          if (isCompleted) ...[
                            const SizedBox(height: 4),
                            Text(
                              _getStarDisplay(stars),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 16),
                            ),
                          ] else if (isQuiz) ...[
                            const SizedBox(height: 4),
                            Text(
                              isLessonQuiz
                                  ? 'student.student_activities_screen.lessonQuizBadge'.tr()
                                  : 'student.student_activities_screen.unitTestBadge'.tr(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                  height: 1.1),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 140,
                  child: Text(
                    item['title'],
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isUnlocked
                          ? AppColors.textPrimary
                          : Colors.grey[600],
                    ),
                  ),
                ),
                if (!isUnlocked && isClosedAfterAttempts) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 140,
                    child: Text(
                      'student.student_activities_screen.completedBadge'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ),
                ],
                if (isUnlocked && isOverdue) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'student.student_activities_screen.overdueBadge'.tr(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ],
                if (!isUnlocked && isTurnInClosed) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 140,
                    child: Text(
                      'student.student_activities_screen.closedNoLongerAccepted'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      )));

      if (count > 0 && progress == midPoint) {
        activityWidgets.add(Center(
          child: Lottie.asset(mascotPath, width: 130, height: 130),
        ));
      }
      unitProgress[uid] = progress + 1;
    }

    return SingleChildScrollView(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(children: activityWidgets),
    );
  }

  /// This student's current league tier, derived from seasonXp (see
  /// models/league_tier.dart) — one-time read, not a stream, since it's
  /// only used to diff before/after an activity in _navigateToActivity.
  Future<Map<String, dynamic>?> _fetchCurrentTier() async {
    if (groupId == null) return null;
    final doc = await FirebaseFirestore.instance
        .collection('teacherGroups')
        .doc(groupId)
        .collection('students')
        .doc(widget.studentId)
        .get();
    if (!doc.exists) return null;
    final seasonXp = ((doc.data()?['seasonXp'] as num?) ?? 0).toInt();
    return tierForXp(seasonXp);
  }

  /// Shows the celebration pop-up (league_ascension_dialog.dart) if
  /// `newTier` ranks higher than `previousTier` in kLeagueTiers — a
  /// strictly-higher index, not just a different key, so a same-tier
  /// re-completion or (once resetLeagueSeasons.ts runs) a season reset
  /// never triggers it.
  void _maybeCelebrateAscension(
    Map<String, dynamic>? previousTier,
    Map<String, dynamic>? newTier,
  ) {
    if (previousTier == null || newTier == null || !mounted) return;
    final prevIndex =
        kLeagueTiers.indexWhere((t) => t['key'] == previousTier['key']);
    final newIndex =
        kLeagueTiers.indexWhere((t) => t['key'] == newTier['key']);
    if (newIndex <= prevIndex) return;

    showLeagueAscensionDialog(
      context,
      leagueName: tierLabel(newTier['key'] as String),
      leagueImage: newTier['image'] as String?,
      leagueColor: newTier['color'] as Color,
    );
  }

  void _navigateToActivity(Map<String, dynamic> item, bool isQuiz) async {
    final previousTier = await _fetchCurrentTier();

    if (isQuiz) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuizPlayScreen(
            contentId: item['contentId'],
            unitId: item['unitId'],
            lessonId: item['quizScope'] == 'lesson'
                ? item['lessonId'] as String?
                : null,
            quizId: item['quizId'],
            quizTitle: item['title'],
            studentId: widget.studentId,
            studentName: widget.studentName,
          ),
        ),
      ).then((_) async {
        _refreshContent();
        _maybeCelebrateAscension(previousTier, await _fetchCurrentTier());
      });
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ActivityPlayScreen(
            contentId: item['contentId'],
            unitId: item['unitId'],
            lessonId: item['lessonId'],
            activityId: item['activityId'],
            activityTitle: item['title'],
            studentId: widget.studentId,
            xpBase: item['xpBase'] ?? 100,
            bonusXP: 0,
            collectionName: 'content',
            isPreview: false,
          ),
        ),
      ).then((_) async {
        _refreshContent();
        _maybeCelebrateAscension(previousTier, await _fetchCurrentTier());
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadAssignedContent() async {
    try {
      if (groupId == null) return [];

      final contentSnap = await FirebaseFirestore.instance
          .collection('content')
          .where('assignedTo', arrayContains: groupId)
          .get();

      final contentDocs = contentSnap.docs.toList()
        ..sort((a, b) {
          final ao = (a.data()['order'] as num? ?? 0).toInt();
          final bo = (b.data()['order'] as num? ?? 0).toInt();
          return ao.compareTo(bo);
        });

      Map<String, dynamic> completedActivities = {};
      Map<String, dynamic> completedQuizzes = {};
      Map<String, dynamic> quizProgressDetails = {};

      try {
        final progressSnapshot = await FirebaseFirestore.instance
            .collection('teacherGroups')
            .doc(groupId)
            .collection('students')
            .doc(widget.studentId)
            .collection('progress')
            .get();
        for (var d in progressSnapshot.docs) {
          final pd = d.data();
          if (pd['isCompleted'] == true) {
            if (pd['type'] == 'activity') {
              completedActivities[d.id] = {
                'stars': pd['stars'] ?? 0,
                'bestScore': pd['bestScore'] ?? 0,
              };
            } else if (pd['type'] == 'quiz') {
              completedQuizzes[d.id] = {
                'stars': pd['stars'] ?? 0,
                'score': pd['correctAnswers'] ?? 0
              };
              quizProgressDetails[d.id] = {
                'attempts': pd['totalAttempts'] ?? 0,
                'passed': pd['passed'] ?? false,
                'isClosedAfterAttempts': pd['isClosedAfterAttempts'] ?? false,
              };
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading progress: $e');
      }

      final List<Map<String, dynamic>> allItems = [];

      for (final contentDoc in contentDocs) {
        final contentId = contentDoc.id;
        final unitsSnap = await FirebaseFirestore.instance
            .collection('content')
            .doc(contentId)
            .collection('units')
            .orderBy('order')
            .get();

        // ── PHASE 1: fetch every unit's + lesson's raw data in parallel ──
        // None of these reads depend on unlock state, only on
        // contentId/unitId/lessonId identifiers already known from
        // unitsSnap — so every unit's (unitQuizzes, lessons) pair, and
        // every lesson's (activities, lessonQuiz) pair, fire concurrently
        // instead of one Firestore round trip at a time. This is also
        // what removes the old duplicate activities read (previously
        // fetched once for a unit-level tally and again to build items —
        // now fetched exactly once and reused for both).
        //
        // PHASE 2 below still walks units/lessons in original order —
        // unlock state is inherently sequential (unit 2 depends on unit
        // 1's outcome) — but by then everything it needs is already in
        // memory, so that loop never awaits.
        final unitsData = await Future.wait(unitsSnap.docs.map((unitDoc) async {
          final unitId = unitDoc.id;

          final unitLevel = await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
            // Unit Quizzes live in their own nested collection now
            // (content/{contentId}/units/{unitId}/quizzes) — separate from
            // Lesson Quizzes (nested one level deeper, under each lesson),
            // so no scope filter is needed to tell them apart anymore.
            FirebaseFirestore.instance
                .collection('content')
                .doc(contentId)
                .collection('units')
                .doc(unitId)
                .collection('quizzes')
                .get(),
            FirebaseFirestore.instance
                .collection('content')
                .doc(contentId)
                .collection('units')
                .doc(unitId)
                .collection('lessons')
                .orderBy('order')
                .get(),
          ]);
          final unitQuizzesSnap = unitLevel[0];
          final lessonsSnap = unitLevel[1];

          final lessons = await Future.wait(lessonsSnap.docs.map((lessonDoc) async {
            final lessonId = lessonDoc.id;
            final lessonLevel = await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
              FirebaseFirestore.instance
                  .collection('content')
                  .doc(contentId)
                  .collection('units')
                  .doc(unitId)
                  .collection('lessons')
                  .doc(lessonId)
                  .collection('activities')
                  .orderBy('order')
                  .get(),
              // ── LESSON QUIZ ──
              FirebaseFirestore.instance
                  .collection('content')
                  .doc(contentId)
                  .collection('units')
                  .doc(unitId)
                  .collection('lessons')
                  .doc(lessonId)
                  .collection('quizzes')
                  .limit(1)
                  .get(),
            ]);
            return _LessonFetchResult(lessonDoc, lessonLevel[0], lessonLevel[1]);
          }));

          return _UnitFetchResult(unitDoc, unitQuizzesSnap, lessons);
        }));

        // ── PHASE 2: sequential unlock computation over prefetched data ──
        List<String> previousUnitIds = [];
        Map<String, bool> unitCompletedMap = {};

        for (final unit in unitsData) {
          final unitId = unit.unitDoc.id;

          bool hasUnitQuiz = false;
          bool unitQuizCompleted = false;
          if (unit.unitQuizzesSnap.docs.isNotEmpty) {
            hasUnitQuiz = true;
            for (final qDoc in unit.unitQuizzesSnap.docs) {
              if (completedQuizzes.containsKey(qDoc.id)) {
                unitQuizCompleted = true;
                break;
              }
            }
          }

          bool isUnitUnlocked = true;
          if (previousUnitIds.isNotEmpty) {
            bool allPreviousCompleted = true;
            for (final prevUnitId in previousUnitIds) {
              if (!(unitCompletedMap[prevUnitId] ?? false)) {
                allPreviousCompleted = false;
                break;
              }
            }
            isUnitUnlocked = allPreviousCompleted;
          }

          List<String> unitActivityIds = [];
          int unitActivitiesCompleted = 0;

          // NEW: lesson-level chaining within this unit. Same pattern as
          // previousUnitIds/unitCompletedMap above, one level down —
          // previousLessonIds accumulates every lesson already visited
          // (in `order`), lessonCompletedMap records whether each one
          // finished ALL its activities. Lesson Quiz completion is
          // deliberately NOT part of this — Lesson Quiz stays optional/
          // non-blocking, so a student can move to lesson 2's activities
          // without having touched lesson 1's quiz.
          List<String> previousLessonIds = [];
          Map<String, bool> lessonCompletedMap = {};

          for (final lesson in unit.lessons) {
            final lessonId = lesson.lessonDoc.id;
            final lessonData = lesson.lessonDoc.data();
            final activitiesSnap = lesson.activitiesSnap;

            // per-lesson completion tracking, separate from the
            // unit-wide unitActivityIds/unitActivitiesCompleted counters
            // (those gate the Unit Quiz; these gate both this lesson's
            // own unlock-for-next-lesson check and its Lesson Quiz below).
            int lessonActivitiesTotal = activitiesSnap.docs.length;
            int lessonActivitiesCompleted = 0;

            // NEW: is every PRIOR lesson in this unit fully completed?
            // Mirrors allPreviousCompleted for units, one level down.
            // First lesson in the unit has an empty previousLessonIds,
            // so this defaults to true — same "nothing to wait on" rule
            // the first unit already gets.
            bool allPreviousLessonsCompleted = true;
            for (final prevLessonId in previousLessonIds) {
              if (!(lessonCompletedMap[prevLessonId] ?? false)) {
                allPreviousLessonsCompleted = false;
                break;
              }
            }
            // Both gates AND together: the unit must be unlocked AND
            // every earlier lesson in it must be done before this
            // lesson's activities open up.
            final bool isLessonUnlocked =
                isUnitUnlocked && allPreviousLessonsCompleted;

            for (final actDoc in activitiesSnap.docs) {
              final actData = actDoc.data();
              final activityId = actDoc.id;
              unitActivityIds.add(activityId);
              final requiredActivityId = actData['requiredActivityId'];
              final isCompleted = completedActivities.containsKey(activityId);
              if (isCompleted) {
                lessonActivitiesCompleted++;
                unitActivitiesCompleted++;
              }
              final stars = isCompleted
                  ? (completedActivities[activityId]['stars'] ?? 0)
                  : 0;

              final scheduledTimestamp = actData['scheduledDate'] as Timestamp?;
              final bool isScheduleReady = scheduledTimestamp == null ||
                  !scheduledTimestamp.toDate().isAfter(DateTime.now());

              // Display-only: due date never gates unlock/completion,
              // it only flags the activity as overdue when incomplete.
              final dueTimestamp = actData['dueDate'] as Timestamp?;
              final bool isOverdue = !isCompleted &&
                  dueTimestamp != null &&
                  dueTimestamp.toDate().isBefore(DateTime.now());

              // FEATURE: Canvas/Teams-style hard cutoff (turn_in_widget.dart).
              // Unlike dueDate, closeDate DOES gate unlock — but only
              // when actually set; null (every activity created before
              // this field existed, or one left "never closes") means
              // the activity behaves exactly as it always has, no cutoff
              // ever. Whether the gap between dueDate and closeDate
              // reads as a "late grace window" or "no late submissions"
              // is just how far apart the two dates are — no separate
              // flag needed (see TurnInSettings.allowsLateWindow).
              final closeTimestamp = actData['closeDate'] as Timestamp?;
              final bool isClosed = !isCompleted &&
                  closeTimestamp != null &&
                  closeTimestamp.toDate().isBefore(DateTime.now());

              // CHANGED: was `isUnitUnlocked && isScheduleReady`. Now
              // gated by isLessonUnlocked, which already includes
              // isUnitUnlocked — strictly tighter, never looser than
              // before. This is what blocks lesson 2's first activity
              // (its own requiredActivityId == null) until lesson 1 is
              // fully done.
              bool isUnlocked = isLessonUnlocked && isScheduleReady && !isClosed;
              if (requiredActivityId != null && requiredActivityId.isNotEmpty) {
                isUnlocked = isUnlocked && completedActivities.containsKey(requiredActivityId);
              }

              allItems.add({
                'type': 'activity',
                'contentId': contentId,
                'unitId': unitId,
                'lessonId': lessonId,
                'lessonTitle': lessonData['title'] ??
                    'student.student_activities_screen.untitledLesson'.tr(),
                'activityId': activityId,
                'title': actData['title'] ??
                    'student.student_activities_screen.untitledActivity'.tr(),
                'order': actData['order'] ?? 0,
                'difficulty': actData['difficulty'] ?? 'medium',
                'xpBase': actData['xpBase'] ?? 100,
                'isUnlocked': isUnlocked,
                'isCompleted': isCompleted,
                'stars': stars,
                'requiredActivityId': requiredActivityId,
                'scheduledDate': scheduledTimestamp,
                'dueDate': dueTimestamp,
                'isOverdue': isOverdue,
                'isClosed': isClosed,
              });
            }

            // record this lesson's completion so the NEXT lesson's
            // allPreviousLessonsCompleted check can see it.
            final bool thisLessonCompleted = lessonActivitiesTotal > 0 &&
                lessonActivitiesCompleted == lessonActivitiesTotal;
            lessonCompletedMap[lessonId] = thisLessonCompleted;
            previousLessonIds.add(lessonId);

            final lessonQuizSnap = lesson.lessonQuizSnap;
            if (lessonQuizSnap.docs.isNotEmpty) {
              final lqDoc = lessonQuizSnap.docs.first;
              final lqData = lqDoc.data();
              final lqQuizId = lqDoc.id;
              final lqCompleted = completedQuizzes.containsKey(lqQuizId);
              final lqStars = lqCompleted ? (completedQuizzes[lqQuizId]['stars'] ?? 0) : 0;

              // CHANGED: was `isUnitUnlocked && lessonActivitiesTotal > 0
              // && lessonActivitiesCompleted == lessonActivitiesTotal`.
              // Now uses isLessonUnlocked instead of isUnitUnlocked, so
              // a lesson-2 quiz also respects the new lesson chain (no
              // point unlocking lesson 2's quiz if lesson 2's activities
              // themselves aren't reachable yet). thisLessonCompleted is
              // the same value just computed above, reused instead of
              // recomputed.
              final bool lessonActivitiesReady =
                  isLessonUnlocked && thisLessonCompleted;

              allItems.add({
                'type': 'quiz',
                'quizScope': 'lesson',
                'contentId': contentId,
                'unitId': unitId,
                'lessonId': lessonId,
                'quizId': lqQuizId,
                'title': lqData['title'] ??
                    'student.student_activities_screen.lessonQuizFallback'.tr(),
                'description': lqData['description'] ??
                    'student.student_activities_screen.optionalCheckIn'.tr(),
                'isUnlocked': lessonActivitiesReady,
                'isCompleted': lqCompleted,
                'isClosedAfterAttempts': false,
                'stars': lqStars,
              });
            }
          }

          bool allActivitiesCompleted = unitActivityIds.isNotEmpty &&
              unitActivitiesCompleted == unitActivityIds.length;
          bool unitCompleted = hasUnitQuiz
              ? (allActivitiesCompleted && unitQuizCompleted)
              : allActivitiesCompleted;
          unitCompletedMap[unitId] = unitCompleted;

          // ── UNIT QUIZZES ──
          for (final qDoc in unit.unitQuizzesSnap.docs) {
            final qData = qDoc.data();
            final quizId = qDoc.id;

            final bool activitiesReady = isUnitUnlocked &&
                unitActivityIds.isNotEmpty &&
                unitActivitiesCompleted == unitActivityIds.length;

            final isCompleted = completedQuizzes.containsKey(quizId);
            final stars = isCompleted ? (completedQuizzes[quizId]['stars'] ?? 0) : 0;

            final int maxAttempts = (qData['maxAttempts'] as num?)?.toInt() ?? 1;
            final progressDetail = quizProgressDetails[quizId];
            final int attemptsUsed = progressDetail != null
                ? (progressDetail['attempts'] as int? ?? 0)
                : 0;

            final bool isCompletedAfterAttempts = progressDetail != null
                ? (progressDetail['isClosedAfterAttempts'] as bool? ?? false)
                : false;

            final bool quizClosed = isCompletedAfterAttempts || isCompleted;

            final bool isQuizUnlocked = activitiesReady && !quizClosed;

            allItems.add({
              'type': 'quiz',
              'contentId': contentId,
              'unitId': unitId,
              'lessonId': '',
              'quizId': quizId,
              'title': qData['title'] ??
                  'student.student_activities_screen.unitQuizFallback'.tr(),
              'description': qData['description'] ??
                  'student.student_activities_screen.completeToUnlock'.tr(),
              'isUnlocked': isQuizUnlocked,
              'isCompleted': isCompleted,
              'isClosedAfterAttempts': quizClosed,
              'attemptsUsed': attemptsUsed,
              'maxAttempts': maxAttempts,
              'stars': stars,
            });
          }

          previousUnitIds.add(unitId);
        }
      }
      return allItems;
    } catch (e) {
      debugPrint('Error loading assigned content: $e');
      return [];
    }
  }

  String _getStarDisplay(int stars) {
    switch (stars) {
      case 3:
        return '⭐⭐⭐';
      case 2:
        return '⭐⭐';
      case 1:
        return '⭐';
      default:
        return '';
    }
  }
}