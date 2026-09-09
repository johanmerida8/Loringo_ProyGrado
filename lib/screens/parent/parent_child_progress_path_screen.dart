// parent_child_progress_path_screen.dart
//
// Read-only mirror of the student's Duolingo-style activity path
// (student_activities_screen.dart), for a parent checking in on one
// child. Same visual language (unit/lesson bubbles, lock/unlock/star
// state, mascot animations at each unit's midpoint) so a parent
// recognizes it as "the same path my child sees" — but every bubble is
// inert (no GestureDetector/onTap, no navigation into an activity or
// quiz) and the child's own avatar is pinned to whichever bubble they're
// currently on, auto-scrolled into view on open, so "where is my child
// right now" is answerable at a glance.
//
// Deliberately a self-contained copy of the unlock-chain computation
// rather than a shared import from student_activities_screen.dart — that
// file is intentionally left untouched.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:loringo_app/components/app_loading_indicator.dart';
import 'package:loringo_app/components/avatar_image.dart';
import 'package:loringo_app/providers/locale_provider.dart';
import 'package:loringo_app/screens/parent/widgets/parent_screen_header.dart';
import 'package:loringo_app/theme/app_theme.dart';

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

class ParentChildProgressPathScreen extends StatefulWidget {
  final Map<String, dynamic> child;

  const ParentChildProgressPathScreen({super.key, required this.child});

  @override
  State<ParentChildProgressPathScreen> createState() =>
      _ParentChildProgressPathScreenState();
}

class _ParentChildProgressPathScreenState
    extends State<ParentChildProgressPathScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  final Map<String, GlobalKey> _itemKeys = {};
  bool _scrolled = false;

  String get _childName =>
      widget.child['names'] as String? ?? 'common.student'.tr();
  String get _childAvatar =>
      widget.child['avatar'] as String? ?? kAvatarFallbackAsset;
  String? get _groupId => widget.child['groupId'] as String?;
  String get _studentId => widget.child['id'] as String;

  @override
  void initState() {
    super.initState();
    _future = _loadAssignedContent();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: Column(
        children: [
          ParentScreenHeader(
              title: 'parent.parent_child_progress_path_screen.titlePath'
                  .tr(namedArgs: {'name': _childName})),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const AppLoadingIndicator();
                  }
                  final activities = snapshot.data ?? const [];
                  if (activities.isEmpty) return _buildEmptyState();

                  if (!_scrolled) {
                    _scrolled = true;
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _scrollToCurrentItem(activities),
                    );
                  }

                  return _buildActivityPath(activities);
                },
              ),
            ),
          ),
        ],
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
            const Icon(
              Icons.assignment_rounded,
              size: 100,
              color: AppColors.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'parent.parent_child_progress_path_screen.noActivitiesTitle'.tr(),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'parent.parent_child_progress_path_screen.noActivitiesSubtitle'
                  .tr(namedArgs: {'name': _childName}),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The next thing the student should do — same rule
  /// student_activities_screen.dart's _findCurrentItem uses, so the
  /// avatar marker lands on the same bubble the child themself sees as
  /// "up next."
  Map<String, dynamic>? _findCurrentItem(
    List<Map<String, dynamic>> activities,
  ) {
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

  Widget _buildActivityPath(List<Map<String, dynamic>> activities) {
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

    final currentItem = _findCurrentItem(activities);
    final String? currentKeyId = currentItem == null
        ? null
        : _itemKeyId(currentItem);

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

      final itemKeyId = _itemKeyId(item);
      final itemKey = _itemKeys.putIfAbsent(itemKeyId, () => GlobalKey());
      final bool isCurrent = itemKeyId == currentKeyId;

      activityWidgets.add(
        KeyedSubtree(
          key: itemKey,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: isLeft
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.end,
              children: [
                Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: isUnlocked
                                ? (isLessonQuiz
                                      ? const LinearGradient(
                                          colors: [
                                            Color(0xFF64B5F6),
                                            AppColors.info,
                                          ],
                                        )
                                      : (isQuiz
                                            ? const LinearGradient(
                                                colors: [
                                                  Color(0xFFFFB74D),
                                                  Color(0xFFFF9800),
                                                ],
                                              )
                                            : const LinearGradient(
                                                colors: [
                                                  AppColors.primary,
                                                  AppColors.primaryLight,
                                                ],
                                              )))
                                : LinearGradient(
                                    colors: [
                                      Colors.grey[400]!,
                                      Colors.grey[600]!,
                                    ],
                                  ),
                            border: Border.all(
                              color: isCurrent
                                  ? AppColors.warning
                                  : Colors.white,
                              width: isCurrent ? 5 : 4,
                            ),
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
                                                  : (isQuiz
                                                        ? Icons.quiz
                                                        : Icons.star))
                                            : Icons.lock),
                                  color: Colors.white,
                                  size: 28,
                                ),
                                if (isCompleted) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _getStarDisplay(stars),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                  ),
                                ] else if (isQuiz) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    isLessonQuiz
                                        ? 'parent.parent_child_progress_path_screen.lessonQuiz'
                                            .tr()
                                        : 'parent.parent_child_progress_path_screen.unitTest'
                                            .tr(),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                      height: 1.1,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        // ── Child's avatar marker: pinned to whichever
                        // bubble they're currently on, so a parent spots
                        // "where is my child" without reading every row.
                        if (isCurrent)
                          Positioned(
                            top: -10,
                            right: -6,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.warning,
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.white,
                                backgroundImage: avatarImageProvider(_childAvatar),
                                onBackgroundImageError: (_, __) {},
                              ),
                            ),
                          ),
                      ],
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
                    if (isCurrent) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'parent.parent_child_progress_path_screen.childIsHere'
                              .tr(namedArgs: {'name': _childName}),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                    if (!isUnlocked && isClosedAfterAttempts) ...[
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 140,
                        child: Text(
                          'parent.parent_child_progress_path_screen.completed'
                              .tr(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ),
                    ],
                    if (isUnlocked && isOverdue) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'parent.parent_child_progress_path_screen.overdue'
                              .tr(),
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
                          'parent.parent_child_progress_path_screen.closedNoLongerAccepted'
                              .tr(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      if (count > 0 && progress == midPoint) {
        activityWidgets.add(
          Center(child: Lottie.asset(mascotPath, width: 130, height: 130)),
        );
      }
      unitProgress[uid] = progress + 1;
    }

    return SingleChildScrollView(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(children: activityWidgets),
    );
  }

  Future<List<Map<String, dynamic>>> _loadAssignedContent() async {
    try {
      final groupId = _groupId;
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
            .doc(_studentId)
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
                'score': pd['correctAnswers'] ?? 0,
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

        final unitsData = await Future.wait(
          unitsSnap.docs.map((unitDoc) async {
            final unitId = unitDoc.id;

            final unitLevel =
                await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
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

            final lessons = await Future.wait(
              lessonsSnap.docs.map((lessonDoc) async {
                final lessonId = lessonDoc.id;
                final lessonLevel =
                    await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
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
                return _LessonFetchResult(
                  lessonDoc,
                  lessonLevel[0],
                  lessonLevel[1],
                );
              }),
            );

            return _UnitFetchResult(unitDoc, unitQuizzesSnap, lessons);
          }),
        );

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

          List<String> previousLessonIds = [];
          Map<String, bool> lessonCompletedMap = {};

          for (final lesson in unit.lessons) {
            final lessonId = lesson.lessonDoc.id;
            final lessonData = lesson.lessonDoc.data();
            final activitiesSnap = lesson.activitiesSnap;

            int lessonActivitiesTotal = activitiesSnap.docs.length;
            int lessonActivitiesCompleted = 0;

            bool allPreviousLessonsCompleted = true;
            for (final prevLessonId in previousLessonIds) {
              if (!(lessonCompletedMap[prevLessonId] ?? false)) {
                allPreviousLessonsCompleted = false;
                break;
              }
            }
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
              final bool isScheduleReady =
                  scheduledTimestamp == null ||
                  !scheduledTimestamp.toDate().isAfter(DateTime.now());

              final dueTimestamp = actData['dueDate'] as Timestamp?;
              final bool isOverdue =
                  !isCompleted &&
                  dueTimestamp != null &&
                  dueTimestamp.toDate().isBefore(DateTime.now());

              final closeTimestamp = actData['closeDate'] as Timestamp?;
              final bool isClosed =
                  !isCompleted &&
                  closeTimestamp != null &&
                  closeTimestamp.toDate().isBefore(DateTime.now());

              bool isUnlocked =
                  isLessonUnlocked && isScheduleReady && !isClosed;
              if (requiredActivityId != null && requiredActivityId.isNotEmpty) {
                isUnlocked =
                    isUnlocked &&
                    completedActivities.containsKey(requiredActivityId);
              }

              allItems.add({
                'type': 'activity',
                'contentId': contentId,
                'unitId': unitId,
                'lessonId': lessonId,
                'lessonTitle': lessonData['title'] ??
                    'parent.parent_child_progress_path_screen.untitledLesson'
                        .tr(),
                'activityId': activityId,
                'title': actData['title'] ??
                    'parent.parent_child_progress_path_screen.untitledActivity'
                        .tr(),
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

            final bool thisLessonCompleted =
                lessonActivitiesTotal > 0 &&
                lessonActivitiesCompleted == lessonActivitiesTotal;
            lessonCompletedMap[lessonId] = thisLessonCompleted;
            previousLessonIds.add(lessonId);

            final lessonQuizSnap = lesson.lessonQuizSnap;
            if (lessonQuizSnap.docs.isNotEmpty) {
              final lqDoc = lessonQuizSnap.docs.first;
              final lqData = lqDoc.data();
              final lqQuizId = lqDoc.id;
              final lqCompleted = completedQuizzes.containsKey(lqQuizId);
              final lqStars = lqCompleted
                  ? (completedQuizzes[lqQuizId]['stars'] ?? 0)
                  : 0;

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
                    'parent.parent_child_progress_path_screen.lessonQuizFallback'
                        .tr(),
                'description':
                    lqData['description'] ??
                    'parent.parent_child_progress_path_screen.optionalCheckIn'
                        .tr(),
                'isUnlocked': lessonActivitiesReady,
                'isCompleted': lqCompleted,
                'isClosedAfterAttempts': false,
                'stars': lqStars,
              });
            }
          }

          bool allActivitiesCompleted =
              unitActivityIds.isNotEmpty &&
              unitActivitiesCompleted == unitActivityIds.length;
          bool unitCompleted = hasUnitQuiz
              ? (allActivitiesCompleted && unitQuizCompleted)
              : allActivitiesCompleted;
          unitCompletedMap[unitId] = unitCompleted;

          for (final qDoc in unit.unitQuizzesSnap.docs) {
            final qData = qDoc.data();
            final quizId = qDoc.id;

            final bool activitiesReady =
                isUnitUnlocked &&
                unitActivityIds.isNotEmpty &&
                unitActivitiesCompleted == unitActivityIds.length;

            final isCompleted = completedQuizzes.containsKey(quizId);
            final stars = isCompleted
                ? (completedQuizzes[quizId]['stars'] ?? 0)
                : 0;

            final int maxAttempts =
                (qData['maxAttempts'] as num?)?.toInt() ?? 1;
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
                  'parent.parent_child_progress_path_screen.unitQuizFallback'
                      .tr(),
              'description':
                  qData['description'] ??
                  'parent.parent_child_progress_path_screen.completeToUnlock'
                      .tr(),
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
}
