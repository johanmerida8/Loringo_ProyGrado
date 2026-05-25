import 'package:cloud_firestore/cloud_firestore.dart';

class Database {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // =========================
  // USERS
  // =========================

  CollectionReference get users => _db.collection('users');

  // -------- CREATE USER --------
  Future<void> createUser({
    required String uid,
    required String name,
    required String email,
    required String role, // 'admin', 'teacher', 'parent', 'student'
  }) async {
    // Detect admin by name
    String finalRole = role;
    final nameLower = name.toLowerCase();
    if (nameLower == 'admin' || nameLower == 'administrador') {
      // Check if there are already 3 admins
      final adminCount = await users
          .where('role', isEqualTo: 'admin')
          .get()
          .then((snapshot) => snapshot.docs.length);

      if (adminCount >= 3) {
        throw Exception('Maximum number of administrators (3) reached');
      }
      finalRole = 'admin';
    }

    return users.doc(uid).set({
      'name': name,
      'email': email,
      'role': finalRole,
      'xp': 0,
      'streak': 0,
      'language': 'Spanish',
      'state': 1,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // -------- READ USER --------
  Future<DocumentSnapshot> getUser(String uid) {
    return users.doc(uid).get();
  }

  Stream<DocumentSnapshot> getUserStream(String uid) {
    return users.doc(uid).snapshots();
  }

  // -------- UPDATE USER --------
  Future<void> updateUser({
    required String uid,
    String? name,
    String? language,
    int? xp,
    int? streak,
  }) {
    Map<String, dynamic> updates = {};
    if (name != null) updates['name'] = name;
    if (language != null) updates['language'] = language;
    if (xp != null) updates['xp'] = xp;
    if (streak != null) updates['streak'] = streak;

    return users.doc(uid).update(updates);
  }

  // =========================
  // STUDENT PROGRESS
  // =========================

  CollectionReference studentProgress(String studentId) {
    return _db.collection('students').doc(studentId).collection('progress');
  }

  CollectionReference studentAttempts(String studentId, String activityId) {
    return studentProgress(studentId).doc(activityId).collection('attempts');
  }

  // -------- SAVE ACTIVITY COMPLETION --------
  Future<int> saveActivityCompletion({
    required String studentId,
    required String activityId,
    required String contentId,
    required String unitId,
    required int score,
    required int correctAnswers,
    required int wrongAnswers,
    required int xpBase,
    required int bonusXP,
  }) async {
    final progressRef = studentProgress(studentId).doc(activityId);
    final progressDoc = await progressRef.get();

    int totalAttempts = 1;
    int bestScore = score;
    int xpEarned;
    bool isFirstCompletion = true;
    dynamic firstCompletedAt;
    final currentTimestamp = FieldValue.serverTimestamp();

    if (progressDoc.exists) {
      // Not first attempt
      final data = progressDoc.data() as Map<String, dynamic>;
      totalAttempts = (data['totalAttempts'] ?? 0) + 1;
      bestScore = score > (data['bestScore'] ?? 0) ? score : (data['bestScore'] ?? 0);
      xpEarned = 5; // Subsequent attempts get only 5 XP
      isFirstCompletion = false;
      firstCompletedAt = data['firstCompletedAt']; // Keep original first completion time
    } else {
      // First attempt - calculate XP based on score percentage
      // Perfect score (100%) gets full XP (base + bonus)
      // Lower scores get proportional XP based on base, but always get full bonus
      final scoreMultiplier = score / 100.0;
      final earnedBaseXP = (xpBase * scoreMultiplier).round();
      xpEarned = earnedBaseXP + bonusXP;
      firstCompletedAt = currentTimestamp;
    }

    // Save attempt details in subcollection FIRST
    final attemptId = 'attempt_$totalAttempts';
    await studentAttempts(studentId, activityId).doc(attemptId).set({
      'attemptNumber': totalAttempts,
      'score': score,
      'correctAnswers': correctAnswers,
      'wrongAnswers': wrongAnswers,
      'xpEarned': xpEarned,
      'completedAt': currentTimestamp,
    });

    // Update main progress document (without xpEarnedTotal)
    await progressRef.set({
      'activityId': activityId,
      'contentId': contentId,
      'unitId': unitId,
      'isCompleted': true,
      'firstCompletedAt': firstCompletedAt, // Keeps original timestamp from first attempt
      'lastCompletedAt': currentTimestamp,   // Always updates to current time
      'totalAttempts': totalAttempts,
      'bestScore': bestScore,
    });

    // Increment total XP on the student document
    await _db.collection('students').doc(studentId).update({
      'xp': FieldValue.increment(xpEarned),
    });

    print(
      'Activity $activityId completed - Attempt $totalAttempts: Score $score%, XP earned: $xpEarned',
    );

    return xpEarned;
  }

  // -------- GET STUDENT PROGRESS --------
  Future<QuerySnapshot> getStudentProgress(String studentId) {
    return studentProgress(studentId).get();
  }

  Stream<QuerySnapshot> getStudentProgressStream(String studentId) {
    return studentProgress(studentId).snapshots();
  }

  // -------- CHECK IF ACTIVITY IS COMPLETED --------
  Future<bool> isActivityCompleted(String studentId, String activityId) async {
    final doc = await studentProgress(studentId).doc(activityId).get();
    return doc.exists && (doc.data() as Map<String, dynamic>)['isCompleted'] == true;
  }

  // -------- SAVE QUIZ COMPLETION --------
  Future<void> saveQuizCompletion({
    required String studentId,
    required String quizId,
    required String contentId,
    required String unitId,
    required int score,
    required int totalQuestions,
    required int stars,
    required int xpEarned,
    bool updateBestOnly = false,
    String unitTitle = '',
    bool generateReport = false,
    String reportType = 'unit',
  }) async {
    if (updateBestOnly) {
      // Replay: only update score/stars if improved; always record last attempt
      await studentProgress(studentId).doc(quizId).update({
        'score': score,
        'stars': stars,
        'lastAttemptAt': FieldValue.serverTimestamp(),
        'attempts': FieldValue.increment(1),
      });
    } else {
      // First completion: write full record
      await studentProgress(studentId).doc(quizId).set({
        'quizId': quizId,
        'contentId': contentId,
        'unitId': unitId,
        'score': score,
        'totalQuestions': totalQuestions,
        'stars': stars,
        'xpEarned': xpEarned,
        'completedAt': FieldValue.serverTimestamp(),
        'lastAttemptAt': FieldValue.serverTimestamp(),
        'attempts': 1,
        'isCompleted': true,
      });
    }

    // Increment total XP only if there is XP to award
    if (xpEarned > 0) {
      await _db.collection('students').doc(studentId).update({
        'xp': FieldValue.increment(xpEarned),
      });
    }

    // Auto-generate report on first completion of a graded quiz
    if (generateReport && !updateBestOnly) {
      await _generateReport(
        studentId: studentId,
        contentId: contentId,
        unitId: unitId,
        unitTitle: unitTitle.isNotEmpty ? unitTitle : 'Quiz',
        quizCorrectCount: score,
        quizTotalQuestions: totalQuestions,
        quizStars: stars,
        reportType: reportType,
      );
    }
  }

  // ── Reports ──────────────────────────────────────────────────────────────

  CollectionReference reports(String studentId) {
    return _db.collection('students').doc(studentId).collection('reports');
  }

  Future<DocumentSnapshot> getReport(String studentId, String reportId) {
    return reports(studentId).doc(reportId).get();
  }

  Stream<QuerySnapshot> getReportsStream(String studentId) {
    return reports(studentId).snapshots();
  }

  /// Builds a completion report for a graded quiz (unit test or content final quiz).
  /// Triggered automatically by [saveQuizCompletion] on first completion.
  Future<void> _generateReport({
    required String studentId,
    required String contentId,
    required String unitId,
    required String unitTitle,
    required int quizCorrectCount, // raw correct-answer count
    required int quizTotalQuestions,
    required int quizStars,
    String reportType = 'unit',
  }) async {
    final quizIncorrect = quizTotalQuestions - quizCorrectCount;
    final quizPercent = quizTotalQuestions == 0
        ? 0
        : (quizCorrectCount / quizTotalQuestions * 100).round();

    // Count total activities across all lessons in this unit
    int totalActivities = 0;
    final lessonsSnap = await personalizedLessons(contentId, unitId).get();
    for (final lesson in lessonsSnap.docs) {
      final actSnap =
          await personalizedActivities(contentId, unitId, lesson.id).get();
      totalActivities += actSnap.docs.length;
    }

    // Count activities the student completed in this unit
    final progressSnap = await studentProgress(studentId).get();
    int activitiesCompleted = 0;
    for (final doc in progressSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['unitId'] == unitId &&
          data['isCompleted'] == true &&
          data.containsKey('activityId')) {
        activitiesCompleted++;
      }
    }
    final activitiesPercent = totalActivities == 0
        ? 0
        : (activitiesCompleted / totalActivities * 100).round();

    // Gather previous unit quiz percentages for trend comparison
    final prevSnap = await reports(studentId).get();
    final previousUnitScores = prevSnap.docs
        .where((d) =>
            (d.data() as Map<String, dynamic>)['unitId'] != unitId)
        .map((d) =>
            ((d.data() as Map<String, dynamic>)['quizPercent'] as int?) ?? 0)
        .toList();

    // Persist report — keyed by unitId for unit reports, contentId for content reports
    final reportKey = reportType == 'content' ? contentId : unitId;
    await reports(studentId).doc(reportKey).set({
      'reportType': reportType,
      'contentId': contentId,
      'unitId': unitId,
      'unitTitle': unitTitle,
      'quizCorrect': quizCorrectCount,
      'quizIncorrect': quizIncorrect,
      'quizTotalQuestions': quizTotalQuestions,
      'quizPercent': quizPercent,
      'activitiesCompleted': activitiesCompleted,
      'totalActivities': totalActivities,
      'activitiesPercent': activitiesPercent,
      'previousUnitScores': previousUnitScores,
      'generatedAt': FieldValue.serverTimestamp(),
    });
  }

  // =========================
  // PERSONALIZED CONTENT (TEACHER)
  // =========================

  CollectionReference get personalizedContent => _db.collection('personalizedContent');

  // -------- CREATE (TEACHER) --------
  Future<void> createPersonalizedContent({
    required String contentId,
    required String title,
    required String description,
    required String ageGroup,
    required int order,
    required String teacherId,
    List<String>? assignedTo,
    String status = 'pending',
  }) {
    return personalizedContent.doc(contentId).set({
      'teacherId': teacherId,
      'assignedTo': assignedTo ?? [],
      'title': title,
      'description': description,
      'ageGroup': ageGroup,
      'order': order,
      'status': status, // pending | approved | rejected
      'isActive': false, // set to true only when admin approves
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Assign content to groups (after admin approval)
  Future<void> assignContentToGroups({
    required String contentId,
    required List<String> groupIds,
  }) {
    return personalizedContent.doc(contentId).update({
      'assignedTo': groupIds,
      'assignedAt': FieldValue.serverTimestamp(),
    });
  }

  // -------- READ --------
  Future<QuerySnapshot> getPersonalizedContent(String groupId) {
    return personalizedContent
        .where('assignedTo', arrayContains: groupId)
        .orderBy('order')
        .get();
  }

  /// Get approved content assigned to a group
  Stream<QuerySnapshot> getPersonalizedContentStream(String groupId) {
    return personalizedContent
        .where('status', isEqualTo: 'approved')
        .where('assignedTo', arrayContains: groupId)
        .snapshots();
  }

  /// Get ALL content by a teacher (all statuses), for the teacher-level management screen
  Stream<QuerySnapshot> getTeacherContentStream(String teacherId) {
    return personalizedContent
        .where('teacherId', isEqualTo: teacherId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Get only approved content for a teacher (for teacher-level quizzes screen)
  Stream<QuerySnapshot> getTeacherApprovedContentStream(String teacherId) {
    return personalizedContent
        .where('teacherId', isEqualTo: teacherId)
        .where('status', isEqualTo: 'approved')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Assign a single group to the content's assignedTo list
  Future<void> assignContentToGroup({
    required String contentId,
    required String groupId,
  }) {
    return personalizedContent.doc(contentId).update({
      'assignedTo': FieldValue.arrayUnion([groupId]),
      'assignedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Remove a group from the content's assignedTo list
  Future<void> removeContentFromGroup({
    required String contentId,
    required String groupId,
  }) {
    return personalizedContent.doc(contentId).update({
      'assignedTo': FieldValue.arrayRemove([groupId]),
    });
  }

  /// Get pending content created by a teacher (awaiting admin review or to be assigned)
  Stream<QuerySnapshot> getPendingContentByTeacherStream(String teacherId) {
    return personalizedContent
        .where('teacherId', isEqualTo: teacherId)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Get rejected content for teacher to edit/resubmit
  Stream<QuerySnapshot> getRejectedContentStream(String teacherId) {
    return personalizedContent
        .where('teacherId', isEqualTo: teacherId)
        .where('status', isEqualTo: 'rejected')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<DocumentSnapshot> getPersonalizedContentDoc(String contentId) {
    return personalizedContent.doc(contentId).get();
  }

  Future<void> updatePersonalizedContent({
    required String contentId,
    required String title,
    required String description,
    required String ageGroup,
    required int order,
    String? status,
  }) {
    return personalizedContent.doc(contentId).update({
      'title': title,
      'description': description,
      'ageGroup': ageGroup,
      'order': order,
      if (status != null) 'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // -------- DELETE (TEACHER) --------
  Future<void> deletePersonalizedContent(String contentId) {
    return personalizedContent.doc(contentId).delete();
  }

  // -------- APPROVAL METADATA (subcollection) --------
  /// Subcollection that stores approval/rejection metadata.
  /// Main document stays clean: title, description, ageGroup, isActive,
  /// status, teacherId, order, assignedTo, createdAt, updatedAt.
  CollectionReference contentApproval(String contentId) {
    return personalizedContent.doc(contentId).collection('approval');
  }

  /// Write approval record (called by admin when approving).
  Future<void> writeContentApproved(String contentId) async {
    await personalizedContent.doc(contentId).update({
      'status': 'approved',
      'isActive': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await contentApproval(contentId).doc('record').set({
      'approvedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Write rejection record (called by admin when rejecting).
  Future<void> writeContentRejected(
      String contentId, String reason) async {
    await personalizedContent.doc(contentId).update({
      'status': 'rejected',
      'isActive': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await contentApproval(contentId).doc('record').set({
      'rejectedAt': FieldValue.serverTimestamp(),
      'reason': reason.isNotEmpty ? reason : 'No reason provided',
    });
  }

  /// Read the approval record (teacher sees rejection reason here).
  Future<DocumentSnapshot> getContentApprovalRecord(String contentId) {
    return contentApproval(contentId).doc('record').get();
  }

  // =========================
  // PERSONALIZED UNITS (TEACHER)
  // =========================

  CollectionReference personalizedUnits(String contentId) {
    return personalizedContent.doc(contentId).collection('units');
  }

  Future<void> createPersonalizedUnit({
    required String groupId,
    required String contentId,
    required String unitId,
    required String title,
    required int order,
  }) {
    return personalizedUnits(contentId).doc(unitId).set({
      'title': title,
      'order': order,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<QuerySnapshot> getPersonalizedUnits(String groupId, String contentId) {
    return personalizedUnits(contentId).orderBy('order').get();
  }

  Stream<QuerySnapshot> getPersonalizedUnitsStream(String groupId, String contentId) {
    return personalizedUnits(contentId).orderBy('order').snapshots();
  }

  Future<void> updatePersonalizedUnit({
    required String groupId,
    required String contentId,
    required String unitId,
    required String title,
    required int order,
  }) {
    return personalizedUnits(contentId).doc(unitId).update({
      'title': title,
      'order': order,
    });
  }

  Future<void> deletePersonalizedUnit(String groupId, String contentId, String unitId) {
    return personalizedUnits(contentId).doc(unitId).delete();
  }

  // =========================
  // PERSONALIZED LESSONS (TEACHER)
  // =========================

  CollectionReference personalizedLessons(String contentId, String unitId) {
    return personalizedUnits(contentId).doc(unitId).collection('lessons');
  }

  Future<void> createPersonalizedLesson({
    required String groupId,
    required String contentId,
    required String unitId,
    required String lessonId,
    required String title,
    required int order,
  }) {
    return personalizedLessons(contentId, unitId).doc(lessonId).set({
      'title': title,
      'order': order,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<QuerySnapshot> getPersonalizedLessons(String groupId, String contentId, String unitId) {
    return personalizedLessons(contentId, unitId).orderBy('order').get();
  }

  Stream<QuerySnapshot> getPersonalizedLessonsStream(String groupId, String contentId, String unitId) {
    return personalizedLessons(contentId, unitId).orderBy('order').snapshots();
  }

  Future<void> updatePersonalizedLesson({
    required String groupId,
    required String contentId,
    required String unitId,
    required String lessonId,
    required String title,
    required int order,
  }) {
    return personalizedLessons(contentId, unitId).doc(lessonId).update({
      'title': title,
      'order': order,
    });
  }

  Future<void> deletePersonalizedLesson(String groupId, String contentId, String unitId, String lessonId) {
    return personalizedLessons(contentId, unitId).doc(lessonId).delete();
  }

  // =========================
  // PERSONALIZED ACTIVITIES (TEACHER)
  // =========================

  CollectionReference personalizedActivities(String contentId, String unitId, String lessonId) {
    return personalizedLessons(contentId, unitId).doc(lessonId).collection('activities');
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
  }) {
    return personalizedActivities(contentId, unitId, lessonId).doc(activityId).set({
      'title': title,
      'order': order,
      'requiredActivityId': requiredActivityId,
      'xpBase': xpBase ?? 100,
      'difficulty': difficulty ?? 'easy',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<QuerySnapshot> getPersonalizedActivities(String groupId, String contentId, String unitId, String lessonId) {
    return personalizedActivities(contentId, unitId, lessonId).orderBy('order').get();
  }

  Stream<QuerySnapshot> getPersonalizedActivitiesStream(String groupId, String contentId, String unitId, String lessonId) {
    return personalizedActivities(contentId, unitId, lessonId).orderBy('order').snapshots();
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
  }) {
    return personalizedActivities(contentId, unitId, lessonId).doc(activityId).update({
      'title': title,
      'order': order,
      'requiredActivityId': requiredActivityId,
      'xpBase': xpBase ?? 100,
      'difficulty': difficulty ?? 'easy',
    });
  }

  Future<void> deletePersonalizedActivity(String groupId, String contentId, String unitId, String lessonId, String activityId) {
    return personalizedActivities(contentId, unitId, lessonId).doc(activityId).delete();
  }

  // =========================
  // PERSONALIZED TASKS (TEACHER)
  // =========================

  CollectionReference personalizedTasks(String contentId, String unitId, String lessonId, String activityId) {
    return personalizedActivities(contentId, unitId, lessonId).doc(activityId).collection('tasks');
  }

  Future<void> createPersonalizedTask({
    required String groupId,
    required String contentId,
    required String unitId,
    required String lessonId,
    required String activityId,
    required String taskId,
    required String type,
    required String question,
    required int order,
    required Map<String, dynamic> data,
  }) {
    return personalizedTasks(contentId, unitId, lessonId, activityId).doc(taskId).set({
      'type': type,
      'question': question,
      'order': order,
      'data': data,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<QuerySnapshot> getPersonalizedTasks(String groupId, String contentId, String unitId, String lessonId, String activityId) {
    return personalizedTasks(contentId, unitId, lessonId, activityId).orderBy('order').get();
  }

  Stream<QuerySnapshot> getPersonalizedTasksStream(String groupId, String contentId, String unitId, String lessonId, String activityId) {
    return personalizedTasks(contentId, unitId, lessonId, activityId).orderBy('order').snapshots();
  }

  Future<void> updatePersonalizedTask({
    required String groupId,
    required String contentId,
    required String unitId,
    required String lessonId,
    required String activityId,
    required String taskId,
    required String type,
    required String question,
    required int order,
    required Map<String, dynamic> data,
  }) {
    return personalizedTasks(contentId, unitId, lessonId, activityId).doc(taskId).update({
      'type': type,
      'question': question,
      'order': order,
      'data': data,
    });
  }

  Future<void> deletePersonalizedTask(String groupId, String contentId, String unitId, String lessonId, String activityId, String taskId) {
    return personalizedTasks(contentId, unitId, lessonId, activityId).doc(taskId).delete();
  }

    // =========================
  // IMAGE CATEGORIES & MANAGEMENT (ADMIN)
  // =========================

  CollectionReference get imageCategories => _db.collection('image_categories');

  // -------- GET CATEGORIES COUNT --------
  Future<int> getCategoriesCount() async {
    final snapshot = await imageCategories.get();
    return snapshot.docs.length;
  }

  Stream<int> getCategoriesCountStream() {
    return imageCategories.snapshots().map((snapshot) => snapshot.docs.length);
  }

  // -------- GET TOTAL IMAGES COUNT --------
  Future<int> getTotalImagesCount() async {
    try {
      int totalImages = 0;
      final categories = await imageCategories.get();

      for (var categoryDoc in categories.docs) {
        final imagesSnapshot = await imageCategories
            .doc(categoryDoc.id)
            .collection('images')
            .get();
        totalImages += imagesSnapshot.docs.length;
      }

      return totalImages;
    } catch (e) {
      print('Error counting images: $e');
      return 0;
    }
  }

  // -------- GET CATEGORIES LIST --------
  Stream<QuerySnapshot> getCategoriesStream() {
    return imageCategories.snapshots();
  }

  Future<QuerySnapshot> getCategories() {
    return imageCategories.get();
  }

  // -------- GET IMAGES BY CATEGORY --------
  Future<int> getImagesCountByCategory(String categoryId) async {
    final snapshot = await imageCategories
        .doc(categoryId)
        .collection('images')
        .get();
    return snapshot.docs.length;
  }

  Stream<int> getImagesCountByCategoryStream(String categoryId) {
    return imageCategories
        .doc(categoryId)
        .collection('images')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // -------- CONTENT APPROVAL STATS --------
  /// Get count of approved content across all groups
  Stream<int> getApprovedContentCountStream() async* {
    try {
      final approvedSnapshot = await _db
          .collection('personalizedContent')
          .where('status', isEqualTo: 'approved')
          .get();

      yield approvedSnapshot.docs.length;
    } catch (e) {
      print('Error counting approved content: $e');
      yield 0;
    }
  }

  /// Get count of pending content (assigned to groups, waiting for approval)
  Stream<int> getPendingContentCountStream() async* {
    try {
      final pendingSnapshot = await _db
          .collection('personalizedContent')
          .where('status', isEqualTo: 'pending')
          .get();

      yield pendingSnapshot.docs.length;
    } catch (e) {
      print('Error counting pending content: $e');
      yield 0;
    }
  }

  // =========================
  // TEACHER GROUPS
  // =========================

  CollectionReference get teacherGroups => _db.collection('teacherGroups');

  /// Get all groups for a teacher
  Future<QuerySnapshot> getTeacherGroups(String teacherId) {
    return teacherGroups
        .where('teacherId', isEqualTo: teacherId)
        .get();
  }

  /// Get all groups (for admin to auto-assign)
  Future<QuerySnapshot> getAllGroups() {
    return teacherGroups.get();
  }

  // =========================
  // PERSONALIZED QUIZZES (TEACHER)
  // =========================

  CollectionReference personalizedLessonQuizzes(
    String contentId,
    String unitId,
    String lessonId,
  ) {
    return personalizedLessons(contentId, unitId)
        .doc(lessonId)
        .collection('quizzes');
  }

  CollectionReference personalizedUnitQuizzes(
    String contentId,
    String unitId,
  ) {
    return personalizedUnits(contentId).doc(unitId).collection('quizzes');
  }

  /// Creates a lesson practice quiz (not graded). xpReward is clamped to 0–10.
  Future<void> createPersonalizedLessonQuiz({
    required String contentId,
    required String unitId,
    required String lessonId,
    required String quizId,
    required String title,
    required List<String> questionIds,
    required int xpReward,
  }) {
    return personalizedLessonQuizzes(contentId, unitId, lessonId)
        .doc(quizId)
        .set({
      'title': title,
      'questionIds': questionIds,
      'type': 'lesson_quiz',
      'isGraded': false,
      'passingScore': 0,
      'xpReward': xpReward.clamp(0, 10),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Creates a graded unit test quiz.
  Future<void> createPersonalizedUnitQuiz({
    required String contentId,
    required String unitId,
    required String quizId,
    required String title,
    required List<String> questionIds,
    required int passingScore,
    required int xpReward,
  }) {
    return personalizedUnitQuizzes(contentId, unitId).doc(quizId).set({
      'title': title,
      'questionIds': questionIds,
      'type': 'unit_test',
      'isGraded': true,
      'passingScore': passingScore, // number of correct questions required
      'xpReward': xpReward.clamp(0, 100),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> getPersonalizedLessonQuizzesStream(
    String contentId,
    String unitId,
    String lessonId,
  ) {
    return personalizedLessonQuizzes(contentId, unitId, lessonId).snapshots();
  }

  Stream<QuerySnapshot> getPersonalizedUnitQuizzesStream(
    String contentId,
    String unitId,
  ) {
    return personalizedUnitQuizzes(contentId, unitId).snapshots();
  }

  Future<void> deletePersonalizedLessonQuiz({
    required String contentId,
    required String unitId,
    required String lessonId,
    required String quizId,
  }) {
    return personalizedLessonQuizzes(contentId, unitId, lessonId)
        .doc(quizId)
        .delete();
  }

  Future<void> deletePersonalizedUnitQuiz({
    required String contentId,
    required String unitId,
    required String quizId,
  }) {
    return personalizedUnitQuizzes(contentId, unitId).doc(quizId).delete();
  }

  Future<void> updatePersonalizedLessonQuiz({
    required String contentId,
    required String unitId,
    required String lessonId,
    required String quizId,
    required String title,
    required int xpReward,
  }) {
    return personalizedLessonQuizzes(contentId, unitId, lessonId)
        .doc(quizId)
        .update({
      'title': title,
      'xpReward': xpReward.clamp(0, 10),
    });
  }

  Future<void> updatePersonalizedUnitQuiz({
    required String contentId,
    required String unitId,
    required String quizId,
    required String title,
    required int passingScore,
    required int xpReward,
  }) {
    return personalizedUnitQuizzes(contentId, unitId).doc(quizId).update({
      'title': title,
      'passingScore': passingScore,
      'xpReward': xpReward.clamp(0, 100),
    });
  }
}
