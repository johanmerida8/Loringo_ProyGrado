// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class Database {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // =========================
  // USERS
  // =========================

  CollectionReference get users => _db.collection('users');

  Future<void> createUser({required String uid, required String name, required String email, required String role}) async {
    String finalRole = role;
    final nameLower = name.toLowerCase();
    if (nameLower == 'admin' || nameLower == 'administrador') {
      final count = await users.where('role', isEqualTo: 'admin').get().then((s) => s.docs.length);
      if (count >= 3) throw Exception('Maximum number of administrators (3) reached');
      finalRole = 'admin';
    }
    return users.doc(uid).set({
      'name': name, 'email': email, 'role': finalRole,
      'xp': 0, 'streak': 0, 'language': 'Spanish',
      'state': 1, 'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<DocumentSnapshot> getUser(String uid) => users.doc(uid).get();
  Stream<DocumentSnapshot> getUserStream(String uid) => users.doc(uid).snapshots();

  Future<void> updateUser({required String uid, String? name, String? language, int? xp, int? streak}) {
    final u = <String, dynamic>{};
    if (name != null) u['name'] = name;
    if (language != null) u['language'] = language;
    if (xp != null) u['xp'] = xp;
    if (streak != null) u['streak'] = streak;
    return users.doc(uid).update(u);
  }

  // =========================
  // STUDENT PROGRESS
  // =========================

  CollectionReference studentProgress(String studentId) =>
      _db.collection('students').doc(studentId).collection('progress');
  CollectionReference studentAttempts(String studentId, String activityId) =>
      studentProgress(studentId).doc(activityId).collection('attempts');

  /// [taskAnswers] — teacher-review feature: a map of taskId -> answerDetail
  /// (the type-specific "what did the student answer" shape built by each
  /// of the 13 task screens; see ActivityPlayScreen's class doc comment).
  ///
  /// Persistence rule: taskAnswers is written whenever THIS attempt's score
  /// TIES OR BEATS the previous bestScore (>=, not the strict > used for
  /// bestScore/XP below) — see the shouldUpdateTaskAnswers comment inline
  /// for why a tie still needs to refresh the stored detail. A strictly
  /// worse retry's taskAnswers are discarded so the stored detail always
  /// corresponds to the student's best-scoring attempt, never a stale
  /// worse one.
  Future<int> saveActivityCompletion({
    required String studentId, required String activityId,
    required String contentId, required String unitId,
    required int score, required int correctAnswers,
    required int wrongAnswers, required int xpBase, required int bonusXP,
    Map<String, Map<String, dynamic>> taskAnswers = const {},
  }) async {
    final progressRef = studentProgress(studentId).doc(activityId);
    final progressDoc = await progressRef.get();
    int totalAttempts = 1, bestScore = score, xpEarned;
    dynamic firstCompletedAt;
    final now = FieldValue.serverTimestamp();

    // Tracks whether THIS attempt's score should update the stored
    // taskAnswers detail — deliberately >= (not strictly >) unlike the
    // XP/bestScore comparison below. bestScore/XP genuinely should only
    // change on a strictly better attempt (no double-rewarding a tie).
    // taskAnswers is different: a tie (e.g. 100% again) still reflects
    // the CURRENT attempt's actual answers, and the teacher reviewing
    // should see what just happened, not a stale detail from a previous
    // attempt that happened to score the same. Using > here (matching
    // bestScore) was the original bug — a student re-playing an
    // already-100% activity would never have their new taskAnswers
    // persisted, silently keeping whatever detail was stored the first
    // time (including any pre-fix data missing a field).
    bool shouldUpdateTaskAnswers = true;

    if (progressDoc.exists) {
      final data = progressDoc.data() as Map<String, dynamic>;
      totalAttempts = (data['totalAttempts'] ?? 0) + 1;
      final previousBest = (data['bestScore'] ?? 0) as int;
      final isNewBest = score > previousBest;
      bestScore = isNewBest ? score : previousBest;
      // >= here, not just isNewBest — see doc comment above on why a
      // tied score should still refresh taskAnswers.
      shouldUpdateTaskAnswers = score >= previousBest;
      xpEarned = 5;
      firstCompletedAt = data['firstCompletedAt'];
    } else {
      xpEarned = (xpBase * score / 100.0).round() + bonusXP;
      firstCompletedAt = now;
    }

    int stars = 1;
    if (bestScore >= 90) stars = 3;
    else if (bestScore >= 70) stars = 2;

    await studentAttempts(studentId, activityId).doc('attempt_$totalAttempts').set({
      'attemptNumber': totalAttempts, 'score': score,
      'correctAnswers': correctAnswers, 'wrongAnswers': wrongAnswers,
      'xpEarned': xpEarned, 'completedAt': now,
    });

    final progressPayload = <String, dynamic>{
      'type': 'activity', 'contentId': contentId, 'unitId': unitId,
      'isCompleted': true, 'firstCompletedAt': firstCompletedAt,
      'lastCompletedAt': now, 'totalAttempts': totalAttempts, 'bestScore': bestScore,
      'stars': stars, 'xpEarned': xpEarned,
    };
    // Only overwrite the stored per-task detail when this attempt ties
    // or beats the previous best — a strictly worse retry's taskAnswers
    // never replace a better attempt's stored detail. On the very first
    // attempt (progressDoc doesn't exist yet) shouldUpdateTaskAnswers is
    // always true, so first-attempt detail is always saved as expected.
    if (shouldUpdateTaskAnswers) {
      progressPayload['taskAnswers'] = taskAnswers;
    }

    await progressRef.set(progressPayload, SetOptions(merge: true));
    await _db.collection('students').doc(studentId).update({'xp': FieldValue.increment(xpEarned)});
    return xpEarned;
  }

  Future<QuerySnapshot> getStudentProgress(String studentId) => studentProgress(studentId).get();
  Stream<QuerySnapshot> getStudentProgressStream(String studentId) => studentProgress(studentId).snapshots();

  Future<bool> isActivityCompleted(String studentId, String activityId) async {
    final doc = await studentProgress(studentId).doc(activityId).get();
    return doc.exists && (doc.data() as Map<String, dynamic>)['isCompleted'] == true;
  }

  /// Teacher-review feature: writes/updates the internal feedback note a
  /// teacher leaves on a specific activity's progress doc. Deliberately
  /// separate from the reports collection and saveReportOnly — this is
  /// NOT a parent-facing report and never triggers a push notification.
  /// It's a plain field on the same
  /// progress doc already used for scoring, exactly like the pattern
  /// UnitQuizReviewScreen already uses for the Unit Quiz's parent
  /// report feedback field, just without the send-to-parent step.
  Future<void> saveActivityFeedback({
    required String studentId,
    required String activityId,
    required String feedback,
  }) async {
    await studentProgress(studentId).doc(activityId).set({
      'feedback': feedback,
      'feedbackAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Same as saveActivityFeedback but for a Lesson Quiz's progress doc
  /// (studentProgress(studentId).doc(quizId) — quizzes and activities
  /// share the same progress subcollection, keyed by their own doc ID,
  /// so this is really the same operation with a name that reads
  /// correctly at the call site in the Lesson Quiz review screen).
  Future<void> saveLessonQuizFeedback({
    required String studentId,
    required String quizId,
    required String feedback,
  }) async {
    await studentProgress(studentId).doc(quizId).set({
      'feedback': feedback,
      'feedbackAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Mirrors saveActivityCompletion's structure: one attempt doc per
  /// submission in the (now shared) attempts subcollection, then a single
  /// merge onto the progress doc — no more separate "first attempt" vs
  /// "retry" code paths, and no more separate _saveStudentAnswers call
  /// racing this one to write `answers`/`completedAt` (that used to be a
  /// second, independent write from quiz_play_screen.dart).
  ///
  /// bestScore/correctAnswers/stars/xpEarned only update on a strictly
  /// better attempt; answers refreshes on a tie-or-better, matching
  /// saveActivityCompletion's taskAnswers nuance (a tied re-play should
  /// still show the teacher what just happened, not stale detail).
  Future<void> saveQuizCompletion({
    required String studentId,
    required String quizId,
    required String contentId,
    required String unitId,
    required int correctAnswers,
    required int totalQuestions,
    required List<Map<String, dynamic>> answers,
    required int xpEarned,
    required bool passed,
    bool isClosedAfterAttempts = false,
  }) async {
    final quizDoc = await allQuizzes.doc(quizId).get();
    final scope = quizDoc.exists
        ? (quizDoc.data() as Map<String, dynamic>)['scope'] as String? ?? 'unit'
        : 'unit';
    final configuredXp = quizDoc.exists
        ? ((quizDoc.data() as Map<String, dynamic>)['xpReward'] as num?)?.toInt() ?? xpEarned
        : xpEarned;

    final progressRef = studentProgress(studentId).doc(quizId);
    final progressDoc = await progressRef.get();
    int currentAttempts = 0;
    int previousBestScore = -1;
    bool previousPassed = false;
    dynamic firstCompletedAt;
    final now = FieldValue.serverTimestamp();
    final bool wasAlreadyCompleted = progressDoc.exists &&
        (progressDoc.data() as Map<String, dynamic>)['isCompleted'] == true;

    if (progressDoc.exists) {
      final data = progressDoc.data() as Map<String, dynamic>;
      currentAttempts = (data['totalAttempts'] ?? 0) as int;
      previousBestScore = (data['bestScore'] ?? -1) as int;
      previousPassed = (data['passed'] ?? false) as bool;
      firstCompletedAt = data['firstCompletedAt'];
    } else {
      firstCompletedAt = now;
    }

    final bool effectivePassed = scope == 'lesson' ? true : passed;
    final int effectiveXpEarned = scope == 'lesson'
        ? (wasAlreadyCompleted ? 5 : configuredXp)
        : xpEarned;

    final scorePercent = totalQuestions == 0
        ? 0
        : (correctAnswers / totalQuestions * 100).round();
    final newAttempts = currentAttempts + 1;
    final bool isNewBest = scorePercent > previousBestScore;
    final bool shouldUpdateAnswers = scorePercent >= previousBestScore;

    int stars = 1;
    if (scorePercent >= 90) stars = 3;
    else if (scorePercent >= 70) stars = 2;

    await studentAttempts(studentId, quizId).doc('attempt_$newAttempts').set({
      'attemptNumber': newAttempts, 'score': scorePercent,
      'correctAnswers': correctAnswers,
      'wrongAnswers': totalQuestions - correctAnswers,
      'xpEarned': effectiveXpEarned, 'completedAt': now,
    });

    final progressPayload = <String, dynamic>{
      'type': 'quiz', 'contentId': contentId, 'unitId': unitId,
      'totalQuestions': totalQuestions,
      'isCompleted': true, 'firstCompletedAt': firstCompletedAt,
      'lastCompletedAt': now, 'totalAttempts': newAttempts,
      'passed': previousPassed || effectivePassed,
      // Preserves existing behavior: every submitted attempt marks the
      // quiz closed, regardless of maxAttempts remaining or the
      // isClosedAfterAttempts argument — that's what this call has
      // always effectively done (the old code had the same
      // unconditional `true` here), kept as-is since fixing it wasn't
      // part of this schema cleanup.
      'isClosedAfterAttempts': true,
      'xpEarned': effectiveXpEarned,
    };
    if (isNewBest) {
      progressPayload['bestScore'] = scorePercent;
      progressPayload['correctAnswers'] = correctAnswers;
      progressPayload['stars'] = stars;
    }
    if (shouldUpdateAnswers) {
      progressPayload['answers'] = answers;
    }
    await progressRef.set(progressPayload, SetOptions(merge: true));

    if (effectiveXpEarned > 0 && effectivePassed) {
      await _db.collection('students').doc(studentId).update({
        'xp': FieldValue.increment(effectiveXpEarned),
      });
      debugPrint('Added $effectiveXpEarned XP to student $studentId');
    } else {
      debugPrint('No XP added (xpEarned = $effectiveXpEarned)');
    }
  }

  CollectionReference reports(String studentId) => _db.collection('students').doc(studentId).collection('reports');
  Future<DocumentSnapshot> getReport(String studentId, String reportId) => reports(studentId).doc(reportId).get();
  Stream<QuerySnapshot> getReportsStream(String studentId) => reports(studentId).snapshots();

  Future<void> saveReportOnly({
    required String studentId,
    required String unitId,
    required String unitTitle,
    required int score,
    required int totalQuestions,
    required int stars,
    required String feedback,
  }) async {
    final quizPercent = totalQuestions == 0 ? 0 : (score / totalQuestions * 100).round();

    final existingReport = await reports(studentId).doc(unitId).get();
    final previousUnitScores = existingReport.exists
        ? (existingReport.data() as Map<String, dynamic>)['previousUnitScores'] as List? ?? []
        : [];

    int totalActivities = 0;
    int activitiesCompleted = 0;

    try {
      final contentSnapshot = await _db.collection('content').get();

      String? contentId;
      for (final doc in contentSnapshot.docs) {
        final unitsSnapshot = await doc.reference.collection('units').get();
        final hasUnit = unitsSnapshot.docs.any((u) => u.id == unitId);
        if (hasUnit) {
          contentId = doc.id;
          break;
        }
      }

      if (contentId != null) {
        final lessonsSnapshot = await personalizedLessons(contentId, unitId).get();

        for (final lesson in lessonsSnapshot.docs) {
          final activitiesSnapshot = await personalizedActivities(contentId, unitId, lesson.id).get();
          totalActivities += activitiesSnapshot.docs.length;
        }

        final studentProgressSnapshot = await studentProgress(studentId).get();

        for (final progressDoc in studentProgressSnapshot.docs) {
          final data = progressDoc.data() as Map<String, dynamic>;
          if (data['unitId'] == unitId &&
              data['isCompleted'] == true &&
              data['type'] == 'activity') {
            activitiesCompleted++;
          }
        }
      }
    } catch (e) {
      debugPrint('Error calculating activities for report: $e');
    }

    final activitiesPercent = totalActivities == 0
        ? 0
        : (activitiesCompleted / totalActivities * 100).round();

    await reports(studentId).doc(unitId).set({
      'reportType': 'unit',
      'unitId': unitId,
      'unitTitle': unitTitle,
      'quizCorrect': score,
      'quizIncorrect': totalQuestions - score,
      'quizTotalQuestions': totalQuestions,
      'quizPercent': quizPercent,
      'activitiesCompleted': activitiesCompleted,
      'totalActivities': totalActivities,
      'activitiesPercent': activitiesPercent,
      'previousUnitScores': previousUnitScores,
      'stars': stars,
      'feedback': feedback,
      'generatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    debugPrint('✅ Report saved for student: $studentId, unit: $unitId');
    debugPrint('   Quiz: $score/$totalQuestions ($quizPercent%)');
    debugPrint('   Activities: $activitiesCompleted/$totalActivities ($activitiesPercent%)');
  }

  // =========================
  // PERSONALIZED CONTENT
  // =========================

  CollectionReference get personalizedContent => _db.collection('content');

  Future<void> createPersonalizedContent({
    required String contentId,
    required String title,
    required String description,
    required String ageGroup,
    required int order,
    required String teacherId,
    List<String>? assignedTo,
  }) =>
      personalizedContent.doc(contentId).set({
        'teacherId': teacherId,
        'assignedTo': assignedTo ?? [],
        'title': title,
        'description': description,
        'ageGroup': ageGroup,
        'order': order,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> assignContentToGroups({required String contentId, required List<String> groupIds}) =>
      personalizedContent.doc(contentId).update({'assignedTo': groupIds, 'assignedAt': FieldValue.serverTimestamp()});

  Future<QuerySnapshot> getPersonalizedContent(String groupId) =>
      personalizedContent.where('assignedTo', arrayContains: groupId).orderBy('order').get();

  Stream<QuerySnapshot> getPersonalizedContentStream(String groupId) =>
      personalizedContent.where('assignedTo', arrayContains: groupId).snapshots();

  Stream<QuerySnapshot> getTeacherContentStream(String teacherId) =>
      personalizedContent.where('teacherId', isEqualTo: teacherId).orderBy('order').snapshots();

  Future<void> assignContentToGroup({required String contentId, required String groupId}) =>
      personalizedContent.doc(contentId).update({'assignedTo': FieldValue.arrayUnion([groupId]), 'assignedAt': FieldValue.serverTimestamp()});

  Future<void> removeContentFromGroup({required String contentId, required String groupId}) =>
      personalizedContent.doc(contentId).update({'assignedTo': FieldValue.arrayRemove([groupId])});

  Future<DocumentSnapshot> getPersonalizedContentDoc(String contentId) => personalizedContent.doc(contentId).get();

  Future<void> updatePersonalizedContent({
    required String contentId,
    required String title,
    required String description,
    required String ageGroup,
    required int order,
  }) =>
      personalizedContent.doc(contentId).update({
        'title': title,
        'description': description,
        'ageGroup': ageGroup,
        'order': order,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> deletePersonalizedContent(String contentId) async {
    final doc = await personalizedContent.doc(contentId).get();
    if (!doc.exists) return;
    final data = doc.data() as Map<String, dynamic>;
    final teacherId = data['teacherId'] as String?;
    final deletedOrder = data['order'] as int?;

    await personalizedContent.doc(contentId).delete();

    if (teacherId == null || deletedOrder == null) return;

    final siblingsAfter = await personalizedContent
        .where('teacherId', isEqualTo: teacherId)
        .where('order', isGreaterThan: deletedOrder)
        .get();
    if (siblingsAfter.docs.isEmpty) return;

    final batch = _db.batch();
    for (final sibling in siblingsAfter.docs) {
      final currentOrder = (sibling.data() as Map<String, dynamic>)['order'] as int? ?? 0;
      batch.update(sibling.reference, {'order': currentOrder - 1});
    }
    await batch.commit();
  }

  // =========================
  // UNITS / LESSONS / ACTIVITIES / TASKS
  // =========================

  CollectionReference personalizedUnits(String contentId) => personalizedContent.doc(contentId).collection('units');
  CollectionReference personalizedLessons(String contentId, String unitId) => personalizedUnits(contentId).doc(unitId).collection('lessons');
  CollectionReference personalizedActivities(String contentId, String unitId, String lessonId) => personalizedLessons(contentId, unitId).doc(lessonId).collection('activities');
  CollectionReference personalizedTasks(String contentId, String unitId, String lessonId, String activityId) => personalizedActivities(contentId, unitId, lessonId).doc(activityId).collection('tasks');

  Future<void> createPersonalizedUnit({required String groupId, required String contentId, required String unitId, required String title, required int order}) =>
      personalizedUnits(contentId).doc(unitId).set({'title': title, 'order': order, 'createdAt': FieldValue.serverTimestamp()});

  Future<QuerySnapshot> getPersonalizedUnits(String groupId, String contentId) => personalizedUnits(contentId).orderBy('order').get();

  Stream<QuerySnapshot> getPersonalizedUnitsStream(String groupId, String contentId) => personalizedUnits(contentId).orderBy('order').snapshots();

  Future<void> updatePersonalizedUnit({required String groupId, required String contentId, required String unitId, required String title, required int order}) =>
      personalizedUnits(contentId).doc(unitId).update({'title': title, 'order': order});

  Future<void> deletePersonalizedUnit(String groupId, String contentId, String unitId) async {
    final ref = personalizedUnits(contentId).doc(unitId);
    final doc = await ref.get();
    if (!doc.exists) return;
    final deletedOrder = (doc.data() as Map<String, dynamic>)['order'] as int?;

    await ref.delete();

    if (deletedOrder == null) return;

    final siblingsAfter = await personalizedUnits(contentId)
        .where('order', isGreaterThan: deletedOrder)
        .get();
    if (siblingsAfter.docs.isEmpty) return;

    final batch = _db.batch();
    for (final sibling in siblingsAfter.docs) {
      final currentOrder = (sibling.data() as Map<String, dynamic>)['order'] as int? ?? 0;
      batch.update(sibling.reference, {'order': currentOrder - 1});
    }
    await batch.commit();
  }

  Future<void> createPersonalizedLesson({required String groupId, required String contentId, required String unitId, required String lessonId, required String title, required int order}) =>
      personalizedLessons(contentId, unitId).doc(lessonId).set({'title': title, 'order': order, 'createdAt': FieldValue.serverTimestamp()});

  Future<QuerySnapshot> getPersonalizedLessons(String groupId, String contentId, String unitId) => personalizedLessons(contentId, unitId).orderBy('order').get();

  Stream<QuerySnapshot> getPersonalizedLessonsStream(String groupId, String contentId, String unitId) => personalizedLessons(contentId, unitId).orderBy('order').snapshots();

  Future<void> updatePersonalizedLesson({required String groupId, required String contentId, required String unitId, required String lessonId, required String title, required int order}) =>
      personalizedLessons(contentId, unitId).doc(lessonId).update({'title': title, 'order': order});

  Future<void> deletePersonalizedLesson(String groupId, String contentId, String unitId, String lessonId) async {
    final ref = personalizedLessons(contentId, unitId).doc(lessonId);
    final doc = await ref.get();
    if (!doc.exists) return;
    final deletedOrder = (doc.data() as Map<String, dynamic>)['order'] as int?;

    await ref.delete();

    if (deletedOrder == null) return;

    final siblingsAfter = await personalizedLessons(contentId, unitId)
        .where('order', isGreaterThan: deletedOrder)
        .get();
    if (siblingsAfter.docs.isEmpty) return;

    final batch = _db.batch();
    for (final sibling in siblingsAfter.docs) {
      final currentOrder = (sibling.data() as Map<String, dynamic>)['order'] as int? ?? 0;
      batch.update(sibling.reference, {'order': currentOrder - 1});
    }
    await batch.commit();
  }

  Future<void> createPersonalizedActivity({
    required String groupId,
    required String contentId,
    required String unitId,
    required String lessonId,
    required String activityId,
    required String title,
    required int order,
    String? requiredActivityId,
    int? xpBase,
    String? difficulty,
    DateTime? scheduledDate,
    DateTime? dueDate,
    DateTime? closeDate,
  }) =>
      personalizedActivities(contentId, unitId, lessonId).doc(activityId).set({
        'title': title,
        'order': order,
        'requiredActivityId': requiredActivityId,
        'xpBase': xpBase ?? 100,
        'difficulty': difficulty ?? 'easy',
        // FEATURE: optional scheduled availability. Omitted or
        // explicitly null (the default from create_activity_screen.dart
        // unless the teacher picks a date) means "create directly,
        // available immediately" — identical to every activity created
        // before this field existed. The Firestore SDK auto-converts a
        // Dart DateTime to a native Timestamp on write, so
        // student_activities_screen.dart reads this back as a Timestamp
        // for its isScheduleReady comparison with no extra conversion
        // needed here.
        'scheduledDate': scheduledDate,
        // FEATURE: optional deadline, independent of scheduledDate — not
        // an unlock gate, just a display/notification signal read by
        // student_activities_screen.dart (overdue tag) and the
        // notifyOverdueActivities Cloud Function (teacher alerts).
        'dueDate': dueDate,
        // FEATURE: Canvas/Teams-style hard cutoff (turn_in_widget.dart).
        // Null (the default — identical to every pre-existing activity)
        // means no cutoff, the activity stays completable forever. When
        // set, it's the only field that actually blocks submission
        // (student_activities_screen.dart's unlock computation) —
        // whether that creates a late-turn-in grace window or blocks
        // late work entirely falls out of comparing it to dueDate
        // (see TurnInSettings.allowsLateWindow), no separate flag.
        'closeDate': closeDate,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<QuerySnapshot> getPersonalizedActivities(String groupId, String contentId, String unitId, String lessonId) =>
      personalizedActivities(contentId, unitId, lessonId).orderBy('order').get();

  Stream<QuerySnapshot> getPersonalizedActivitiesStream(String groupId, String contentId, String unitId, String lessonId) =>
      personalizedActivities(contentId, unitId, lessonId).orderBy('order').snapshots();

  /// Flat list of every Activity assigned to [groupId], each tagged with a
  /// parent-facing turn-in `status` for [studentId]. Ports the exact
  /// content->units->lessons->activities walk and the isScheduleReady/
  /// isOverdue/isClosed/isUnlocked formulas from
  /// student_activities_screen.dart's _loadAssignedContent (kept in sync
  /// by hand — same business rules, just also emitting a `status` label
  /// instead of driving unlock gating for the student themselves).
  /// Quizzes are out of scope: they carry no dueDate/scheduledDate/
  /// closeDate in this app, so there's nothing to bucket them by — unit
  /// quiz completion is still read internally, purely because it feeds
  /// unitCompletedMap for later units' lock-chain, exactly as it does in
  /// the student-side method.
  ///
  /// `status` is one of: 'completed', 'past_due', 'not_open_yet',
  /// 'due_today', 'due_tomorrow', 'later'. For 'not_open_yet' items,
  /// `notOpenReason` is either 'scheduled' (scheduledDate still in the
  /// future — see `scheduledDate` for when it opens) or 'locked' (blocked
  /// by lesson/unit progression or an incomplete prerequisite activity).
  Future<List<Map<String, dynamic>>> getChildActivityStatusList({
    required String groupId,
    required String studentId,
  }) async {
    final contentSnap = await _db
        .collection('content')
        .where('assignedTo', arrayContains: groupId)
        .get();

    final contentDocs = contentSnap.docs.toList()
      ..sort((a, b) {
        final ao = (a.data()['order'] as num? ?? 0).toInt();
        final bo = (b.data()['order'] as num? ?? 0).toInt();
        return ao.compareTo(bo);
      });

    final completedActivities = <String, dynamic>{};
    final completedQuizzes = <String, dynamic>{};

    final progressSnapshot = await _db
        .collection('students')
        .doc(studentId)
        .collection('progress')
        .get();
    for (final d in progressSnapshot.docs) {
      final pd = d.data();
      if (pd['isCompleted'] == true) {
        if (pd['type'] == 'activity') {
          completedActivities[d.id] = {
            'stars': pd['stars'] ?? 0,
            'bestScore': pd['bestScore'] ?? 0,
          };
        } else if (pd['type'] == 'quiz') {
          completedQuizzes[d.id] = true;
        }
      }
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final List<Map<String, dynamic>> allItems = [];

    for (final contentDoc in contentDocs) {
      final contentId = contentDoc.id;
      final contentTitle = contentDoc.data()['title'] ?? 'Untitled Content';

      final unitsSnap = await _db
          .collection('content')
          .doc(contentId)
          .collection('units')
          .orderBy('order')
          .get();

      List<String> previousUnitIds = [];
      Map<String, bool> unitCompletedMap = {};

      for (final unitDoc in unitsSnap.docs) {
        final unitId = unitDoc.id;
        final unitData = unitDoc.data();

        bool unitCompleted = false;
        bool hasUnitQuiz = false;
        bool unitQuizCompleted = false;

        final unitQuizzesSnap = await _db
            .collection('quizzes')
            .where('contentId', isEqualTo: contentId)
            .where('unitId', isEqualTo: unitId)
            .where('scope', isEqualTo: 'unit')
            .get();

        if (unitQuizzesSnap.docs.isNotEmpty) {
          hasUnitQuiz = true;
          for (final qDoc in unitQuizzesSnap.docs) {
            if (completedQuizzes.containsKey(qDoc.id)) {
              unitQuizCompleted = true;
              break;
            }
          }
        }

        final lessonsSnap = await _db
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
          final activitiesSnap = await _db
              .collection('content')
              .doc(contentId)
              .collection('units')
              .doc(unitId)
              .collection('lessons')
              .doc(lessonDoc.id)
              .collection('activities')
              .orderBy('order')
              .get();

          for (final actDoc in activitiesSnap.docs) {
            unitActivityIds.add(actDoc.id);
            if (completedActivities.containsKey(actDoc.id)) {
              unitActivitiesCompleted++;
            }
          }
        }

        final bool allActivitiesCompleted = unitActivityIds.isNotEmpty &&
            unitActivitiesCompleted == unitActivityIds.length;

        unitCompleted =
            hasUnitQuiz ? (allActivitiesCompleted && unitQuizCompleted) : allActivitiesCompleted;
        unitCompletedMap[unitId] = unitCompleted;

        bool isUnitUnlocked = true;
        if (previousUnitIds.isNotEmpty) {
          isUnitUnlocked = previousUnitIds.every((id) => unitCompletedMap[id] ?? false);
        }

        List<String> previousLessonIds = [];
        Map<String, bool> lessonCompletedMap = {};

        for (final lessonDoc in lessonsSnap.docs) {
          final lessonId = lessonDoc.id;
          final lessonData = lessonDoc.data();

          final activitiesSnap = await _db
              .collection('content')
              .doc(contentId)
              .collection('units')
              .doc(unitId)
              .collection('lessons')
              .doc(lessonId)
              .collection('activities')
              .orderBy('order')
              .get();

          int lessonActivitiesTotal = activitiesSnap.docs.length;
          int lessonActivitiesCompleted = 0;

          bool allPreviousLessonsCompleted = true;
          for (final prevLessonId in previousLessonIds) {
            if (!(lessonCompletedMap[prevLessonId] ?? false)) {
              allPreviousLessonsCompleted = false;
              break;
            }
          }
          final bool isLessonUnlocked = isUnitUnlocked && allPreviousLessonsCompleted;

          for (final actDoc in activitiesSnap.docs) {
            final actData = actDoc.data();
            final activityId = actDoc.id;
            final requiredActivityId = actData['requiredActivityId'];
            final isCompleted = completedActivities.containsKey(activityId);
            if (isCompleted) lessonActivitiesCompleted++;
            final stars = isCompleted ? (completedActivities[activityId]['stars'] ?? 0) : 0;

            final scheduledTimestamp = actData['scheduledDate'] as Timestamp?;
            final scheduledDate = scheduledTimestamp?.toDate();
            final bool isScheduleReady =
                scheduledDate == null || !scheduledDate.isAfter(now);

            final dueTimestamp = actData['dueDate'] as Timestamp?;
            final dueDate = dueTimestamp?.toDate();
            final bool isOverdue =
                !isCompleted && dueDate != null && dueDate.isBefore(now);

            final closeTimestamp = actData['closeDate'] as Timestamp?;
            final closeDate = closeTimestamp?.toDate();
            final bool isClosed =
                !isCompleted && closeDate != null && closeDate.isBefore(now);

            bool isPrerequisiteMet = true;
            if (requiredActivityId != null && (requiredActivityId as String).isNotEmpty) {
              isPrerequisiteMet = completedActivities.containsKey(requiredActivityId);
            }

            String status;
            String? notOpenReason;
            if (isCompleted) {
              status = 'completed';
            } else if (isClosed || isOverdue) {
              // A closed turn-in window is the strongest form of "missed
              // it" — folded into past_due rather than a separate bucket,
              // same as an ordinary overdue-but-still-open activity.
              status = 'past_due';
            } else if (!isScheduleReady) {
              status = 'not_open_yet';
              notOpenReason = 'scheduled';
            } else if (!isLessonUnlocked || !isPrerequisiteMet) {
              status = 'not_open_yet';
              notOpenReason = 'locked';
            } else if (dueDate == null) {
              status = 'later';
            } else {
              // Not overdue (checked above), so dueDay can only be today
              // or later — never before today.
              final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
              if (dueDay == today) {
                status = 'due_today';
              } else if (dueDay == tomorrow) {
                status = 'due_tomorrow';
              } else {
                status = 'later';
              }
            }

            allItems.add({
              'contentId': contentId,
              'contentTitle': contentTitle,
              'unitId': unitId,
              'unitTitle': unitData['title'] ?? 'Untitled Unit',
              'lessonId': lessonId,
              'lessonTitle': lessonData['title'] ?? 'Untitled Lesson',
              'activityId': activityId,
              'title': actData['title'] ?? 'Untitled Activity',
              'order': actData['order'] ?? 0,
              'difficulty': actData['difficulty'] ?? 'medium',
              'xpBase': actData['xpBase'] ?? 100,
              'isCompleted': isCompleted,
              'stars': stars,
              'scheduledDate': scheduledDate,
              'dueDate': dueDate,
              'closeDate': closeDate,
              'status': status,
              'notOpenReason': notOpenReason,
            });
          }

          lessonCompletedMap[lessonId] =
              lessonActivitiesTotal > 0 && lessonActivitiesCompleted == lessonActivitiesTotal;
          previousLessonIds.add(lessonId);
        }

        previousUnitIds.add(unitId);
      }
    }

    return allItems;
  }

  Future<void> updatePersonalizedActivity({
    required String groupId,
    required String contentId,
    required String unitId,
    required String lessonId,
    required String activityId,
    required String title,
    required int order,
    String? requiredActivityId,
    int? xpBase,
    String? difficulty,
    DateTime? scheduledDate,
    DateTime? dueDate,
    DateTime? closeDate,
  }) =>
      personalizedActivities(contentId, unitId, lessonId).doc(activityId).update({
        'title': title,
        'order': order,
        'requiredActivityId': requiredActivityId,
        'xpBase': xpBase ?? 100,
        'difficulty': difficulty ?? 'easy',
        // FEATURE: unlike create, this is a plain .update() call —
        // passing null here (e.g. teacher clears a previously-set date
        // via the "X" button in turn_in_widget.dart) explicitly
        // overwrites the field to null in Firestore rather than leaving
        // a stale date in place. .update() with a null VALUE still
        // writes null; it only SKIPS a key if the key is entirely
        // absent from the map, which isn't the case here since these
        // fields are always included in this call.
        'scheduledDate': scheduledDate,
        'dueDate': dueDate,
        'closeDate': closeDate,
      });

  Future<void> deletePersonalizedActivity(String groupId, String contentId, String unitId, String lessonId, String activityId) async {
    final ref = personalizedActivities(contentId, unitId, lessonId).doc(activityId);
    final doc = await ref.get();
    if (!doc.exists) return;
    final data = doc.data() as Map<String, dynamic>;
    final deletedOrder = data['order'] as int?;
    final wasEntryPoint = data['requiredActivityId'] == null;

    await ref.delete();

    if (wasEntryPoint) {
      final dependent = await personalizedActivities(contentId, unitId, lessonId)
          .where('requiredActivityId', isEqualTo: activityId)
          .limit(1)
          .get();
      if (dependent.docs.isNotEmpty) {
        await dependent.docs.first.reference.update({'requiredActivityId': null});
      }
    }

    if (deletedOrder == null) return;

    final siblingsAfter = await personalizedActivities(contentId, unitId, lessonId)
        .where('order', isGreaterThan: deletedOrder)
        .get();
    if (siblingsAfter.docs.isEmpty) return;

    final batch = _db.batch();
    for (final sibling in siblingsAfter.docs) {
      final currentOrder = (sibling.data() as Map<String, dynamic>)['order'] as int? ?? 0;
      batch.update(sibling.reference, {'order': currentOrder - 1});
    }
    await batch.commit();
  }

  Future<void> createPersonalizedTask({
    required String groupId,
    required String contentId,
    required String unitId,
    required String lessonId,
    required String activityId,
    required String taskId,
    required String type,
    required String title,
    required String question,
    required int order,
    required Map<String, dynamic> data,
  }) =>
      personalizedTasks(contentId, unitId, lessonId, activityId).doc(taskId).set({
        'type': type,
        'title': title,
        'question': question,
        'order': order,
        'data': data,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<QuerySnapshot> getPersonalizedTasks(String groupId, String contentId, String unitId, String lessonId, String activityId) =>
      personalizedTasks(contentId, unitId, lessonId, activityId).orderBy('order').get();

  Stream<QuerySnapshot> getPersonalizedTasksStream(String groupId, String contentId, String unitId, String lessonId, String activityId) =>
      personalizedTasks(contentId, unitId, lessonId, activityId).orderBy('order').snapshots();

  Future<void> updatePersonalizedTask({
    required String groupId,
    required String contentId,
    required String unitId,
    required String lessonId,
    required String activityId,
    required String taskId,
    required String type,
    required String title,
    required String question,
    required int order,
    required Map<String, dynamic> data,
  }) =>
      personalizedTasks(contentId, unitId, lessonId, activityId).doc(taskId).update({
        'type': type,
        'title': title,
        'question': question,
        'order': order,
        'data': data,
      });

  Future<void> deletePersonalizedTask(String groupId, String contentId, String unitId, String lessonId, String activityId, String taskId) async {
    final ref = personalizedTasks(contentId, unitId, lessonId, activityId).doc(taskId);
    final doc = await ref.get();
    if (!doc.exists) return;
    final deletedOrder = (doc.data() as Map<String, dynamic>)['order'] as int?;

    await ref.delete();

    if (deletedOrder == null) return;

    final siblingsAfter = await personalizedTasks(contentId, unitId, lessonId, activityId)
        .where('order', isGreaterThan: deletedOrder)
        .get();
    if (siblingsAfter.docs.isEmpty) return;

    final batch = _db.batch();
    for (final sibling in siblingsAfter.docs) {
      final currentOrder = (sibling.data() as Map<String, dynamic>)['order'] as int? ?? 0;
      batch.update(sibling.reference, {'order': currentOrder - 1});
    }
    await batch.commit();
  }

  // =========================
  // ACTIVITY TASKS
  // =========================

  Future<List<QueryDocumentSnapshot>> getActivityTasks({
    required String contentId,
    required String unitId,
    required String lessonId,
    required String activityId,
    String collectionName = 'content',
  }) async {
    final snapshot = await _db
        .collection(collectionName)
        .doc(contentId)
        .collection('units')
        .doc(unitId)
        .collection('lessons')
        .doc(lessonId)
        .collection('activities')
        .doc(activityId)
        .collection('tasks')
        .orderBy('order')
        .get();
    return snapshot.docs;
  }

  // =========================
  // MEDIA LIBRARY — one document per owner (admin/teacher), with their
  // categories nested underneath instead of every single category being
  // its own top-level document. Old shape was mediaLibrary/{categoryId}
  // flat — every category anyone created added another top-level doc to
  // the same collection. New shape:
  //   mediaLibrary/{ownerId}/categories/{categoryId}/imageItems/{imageId}
  // =========================

  CollectionReference get mediaLibrary => _db.collection('mediaLibrary');

  CollectionReference ownerCategories(String ownerId) =>
      mediaLibrary.doc(ownerId).collection('categories');

  CollectionReference categoryItems(String ownerId, String categoryId) =>
      ownerCategories(ownerId).doc(categoryId).collection('imageItems');

  Future<String> createCategory({
    required String categoryName,
    required String ownerId,
    required String ownerRole,
  }) async {
    final ref = await ownerCategories(ownerId).add({
      'categoryName': categoryName,
      'ownerId': ownerId,
      'ownerRole': ownerRole,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  // Admin categories can belong to any of up to 3 admin accounts (shared
  // pool, same as before), so listing "all admin categories" now has to
  // search across every owner's categories subcollection — a
  // collectionGroup query is exactly that, scoped by ownerRole same as
  // the old flat-collection query was.
  Stream<QuerySnapshot> getAdminCategoriesStream() => _db
      .collectionGroup('categories')
      .where('ownerRole', isEqualTo: 'admin')
      .orderBy('createdAt')
      .snapshots();

  // A teacher's own categories, by contrast, live entirely under their
  // own ownerId doc — no cross-owner search needed, so this is a plain
  // (and cheaper) subcollection query.
  Stream<QuerySnapshot> getTeacherCategoriesStream(String teacherId) =>
      ownerCategories(teacherId)
          .where('ownerRole', isEqualTo: 'teacher')
          .orderBy('createdAt')
          .snapshots();

  Future<List<Map<String, dynamic>>> getAdminCategories() async {
    try {
      final snap = await _db
          .collectionGroup('categories')
          .where('ownerRole', isEqualTo: 'admin')
          .orderBy('createdAt')
          .get();
      return snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList();
    } catch (_) { return []; }
  }

  Future<List<Map<String, dynamic>>> getTeacherCategories(String teacherId) async {
    try {
      final snap = await ownerCategories(teacherId)
          .where('ownerRole', isEqualTo: 'teacher')
          .orderBy('createdAt')
          .get();
      return snap.docs
          .map((d) => {'id': d.id, ...(d.data() as Map<String, dynamic>)})
          .toList();
    } catch (_) { return []; }
  }

  Future<void> deleteCategory(String ownerId, String categoryId) =>
      ownerCategories(ownerId).doc(categoryId).delete();

  Future<String> saveImageMetadata({
    required String ownerId,
    required String categoryId,
    required String name,
    required String imageUrl,
    required String cloudinaryPublicId,
    required String fileExtension,
  }) async {
    final isSvg = fileExtension.toLowerCase() == 'svg';
    final displayUrl = isSvg
        ? imageUrl.replaceFirst('/upload/', '/upload/f_png,w_512,h_512,q_80/')
        : imageUrl;

    final ref = await categoryItems(ownerId, categoryId).add({
      'name': name,
      'imageUrl': imageUrl,
      'displayUrl': displayUrl,
      'cloudinaryPublicId': cloudinaryPublicId,
      'format': isSvg ? 'svg' : 'png',
      'moderationStatus': 'approved',
      'isVisible': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Stream<QuerySnapshot> getImagesStream(String ownerId, String categoryId) =>
      categoryItems(ownerId, categoryId).orderBy('createdAt', descending: true).snapshots();

  Stream<int> getImagesCountStream(String ownerId, String categoryId) =>
      categoryItems(ownerId, categoryId).snapshots().map((s) => s.docs.length);

  Future<List<Map<String, dynamic>>> getImagesByCategory(String ownerId, String categoryId) async {
    try {
      final snap = await categoryItems(ownerId, categoryId).orderBy('name').get();
      return snap.docs
          .map((d) => {'id': d.id, ...(d.data() as Map<String, dynamic>)})
          .toList();
    } catch (_) { return []; }
  }

  Future<void> deleteImage(String ownerId, String categoryId, String imageId) =>
      categoryItems(ownerId, categoryId).doc(imageId).delete();

  Future<void> approveImage({required String ownerId, required String categoryId, required String imageId}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await categoryItems(ownerId, categoryId).doc(imageId).update({
      'moderationStatus': 'approved', 'isVisible': true,
      'approvedAt': FieldValue.serverTimestamp(), 'approvedBy': uid,
      'rejectedAt': null, 'rejectedBy': null,
    });
  }

  Future<void> rejectImage({required String ownerId, required String categoryId, required String imageId}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await categoryItems(ownerId, categoryId).doc(imageId).update({
      'moderationStatus': 'rejected', 'isVisible': false,
      'rejectedAt': FieldValue.serverTimestamp(), 'rejectedBy': uid,
    });
  }

  Future<int> getCategoriesCount() async => (await _db
          .collectionGroup('categories')
          .where('ownerRole', isEqualTo: 'admin')
          .get())
      .docs
      .length;

  Stream<int> getCategoriesCountStream() => _db
      .collectionGroup('categories')
      .where('ownerRole', isEqualTo: 'admin')
      .snapshots()
      .map((s) => s.docs.length);

  Future<int> getTotalImagesCount() async {
    try {
      int total = 0;
      final cats = await _db
          .collectionGroup('categories')
          .where('ownerRole', isEqualTo: 'admin')
          .get();
      for (final c in cats.docs) {
        final ownerId = c.data()['ownerId'] as String?
            ?? c.reference.parent.parent!.id;
        total += (await categoryItems(ownerId, c.id).get()).docs.length;
      }
      return total;
    } catch (_) { return 0; }
  }

  Stream<int> getImagesCountByCategoryStream(String ownerId, String categoryId) =>
      getImagesCountStream(ownerId, categoryId);

  // =========================
  // TEACHER GROUPS
  // =========================

  CollectionReference get teacherGroups => _db.collection('teacherGroups');
  Future<QuerySnapshot> getTeacherGroups(String teacherId) => teacherGroups.where('teacherId', isEqualTo: teacherId).get();
  Future<QuerySnapshot> getAllGroups() => teacherGroups.get();

  // =========================
  // LEAGUE CAMPAIGN (scope + duration + per-tier rewards, one doc per teacher)
  // =========================
  // Replaces the old per-group teacherGroups/{groupId}/leagueRewards/config —
  // a teacher configures ONE reward campaign that either targets a single
  // group or spans every group ("paralelos") they teach, not one per group.

  CollectionReference get leagueCampaigns => _db.collection('leagueCampaigns');

  Future<DocumentSnapshot> getLeagueCampaign(String teacherId) =>
      leagueCampaigns.doc(teacherId).get();

  Future<void> saveLeagueCampaign({
    required String teacherId,
    required String scope, // 'single' | 'all'
    String? groupId,
    DateTime? startDate,
    DateTime? endDate,
    required Map<String, String> rewards,
  }) {
    assert(scope == 'single' || scope == 'all', "scope must be 'single' or 'all'");
    assert(scope != 'single' || groupId != null, 'groupId is required when scope is single');
    return leagueCampaigns.doc(teacherId).set({
      'scope':     scope,
      'groupId':   scope == 'single' ? groupId : null,
      'startDate': startDate,
      'endDate':   endDate,
      'rewards':   rewards,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // =========================
  // QUIZ (unit: graded/reports/gates; lesson: ungraded XP-only check-in)
  // =========================

  CollectionReference get allQuizzes => _db.collection('quizzes');

  Future<void> _assertNoExistingQuiz({
    required String contentId,
    required String unitId,
    required String scope,
    String? lessonId,
  }) async {
    Query query = allQuizzes
        .where('contentId', isEqualTo: contentId)
        .where('unitId', isEqualTo: unitId)
        .where('scope', isEqualTo: scope);
    if (scope == 'lesson') {
      query = query.where('lessonId', isEqualTo: lessonId);
    }
    final existing = await query.limit(1).get();
    if (existing.docs.isNotEmpty) {
      throw Exception(scope == 'unit'
          ? 'This unit already has a Quiz. Edit the existing one instead of creating another.'
          : 'This lesson already has a Quiz. Edit the existing one instead of creating another.');
    }
  }

  Future<void> createQuiz({
    required String contentId,
    required String unitId,
    required String quizId,
    required String title,
    required List<Map<String, dynamic>> questions,
    required int passingScore,
    required int xpReward,
    required int maxAttempts,
    required String scope,
    String? lessonId,
  }) async {
    assert(scope == 'unit' || scope == 'lesson', "scope must be 'unit' or 'lesson'");
    assert(scope != 'lesson' || lessonId != null, 'lessonId is required when scope is lesson');

    await _assertNoExistingQuiz(
      contentId: contentId,
      unitId: unitId,
      scope: scope,
      lessonId: lessonId,
    );

    final maxXp = scope == 'unit' ? 100 : 50;
    final quizRef = allQuizzes.doc(quizId);
    final batch = _db.batch();

    batch.set(quizRef, {
      'contentId':      contentId,
      'unitId':         unitId,
      'scope':          scope,
      if (scope == 'lesson') 'lessonId': lessonId,
      'title':          title,
      'totalQuestions': questions.length,
      'passingScore':   passingScore,
      'xpReward':       xpReward.clamp(0, maxXp),
      'isGraded':       scope == 'unit',
      'maxAttempts':    maxAttempts,
      'createdAt':      FieldValue.serverTimestamp(),
    });

    for (final q in questions) {
      final qRef = quizRef.collection('questions').doc('q_${q['order']}');
      batch.set(qRef, {
        'question':     q['question'],
        'options':      q['options'],
        'correctIndex': q['correctIndex'],
        'order':        q['order'],
      });
    }
    await batch.commit();
  }

  Future<void> updateQuiz({
    required String quizId,
    required String title,
    required int passingScore,
    required int xpReward,
    required int maxAttempts,
    required List<Map<String, dynamic>> questions,
  }) async {
    final quizRef = allQuizzes.doc(quizId);

    final existing = await quizRef.get();
    final scope = existing.exists
        ? (existing.data() as Map<String, dynamic>)['scope'] as String? ?? 'unit'
        : 'unit';
    final maxXp = scope == 'unit' ? 100 : 50;

    await quizRef.update({
      'title':          title,
      'passingScore':   passingScore,
      'xpReward':       xpReward.clamp(0, maxXp),
      'maxAttempts':    maxAttempts,
      'totalQuestions': questions.length,
      'updatedAt':      FieldValue.serverTimestamp(),
    });

    final existingQuestions = await quizRef.collection('questions').get();
    final batch = _db.batch();
    for (final doc in existingQuestions.docs) {
      batch.delete(doc.reference);
    }

    for (final q in questions) {
      final qRef = quizRef.collection('questions').doc('q_${q['order']}');
      batch.set(qRef, {
        'question':     q['question'],
        'options':      q['options'],
        'correctIndex': q['correctIndex'],
        'order':        q['order'],
      });
    }

    await batch.commit();
  }

  Future<void> deleteQuiz({required String quizId}) async {
    final quizRef = allQuizzes.doc(quizId);
    final questions = await quizRef.collection('questions').get();
    final batch = _db.batch();
    for (final q in questions.docs) batch.delete(q.reference);
    batch.delete(quizRef);
    await batch.commit();
  }

  Future<QuerySnapshot> getQuizQuestions(String quizId) async {
    return allQuizzes.doc(quizId).collection('questions').orderBy('order').get();
  }

  Stream<QuerySnapshot> getQuizzesStream(String contentId, String unitId) {
    return allQuizzes
        .where('contentId', isEqualTo: contentId)
        .where('unitId', isEqualTo: unitId)
        .where('scope', isEqualTo: 'unit')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot> getLessonQuizzesStream(String contentId, String unitId, String lessonId) {
    return allQuizzes
        .where('contentId', isEqualTo: contentId)
        .where('unitId', isEqualTo: unitId)
        .where('scope', isEqualTo: 'lesson')
        .where('lessonId', isEqualTo: lessonId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<DocumentSnapshot> getQuiz(String quizId) async {
    return allQuizzes.doc(quizId).get();
  }

  Future<bool> hasStudentCompletedLessonQuiz({
    required String studentId,
    required String contentId,
    required String unitId,
    required String lessonId,
  }) async {
    try {
      final quizSnapshot = await allQuizzes
          .where('contentId', isEqualTo: contentId)
          .where('unitId', isEqualTo: unitId)
          .where('scope', isEqualTo: 'lesson')
          .where('lessonId', isEqualTo: lessonId)
          .limit(1)
          .get();

      if (quizSnapshot.docs.isEmpty) return false;

      final quizId = quizSnapshot.docs.first.id;
      final progressDoc = await studentProgress(studentId).doc(quizId).get();
      if (!progressDoc.exists) return false;

      return (progressDoc.data() as Map<String, dynamic>)['isCompleted'] as bool? ?? false;
    } catch (e) {
      debugPrint('Error checking lesson quiz completion: $e');
      return false;
    }
  }

  // =========================
  // UNIT PROGRESSION WITH LOCKING
  // =========================

  Future<bool> hasStudentCompletedUnitQuiz({
    required String studentId,
    required String contentId,
    required String unitId,
  }) async {
    try {
      final quizSnapshot = await allQuizzes
          .where('contentId', isEqualTo: contentId)
          .where('unitId', isEqualTo: unitId)
          .where('scope', isEqualTo: 'unit')
          .limit(1)
          .get();

      if (quizSnapshot.docs.isEmpty) {
        return false;
      }

      final quizDoc = quizSnapshot.docs.first;
      final quizId = quizDoc.id;

      final progressDoc = await studentProgress(studentId).doc(quizId).get();

      if (!progressDoc.exists) {
        return false;
      }

      final progressData = progressDoc.data() as Map<String, dynamic>;
      return progressData['isCompleted'] as bool? ?? false;
    } catch (e) {
      debugPrint('Error checking unit completion: $e');
      return false;
    }
  }

  Future<bool> isUnitUnlocked({
    required String studentId,
    required String contentId,
    required String unitId,
  }) async {
    try {
      final unitsSnapshot = await personalizedUnits(contentId)
          .orderBy('order')
          .get();

      if (unitsSnapshot.docs.isEmpty) {
        return false;
      }

      int unitIndex = -1;
      for (int i = 0; i < unitsSnapshot.docs.length; i++) {
        if (unitsSnapshot.docs[i].id == unitId) {
          unitIndex = i;
          break;
        }
      }

      if (unitIndex == -1) {
        return false;
      }

      if (unitIndex == 0) {
        return true;
      }

      final previousUnitId = unitsSnapshot.docs[unitIndex - 1].id;
      final isPreviousCompleted = await hasStudentCompletedUnitQuiz(
        studentId: studentId,
        contentId: contentId,
        unitId: previousUnitId,
      );

      return isPreviousCompleted;
    } catch (e) {
      debugPrint('Error checking unit unlock status: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getUnitsWithLockStatus({
    required String studentId,
    required String contentId,
  }) async {
    try {
      final unitsSnapshot = await personalizedUnits(contentId)
          .orderBy('order')
          .get();

      List<Map<String, dynamic>> result = [];

      for (int i = 0; i < unitsSnapshot.docs.length; i++) {
        final unitDoc = unitsSnapshot.docs[i];
        final unitId = unitDoc.id;
        final unitData = unitDoc.data() as Map<String, dynamic>;

        final isCompleted = await hasStudentCompletedUnitQuiz(
          studentId: studentId,
          contentId: contentId,
          unitId: unitId,
        );

        final isUnlocked = await isUnitUnlocked(
          studentId: studentId,
          contentId: contentId,
          unitId: unitId,
        );

        result.add({
          'id': unitId,
          'data': unitData,
          'isCompleted': isCompleted,
          'isUnlocked': isUnlocked,
          'order': i + 1,
        });
      }

      return result;
    } catch (e) {
      debugPrint('Error getting units with lock status: $e');
      return [];
    }
  }

  Stream<List<Map<String, dynamic>>> getUnitsWithLockStatusStream({
    required String studentId,
    required String contentId,
  }) {
    return personalizedUnits(contentId)
        .orderBy('order')
        .snapshots()
        .asyncMap((snapshot) async {
          List<Map<String, dynamic>> result = [];

          for (int i = 0; i < snapshot.docs.length; i++) {
            final doc = snapshot.docs[i];
            final unitId = doc.id;
            final data = doc.data();

            final isCompleted = await hasStudentCompletedUnitQuiz(
              studentId: studentId,
              contentId: contentId,
              unitId: unitId,
            );

            final isUnlocked = await isUnitUnlocked(
              studentId: studentId,
              contentId: contentId,
              unitId: unitId,
            );

            result.add({
              'id': unitId,
              'data': data,
              'isCompleted': isCompleted,
              'isUnlocked': isUnlocked,
              'order': i + 1,
            });
          }

          return result;
        });
  }

  Future<String?> getNextIncompleteUnit({
    required String studentId,
    required String contentId,
  }) async {
    try {
      final unitsSnapshot = await personalizedUnits(contentId)
          .orderBy('order')
          .get();

      for (final doc in unitsSnapshot.docs) {
        final unitId = doc.id;
        final isCompleted = await hasStudentCompletedUnitQuiz(
          studentId: studentId,
          contentId: contentId,
          unitId: unitId,
        );

        if (!isCompleted) {
          return unitId;
        }
      }

      return null;
    } catch (e) {
      debugPrint('Error getting next incomplete unit: $e');
      return null;
    }
  }
}