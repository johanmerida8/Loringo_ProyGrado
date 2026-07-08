import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:loringo_app/screens/initials/activity_play_screen.dart';
import 'package:loringo_app/screens/initials/quiz_lesson_play_screen.dart';
import 'package:loringo_app/screens/initials/quiz_unit_play_screen.dart';
import 'package:loringo_app/theme/app_theme.dart';

class StudentActivitiesTab extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String? studentAvatar;

  const StudentActivitiesTab({
    super.key,
    required this.studentId,
    required this.studentName,
    this.studentAvatar,
  });

  @override
  State<StudentActivitiesTab> createState() => _StudentActivitiesTabState();
}

class _StudentActivitiesTabState extends State<StudentActivitiesTab> {
  String? groupId;
  String? groupName;
  String? _avatar;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _studentSub;
  Future<List<Map<String, dynamic>>>? _assignedContentFuture;

  @override
  void initState() {
    super.initState();
    _avatar = widget.studentAvatar;
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
      final fetchedAvatar = studentData?['avatar'] as String?;

      final isFirstLoad = _assignedContentFuture == null;
      final groupChanged = fetchedGroupId != groupId;

      String? fetchedGroupName = groupName;
      if (fetchedGroupId != null && groupChanged) {
        final groupDoc = await FirebaseFirestore.instance
            .collection('teacherGroups')
            .doc(fetchedGroupId)
            .get();
        if (groupDoc.exists) {
          fetchedGroupName = groupDoc.data()?['name'] ?? 'Unknown Group';
        }
      }

      if (!mounted) return;
      setState(() {
        groupId = fetchedGroupId;
        groupName = fetchedGroupName;
        if (fetchedAvatar != null) _avatar = fetchedAvatar;
        if (isFirstLoad || groupChanged) {
          _assignedContentFuture = _loadAssignedContent();
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
  void _refreshContent() {
    if (!mounted) return;
    setState(() {
      _assignedContentFuture = _loadAssignedContent();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _assignedContentFuture,
                builder: (context, snapshot) {
                  if (_assignedContentFuture == null ||
                      snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return _buildEmptyState();
                  }
                  return _buildActivityList(snapshot.data!);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Text("Loringo",
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.lgAll,
            boxShadow: AppShadows.card,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.primary,
                backgroundImage:
                    _avatar != null ? AssetImage(_avatar!) : null,
                child: _avatar == null
                    ? const Icon(Icons.person,
                        color: AppColors.onPrimary, size: 30)
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('Hello, ${widget.studentName}!',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 8),
                    Text(groupName ?? 'Loading...',
                        style: const TextStyle(
                            fontSize: 16, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_rounded, size: 100, color: AppColors.primary),
            SizedBox(height: 24),
            Text('No Activities Available',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
            SizedBox(height: 12),
            Text('Contact your teacher to add learning activities',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
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
      final bool isCompleted = item['isCompleted'] ?? false;
      final int stars = item['stars'] ?? 0;
      final bool isClosedAfterAttempts = item['isClosedAfterAttempts'] ?? false;

      activityWidgets.add(Padding(
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
                      gradient: isUnlocked
                          ? (isQuiz
                              ? const LinearGradient(
                                  colors: [Color(0xFFFFB74D), Color(0xFFFF9800)])
                              : const LinearGradient(colors: [
                                  AppColors.primary,
                                  AppColors.primaryLight
                                ]))
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
                                    ? (isQuiz ? Icons.quiz : Icons.star)
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
                            const Text(
                              'Quiz',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
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
                      'Completed',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ),
                ],
              ],
            ),],
          ),
        ),
      );

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

  void _navigateToActivity(Map<String, dynamic> item, bool isQuiz) {
    if (isQuiz) {
      if (item['lessonId'] == null || item['lessonId'] == '') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UnitQuizPlayScreen(
              contentId: item['contentId'],
              unitId: item['unitId'],
              quizId: item['quizId'],
              quizTitle: item['title'],
              studentId: widget.studentId,
              studentName: widget.studentName,
            ),
          ),
        ).then((_) => _refreshContent());
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LessonQuizPlayScreen(
              contentId: item['contentId'],
              unitId: item['unitId'],
              lessonId: item['lessonId'],
              quizId: item['quizId'],
              quizTitle: item['title'],
              studentId: widget.studentId,
            ),
          ),
        ).then((_) => _refreshContent());
      }
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
      ).then((_) => _refreshContent());
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
            .collection('students')
            .doc(widget.studentId)
            .collection('progress')
            .get();
        for (var d in progressSnapshot.docs) {
          final pd = d.data();
          if (pd['isCompleted'] == true) {
            if (pd.containsKey('activityId')) {
              completedActivities[pd['activityId']] = {
                'stars': pd['stars'] ?? 0,
                'bestScore': pd['bestScore'] ?? 0,
              };
            } else if (pd.containsKey('quizId')) {
              completedQuizzes[pd['quizId']] = {
                'stars': pd['stars'] ?? 0,
                'score': pd['score'] ?? 0
              };
              quizProgressDetails[pd['quizId']] = {
                'attempts': pd['attempts'] ?? 0,
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

        List<String> previousUnitIds = [];
        Map<String, bool> unitCompletedMap = {};

        for (final unitDoc in unitsSnap.docs) {
          final unitId = unitDoc.id;

          bool unitCompleted = false;
          bool hasUnitQuiz = false;
          bool unitQuizCompleted = false;

          final unitQuizzesSnap = await FirebaseFirestore.instance
              .collection('quizzes')
              .where('type', isEqualTo: 'unit')
              .where('contentId', isEqualTo: contentId)
              .where('unitId', isEqualTo: unitId)
              .get();

          if (unitQuizzesSnap.docs.isNotEmpty) {
            hasUnitQuiz = true;
            for (final qDoc in unitQuizzesSnap.docs) {
              final quizId = qDoc.id;
              if (completedQuizzes.containsKey(quizId)) {
                unitQuizCompleted = true;
                break;
              }
            }
          }

          final lessonsSnap = await FirebaseFirestore.instance
              .collection('content')
              .doc(contentId)
              .collection('units')
              .doc(unitId)
              .collection('lessons')
              .orderBy('order')
              .get();

          List<String> unitActivityIds = [];
          int unitActivitiesCompleted = 0;

          for (final lessonDoc in lessonsSnap.docs) {
            final lessonId = lessonDoc.id;

            final activitiesSnap = await FirebaseFirestore.instance
                .collection('content')
                .doc(contentId)
                .collection('units')
                .doc(unitId)
                .collection('lessons')
                .doc(lessonId)
                .collection('activities')
                .orderBy('order')
                .get();

            for (final actDoc in activitiesSnap.docs) {
              final activityId = actDoc.id;
              unitActivityIds.add(activityId);
              if (completedActivities.containsKey(activityId)) {
                unitActivitiesCompleted++;
              }
            }
          }

          bool allActivitiesCompleted = unitActivityIds.isNotEmpty &&
              unitActivitiesCompleted == unitActivityIds.length;

          if (hasUnitQuiz) {
            unitCompleted = allActivitiesCompleted && unitQuizCompleted;
          } else {
            unitCompleted = allActivitiesCompleted;
          }

          unitCompletedMap[unitId] = unitCompleted;

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

          for (final lessonDoc in lessonsSnap.docs) {
            final lessonId = lessonDoc.id;
            final lessonData = lessonDoc.data();

            final activitiesSnap = await FirebaseFirestore.instance
                .collection('content')
                .doc(contentId)
                .collection('units')
                .doc(unitId)
                .collection('lessons')
                .doc(lessonId)
                .collection('activities')
                .orderBy('order')
                .get();

            for (final actDoc in activitiesSnap.docs) {
              final actData = actDoc.data();
              final activityId = actDoc.id;
              final requiredActivityId = actData['requiredActivityId'];
              final isCompleted = completedActivities.containsKey(activityId);
              final stars = isCompleted
                  ? (completedActivities[activityId]['stars'] ?? 0)
                  : 0;

              bool isUnlocked = isUnitUnlocked;
              if (requiredActivityId != null && requiredActivityId.isNotEmpty) {
                isUnlocked = isUnlocked && completedActivities.containsKey(requiredActivityId);
              }

              allItems.add({
                'type': 'activity',
                'contentId': contentId,
                'unitId': unitId,
                'lessonId': lessonId,
                'lessonTitle': lessonData['title'] ?? 'Untitled Lesson',
                'activityId': activityId,
                'title': actData['title'] ?? 'Untitled Activity',
                'order': actData['order'] ?? 0,
                'difficulty': actData['difficulty'] ?? 'medium',
                'xpBase': actData['xpBase'] ?? 100,
                'isUnlocked': isUnlocked,
                'isCompleted': isCompleted,
                'stars': stars,
                'requiredActivityId': requiredActivityId,
              });
            }

            final lessonQuizzesSnap = await FirebaseFirestore.instance
                .collection('quizzes')
                .where('type', isEqualTo: 'lesson')
                .where('contentId', isEqualTo: contentId)
                .where('unitId', isEqualTo: unitId)
                .where('lessonId', isEqualTo: lessonId)
                .get();

            for (final qDoc in lessonQuizzesSnap.docs) {
              final qData = qDoc.data();
              final quizId = qDoc.id;

              final bool isQuizUnlocked = isUnitUnlocked &&
                  unitActivityIds.isNotEmpty &&
                  unitActivitiesCompleted == unitActivityIds.length;

              final isCompleted = completedQuizzes.containsKey(quizId);
              final stars = isCompleted ? (completedQuizzes[quizId]['stars'] ?? 0) : 0;

              allItems.add({
                'type': 'quiz',
                'contentId': contentId,
                'unitId': unitId,
                'lessonId': lessonId,
                'quizId': quizId,
                'title': qData['title'] ?? 'Lesson Quiz',
                'description': qData['description'] ?? 'Test your lesson knowledge',
                'isUnlocked': isQuizUnlocked,
                'isCompleted': isCompleted,
                'stars': stars,
              });
            }
          }

          // ── UNIT QUIZZES ──
          final unitQuizSnapshots = await FirebaseFirestore.instance
              .collection('quizzes')
              .where('type', isEqualTo: 'unit')
              .where('contentId', isEqualTo: contentId)
              .where('unitId', isEqualTo: unitId)
              .get();

          for (final qDoc in unitQuizSnapshots.docs) {
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
            // final bool hasPassed = progressDetail != null
            //     ? (progressDetail['passed'] as bool? ?? false)
            //     : false;

            final bool isCompletedAfterAttempts = progressDetail != null
                ? (progressDetail['isClosedAfterAttempts'] as bool? ?? false)
                : false;

            // final bool attemptsExhausted = attemptsUsed >= maxAttempts;

            final bool quizClosed = isCompletedAfterAttempts || isCompleted;

            final bool isQuizUnlocked = activitiesReady && !quizClosed;

            allItems.add({
              'type': 'quiz',
              'contentId': contentId,
              'unitId': unitId,
              'lessonId': '',
              'quizId': quizId,
              'title': qData['title'] ?? 'Unit Quiz',
              'description': qData['description'] ?? 'Complete to unlock next unit',
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