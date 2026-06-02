import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:loringo_app/screens/admin/admin_approval_content_screen.dart';
// import 'package:loringo_app/screens/admin/content_approval_screen.dart';

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

  Future<int> saveActivityCompletion({
    required String studentId, required String activityId,
    required String contentId, required String unitId,
    required int score, required int correctAnswers,
    required int wrongAnswers, required int xpBase, required int bonusXP,
  }) async {
    final progressRef = studentProgress(studentId).doc(activityId);
    final progressDoc = await progressRef.get();
    int totalAttempts = 1, bestScore = score, xpEarned;
    dynamic firstCompletedAt;
    final now = FieldValue.serverTimestamp();

    if (progressDoc.exists) {
      final data = progressDoc.data() as Map<String, dynamic>;
      totalAttempts = (data['totalAttempts'] ?? 0) + 1;
      bestScore = score > (data['bestScore'] ?? 0) ? score : (data['bestScore'] ?? 0);
      xpEarned = 5;
      firstCompletedAt = data['firstCompletedAt'];
    } else {
      xpEarned = (xpBase * score / 100.0).round() + bonusXP;
      firstCompletedAt = now;
    }

    await studentAttempts(studentId, activityId).doc('attempt_$totalAttempts').set({
      'attemptNumber': totalAttempts, 'score': score,
      'correctAnswers': correctAnswers, 'wrongAnswers': wrongAnswers,
      'xpEarned': xpEarned, 'completedAt': now,
    });
    await progressRef.set({
      'activityId': activityId, 'contentId': contentId, 'unitId': unitId,
      'isCompleted': true, 'firstCompletedAt': firstCompletedAt,
      'lastCompletedAt': now, 'totalAttempts': totalAttempts, 'bestScore': bestScore,
    });
    await _db.collection('students').doc(studentId).update({'xp': FieldValue.increment(xpEarned)});
    return xpEarned;
  }

  Future<QuerySnapshot> getStudentProgress(String studentId) => studentProgress(studentId).get();
  Stream<QuerySnapshot> getStudentProgressStream(String studentId) => studentProgress(studentId).snapshots();

  Future<bool> isActivityCompleted(String studentId, String activityId) async {
    final doc = await studentProgress(studentId).doc(activityId).get();
    return doc.exists && (doc.data() as Map<String, dynamic>)['isCompleted'] == true;
  }

  Future<void> saveQuizCompletion({
    required String studentId, required String quizId,
    required String contentId, required String unitId,
    required int score, required int totalQuestions,
    required int stars, required int xpEarned,
    bool updateBestOnly = false, String unitTitle = '',
    bool generateReport = false, String reportType = 'unit',
  }) async {
    if (updateBestOnly) {
      await studentProgress(studentId).doc(quizId).update({
        'score': score, 'stars': stars,
        'lastAttemptAt': FieldValue.serverTimestamp(), 'attempts': FieldValue.increment(1),
      });
    } else {
      await studentProgress(studentId).doc(quizId).set({
        'quizId': quizId, 'contentId': contentId, 'unitId': unitId,
        'score': score, 'totalQuestions': totalQuestions, 'stars': stars,
        'xpEarned': xpEarned, 'completedAt': FieldValue.serverTimestamp(),
        'lastAttemptAt': FieldValue.serverTimestamp(), 'attempts': 1, 'isCompleted': true,
      });
    }
    if (xpEarned > 0) await _db.collection('students').doc(studentId).update({'xp': FieldValue.increment(xpEarned)});
    if (generateReport && !updateBestOnly) {
      await _generateReport(studentId: studentId, contentId: contentId, unitId: unitId,
        unitTitle: unitTitle.isNotEmpty ? unitTitle : 'Quiz', quizCorrectCount: score,
        quizTotalQuestions: totalQuestions, quizStars: stars, reportType: reportType);
    }
  }

  CollectionReference reports(String studentId) => _db.collection('students').doc(studentId).collection('reports');
  Future<DocumentSnapshot> getReport(String studentId, String reportId) => reports(studentId).doc(reportId).get();
  Stream<QuerySnapshot> getReportsStream(String studentId) => reports(studentId).snapshots();

  Future<void> _generateReport({
    required String studentId, required String contentId, required String unitId,
    required String unitTitle, required int quizCorrectCount,
    required int quizTotalQuestions, required int quizStars, String reportType = 'unit',
  }) async {
    final quizPercent = quizTotalQuestions == 0 ? 0 : (quizCorrectCount / quizTotalQuestions * 100).round();
    int totalActivities = 0;
    final lessonsSnap = await personalizedLessons(contentId, unitId).get();
    for (final l in lessonsSnap.docs) {
      totalActivities += (await personalizedActivities(contentId, unitId, l.id).get()).docs.length;
    }
    final progressSnap = await studentProgress(studentId).get();
    int activitiesCompleted = 0;
    for (final doc in progressSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['unitId'] == unitId && data['isCompleted'] == true && data.containsKey('activityId')) activitiesCompleted++;
    }
    final prevSnap = await reports(studentId).get();
    final previousUnitScores = prevSnap.docs
      .where((d) => (d.data() as Map<String, dynamic>)['unitId'] != unitId)
      .map((d) => ((d.data() as Map<String, dynamic>)['quizPercent'] as int?) ?? 0).toList();
    await reports(studentId).doc(reportType == 'content' ? contentId : unitId).set({
      'reportType': reportType, 'contentId': contentId, 'unitId': unitId, 'unitTitle': unitTitle,
      'quizCorrect': quizCorrectCount, 'quizIncorrect': quizTotalQuestions - quizCorrectCount,
      'quizTotalQuestions': quizTotalQuestions, 'quizPercent': quizPercent,
      'activitiesCompleted': activitiesCompleted, 'totalActivities': totalActivities,
      'activitiesPercent': totalActivities == 0 ? 0 : (activitiesCompleted / totalActivities * 100).round(),
      'previousUnitScores': previousUnitScores, 'generatedAt': FieldValue.serverTimestamp(),
    });
  }

  // =========================
  // PERSONALIZED CONTENT
  // =========================

  CollectionReference get personalizedContent => _db.collection('content');

  Future<void> createPersonalizedContent({required String contentId, required String title, required String description, required String ageGroup, required int order, required String teacherId, List<String>? assignedTo, String status = 'pending'}) =>
      personalizedContent.doc(contentId).set({'teacherId': teacherId, 'assignedTo': assignedTo ?? [], 'title': title, 'description': description, 'ageGroup': ageGroup, 'order': order, 'status': status, 'isActive': false, 'createdAt': FieldValue.serverTimestamp()});

  Future<void> assignContentToGroups({required String contentId, required List<String> groupIds}) =>
      personalizedContent.doc(contentId).update({'assignedTo': groupIds, 'assignedAt': FieldValue.serverTimestamp()});
  Future<QuerySnapshot> getPersonalizedContent(String groupId) =>
      personalizedContent.where('assignedTo', arrayContains: groupId).orderBy('order').get();
  Stream<QuerySnapshot> getPersonalizedContentStream(String groupId) =>
      personalizedContent.where('status', isEqualTo: 'approved').where('assignedTo', arrayContains: groupId).snapshots();
  Stream<QuerySnapshot> getTeacherContentStream(String teacherId) =>
      personalizedContent.where('teacherId', isEqualTo: teacherId).orderBy('createdAt', descending: true).snapshots();
  Stream<QuerySnapshot> getTeacherApprovedContentStream(String teacherId) =>
      personalizedContent.where('teacherId', isEqualTo: teacherId).where('status', isEqualTo: 'approved').orderBy('createdAt', descending: true).snapshots();
  Future<void> assignContentToGroup({required String contentId, required String groupId}) =>
      personalizedContent.doc(contentId).update({'assignedTo': FieldValue.arrayUnion([groupId]), 'assignedAt': FieldValue.serverTimestamp()});
  Future<void> removeContentFromGroup({required String contentId, required String groupId}) =>
      personalizedContent.doc(contentId).update({'assignedTo': FieldValue.arrayRemove([groupId])});
  Stream<QuerySnapshot> getPendingContentByTeacherStream(String teacherId) =>
      personalizedContent.where('teacherId', isEqualTo: teacherId).where('status', isEqualTo: 'pending').orderBy('createdAt', descending: true).snapshots();
  Stream<QuerySnapshot> getRejectedContentStream(String teacherId) =>
      personalizedContent.where('teacherId', isEqualTo: teacherId).where('status', isEqualTo: 'rejected').orderBy('createdAt', descending: true).snapshots();
  Future<DocumentSnapshot> getPersonalizedContentDoc(String contentId) => personalizedContent.doc(contentId).get();
  Future<void> updatePersonalizedContent({required String contentId, required String title, required String description, required String ageGroup, required int order, String? status}) =>
      personalizedContent.doc(contentId).update({'title': title, 'description': description, 'ageGroup': ageGroup, 'order': order, if (status != null) 'status': status, 'updatedAt': FieldValue.serverTimestamp()});
  Future<void> deletePersonalizedContent(String contentId) => personalizedContent.doc(contentId).delete();

  CollectionReference contentApproval(String contentId) => personalizedContent.doc(contentId).collection('approval');
  Future<void> writeContentApproved(String contentId) async {
    await personalizedContent.doc(contentId).update({'status': 'approved', 'isActive': true, 'updatedAt': FieldValue.serverTimestamp()});
    await contentApproval(contentId).doc('record').set({'approvedAt': FieldValue.serverTimestamp()});
  }
  Future<void> writeContentRejected(String contentId, String reason) async {
    await personalizedContent.doc(contentId).update({'status': 'rejected', 'isActive': false, 'updatedAt': FieldValue.serverTimestamp()});
    await contentApproval(contentId).doc('record').set({'rejectedAt': FieldValue.serverTimestamp(), 'reason': reason.isNotEmpty ? reason : 'No reason provided'});
  }
  Future<DocumentSnapshot> getContentApprovalRecord(String contentId) => contentApproval(contentId).doc('record').get();

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
  Future<void> deletePersonalizedUnit(String groupId, String contentId, String unitId) => personalizedUnits(contentId).doc(unitId).delete();

  Future<void> createPersonalizedLesson({required String groupId, required String contentId, required String unitId, required String lessonId, required String title, required int order}) =>
      personalizedLessons(contentId, unitId).doc(lessonId).set({'title': title, 'order': order, 'createdAt': FieldValue.serverTimestamp()});
  Future<QuerySnapshot> getPersonalizedLessons(String groupId, String contentId, String unitId) => personalizedLessons(contentId, unitId).orderBy('order').get();
  Stream<QuerySnapshot> getPersonalizedLessonsStream(String groupId, String contentId, String unitId) => personalizedLessons(contentId, unitId).orderBy('order').snapshots();
  Future<void> updatePersonalizedLesson({required String groupId, required String contentId, required String unitId, required String lessonId, required String title, required int order}) =>
      personalizedLessons(contentId, unitId).doc(lessonId).update({'title': title, 'order': order});
  Future<void> deletePersonalizedLesson(String groupId, String contentId, String unitId, String lessonId) => personalizedLessons(contentId, unitId).doc(lessonId).delete();

  Future<void> createPersonalizedActivity({required String groupId, required String contentId, required String unitId, required String lessonId, required String activityId, required String title, required int order, String? requiredActivityId, int? xpBase, String? difficulty}) =>
      personalizedActivities(contentId, unitId, lessonId).doc(activityId).set({'title': title, 'order': order, 'requiredActivityId': requiredActivityId, 'xpBase': xpBase ?? 100, 'difficulty': difficulty ?? 'easy', 'createdAt': FieldValue.serverTimestamp()});
  Future<QuerySnapshot> getPersonalizedActivities(String groupId, String contentId, String unitId, String lessonId) => personalizedActivities(contentId, unitId, lessonId).orderBy('order').get();
  Stream<QuerySnapshot> getPersonalizedActivitiesStream(String groupId, String contentId, String unitId, String lessonId) => personalizedActivities(contentId, unitId, lessonId).orderBy('order').snapshots();
  Future<void> updatePersonalizedActivity({required String groupId, required String contentId, required String unitId, required String lessonId, required String activityId, required String title, required int order, String? requiredActivityId, int? xpBase, String? difficulty}) =>
      personalizedActivities(contentId, unitId, lessonId).doc(activityId).update({'title': title, 'order': order, 'requiredActivityId': requiredActivityId, 'xpBase': xpBase ?? 100, 'difficulty': difficulty ?? 'easy'});
  Future<void> deletePersonalizedActivity(String groupId, String contentId, String unitId, String lessonId, String activityId) => personalizedActivities(contentId, unitId, lessonId).doc(activityId).delete();

  Future<void> createPersonalizedTask({required String groupId, required String contentId, required String unitId, required String lessonId, required String activityId, required String taskId, required String type, required String question, required int order, required Map<String, dynamic> data}) =>
      personalizedTasks(contentId, unitId, lessonId, activityId).doc(taskId).set({'type': type, 'question': question, 'order': order, 'data': data, 'createdAt': FieldValue.serverTimestamp()});
  Future<QuerySnapshot> getPersonalizedTasks(String groupId, String contentId, String unitId, String lessonId, String activityId) => personalizedTasks(contentId, unitId, lessonId, activityId).orderBy('order').get();
  Stream<QuerySnapshot> getPersonalizedTasksStream(String groupId, String contentId, String unitId, String lessonId, String activityId) => personalizedTasks(contentId, unitId, lessonId, activityId).orderBy('order').snapshots();
  Future<void> updatePersonalizedTask({required String groupId, required String contentId, required String unitId, required String lessonId, required String activityId, required String taskId, required String type, required String question, required int order, required Map<String, dynamic> data}) =>
      personalizedTasks(contentId, unitId, lessonId, activityId).doc(taskId).update({'type': type, 'question': question, 'order': order, 'data': data});
  Future<void> deletePersonalizedTask(String groupId, String contentId, String unitId, String lessonId, String activityId, String taskId) =>
      personalizedTasks(contentId, unitId, lessonId, activityId).doc(taskId).delete();

  // =========================
  // MEDIA LIBRARY — unified collection for admin + teachers
  // =========================
  //

  // ── Collection refs ───────────────────────────────────────────────────────

  /// Root collection ref — replaces old 'image_categories'
  CollectionReference get mediaLibrary => _db.collection('mediaLibrary');

  /// imageItems subcollection inside a category — replaces old 'images'
  CollectionReference categoryItems(String categoryId) =>
      mediaLibrary.doc(categoryId).collection('imageItems');

  // ── Category CRUD ─────────────────────────────────────────────────────────

  /// Create a category for admin or teacher.
  Future<String> createCategory({
    required String categoryName,
    required String ownerId,
    required String ownerRole, // 'admin' | 'teacher'
  }) async {
    final ref = await mediaLibrary.add({
      'categoryName': categoryName,
      'ownerId': ownerId,
      'ownerRole': ownerRole,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Stream of admin categories (public — all users see these).
  Stream<QuerySnapshot> getAdminCategoriesStream() =>
      mediaLibrary.where('ownerRole', isEqualTo: 'admin').orderBy('createdAt').snapshots();

  /// Stream of a specific teacher's private categories.
  Stream<QuerySnapshot> getTeacherCategoriesStream(String teacherId) =>
      mediaLibrary
          .where('ownerId', isEqualTo: teacherId)
          .where('ownerRole', isEqualTo: 'teacher')
          .orderBy('createdAt')
          .snapshots();

  /// One-time fetch of admin categories (used by SelectImageDialog).
  Future<List<Map<String, dynamic>>> getAdminCategories() async {
    try {
      final snap = await mediaLibrary
          .where('ownerRole', isEqualTo: 'admin')
          .orderBy('createdAt')
          .get();
      return snap.docs
          .map((d) => {'id': d.id, ...(d.data() as Map<String, dynamic>)})
          .toList();
    } catch (_) { return []; }
  }

  /// One-time fetch of a teacher's own categories (used by SelectImageDialog).
  Future<List<Map<String, dynamic>>> getTeacherCategories(String teacherId) async {
    try {
      final snap = await mediaLibrary
          .where('ownerId', isEqualTo: teacherId)
          .where('ownerRole', isEqualTo: 'teacher')
          .orderBy('createdAt')
          .get();
      return snap.docs
          .map((d) => {'id': d.id, ...(d.data() as Map<String, dynamic>)})
          .toList();
    } catch (_) { return []; }
  }

  /// Delete a category document only — imageItems must be deleted by caller first.
  Future<void> deleteCategory(String categoryId) =>
      mediaLibrary.doc(categoryId).delete();

  // ── ImageItem CRUD ────────────────────────────────────────────────────────

  /// Save image metadata after a successful Cloudinary + Vision upload.
  /// Works for both admin and teacher — same subcollection structure.
  Future<String> saveImageMetadata({
    required String categoryId,
    required String name,
    required String imageUrl,
    required String cloudinaryPublicId,
    required String fileExtension, // 'png' or 'svg'
  }) async {
    final isSvg = fileExtension.toLowerCase() == 'svg';
    // SVG files: ask Cloudinary to serve as PNG so Flutter Image.network renders correctly
    final displayUrl = isSvg
        ? imageUrl.replaceFirst('/upload/', '/upload/f_png,w_512,h_512,q_80/')
        : imageUrl;

    final ref = await categoryItems(categoryId).add({
      'name': name,
      'imageUrl': imageUrl,
      'displayUrl': displayUrl,
      'cloudinaryPublicId': cloudinaryPublicId,
      'format': isSvg ? 'svg' : 'png',
      'moderationStatus': 'approved', // Google Vision checked before upload
      'isVisible': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Real-time stream of imageItems in a category (newest first).
  Stream<QuerySnapshot> getImagesStream(String categoryId) =>
      categoryItems(categoryId).orderBy('createdAt', descending: true).snapshots();

  /// Live count for category list badges.
  Stream<int> getImagesCountStream(String categoryId) =>
      categoryItems(categoryId).snapshots().map((s) => s.docs.length);

  /// One-time fetch of all imageItems in a category.
  Future<List<Map<String, dynamic>>> getImagesByCategory(String categoryId) async {
    try {
      final snap = await categoryItems(categoryId).orderBy('name').get();
      return snap.docs
          .map((d) => {'id': d.id, ...(d.data() as Map<String, dynamic>)})
          .toList();
    } catch (_) { return []; }
  }

  /// Delete a single imageItem document. Cloudinary deletion handled by caller.
  Future<void> deleteImage(String categoryId, String imageId) =>
      categoryItems(categoryId).doc(imageId).delete();

  // Admin moderation helpers
  Future<void> approveImage({required String categoryId, required String imageId}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await categoryItems(categoryId).doc(imageId).update({
      'moderationStatus': 'approved', 'isVisible': true,
      'approvedAt': FieldValue.serverTimestamp(), 'approvedBy': uid,
      'rejectedAt': null, 'rejectedBy': null,
    });
  }

  Future<void> rejectImage({required String categoryId, required String imageId}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await categoryItems(categoryId).doc(imageId).update({
      'moderationStatus': 'rejected', 'isVisible': false,
      'rejectedAt': FieldValue.serverTimestamp(), 'rejectedBy': uid,
    });
  }

  // ── Admin dashboard stats ─────────────────────────────────────────────────

  Future<int> getCategoriesCount() async =>
      (await mediaLibrary.where('ownerRole', isEqualTo: 'admin').get()).docs.length;

  Stream<int> getCategoriesCountStream() =>
      mediaLibrary.where('ownerRole', isEqualTo: 'admin').snapshots().map((s) => s.docs.length);

  Future<int> getTotalImagesCount() async {
    try {
      int total = 0;
      final cats = await mediaLibrary.where('ownerRole', isEqualTo: 'admin').get();
      for (final c in cats.docs) {
        total += (await categoryItems(c.id).get()).docs.length;
      }
      return total;
    } catch (_) { return 0; }
  }

  Stream<int> getImagesCountByCategoryStream(String categoryId) =>
      getImagesCountStream(categoryId);


  /// Stream of all pending content with teacher names resolved.
  /// Used by ContentApprovalScreen — replaces the old inline _getPendingContent().
  /// Re-emits every time the 'content' collection changes so the list stays live.
  Stream<List<PendingContent>> getPendingContentStream() {
    return personalizedContent
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
      final result = <PendingContent>[];
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final teacherId = data['teacherId'] as String?;

        // Resolve teacher name from users collection
        String teacherName = 'Unknown';
        if (teacherId != null) {
          try {
            final teacherDoc = await users.doc(teacherId).get();
            if (teacherDoc.exists) {
              teacherName = (teacherDoc.data() as Map<String, dynamic>)['name'] as String? ?? 'Unknown';
            }
          } catch (_) {}
        }

        final createdAt = data['createdAt'] as Timestamp?;
        result.add(PendingContent(
          contentId: doc.id,
          title: data['title'] as String? ?? 'Untitled',
          description: data['description'] as String? ?? 'No description',
          ageGroup: data['ageGroup'] as String? ?? '5-6 years',
          teacherName: teacherName,
          status: data['status'] as String? ?? 'pending',
          createdAt: createdAt != null ? _formatDate(createdAt.toDate()) : 'Unknown',
        ));
      }
      return result;
    });
  }

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  // =========================
  // CONTENT APPROVAL STATS (ADMIN)
  // =========================

  Stream<int> getApprovedContentCountStream() async* {
    try { yield (await _db.collection('content').where('status', isEqualTo: 'approved').get()).docs.length; }
    catch (_) { yield 0; }
  }
  Stream<int> getPendingContentCountStream() async* {
    try { yield (await _db.collection('content').where('status', isEqualTo: 'pending').get()).docs.length; }
    catch (_) { yield 0; }
  }

  // =========================
  // TEACHER GROUPS
  // =========================

  CollectionReference get teacherGroups => _db.collection('teacherGroups');
  Future<QuerySnapshot> getTeacherGroups(String teacherId) => teacherGroups.where('teacherId', isEqualTo: teacherId).get();
  Future<QuerySnapshot> getAllGroups() => teacherGroups.get();

  // =========================
  // ROOT QUIZZES COLLECTION
  // =========================

  CollectionReference get allQuizzes => _db.collection('quizzes');

  // ----------------------------------------------------------------------
  // UNIT QUIZ (graded, teacher creates multiple‑choice questions)
  // ----------------------------------------------------------------------
  Future<void> createPersonalizedUnitQuiz({
    required String contentId,
    required String unitId,
    required String quizId,
    required String title,
    required List<Map<String, dynamic>> questions,
    required int passingScore,
    required int xpReward,
  }) async {
    final quizRef = allQuizzes.doc(quizId);
    final batch = _db.batch();

    // 1. Quiz header
    batch.set(quizRef, {
      'type':           'unit',
      'contentId':      contentId,
      'unitId':         unitId,
      'title':          title,
      'totalQuestions': questions.length,
      'passingScore':   passingScore,
      'xpReward':       xpReward.clamp(0, 100),
      'isGraded':       true,
      'createdAt':      FieldValue.serverTimestamp(),
    });

    // 2. Questions as subcollection
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

  Future<void> updatePersonalizedUnitQuiz({
    required String quizId,   // now we only need quizId, not contentId/unitId
    required String title,
    required int passingScore,
    required int xpReward,
  }) async {
    await allQuizzes.doc(quizId).update({
      'title':        title,
      'passingScore': passingScore,
      'xpReward':     xpReward.clamp(0, 100),
      'updatedAt':    FieldValue.serverTimestamp(),
    });
  }

  Future<void> deletePersonalizedUnitQuiz({required String quizId}) async {
    final quizRef = allQuizzes.doc(quizId);
    // Delete questions subcollection
    final questions = await quizRef.collection('questions').get();
    final batch = _db.batch();
    for (final q in questions.docs) batch.delete(q.reference);
    batch.delete(quizRef);
    await batch.commit();
  }

  Future<QuerySnapshot> getUnitQuizQuestions(String quizId) async {
    return allQuizzes.doc(quizId).collection('questions').orderBy('order').get();
  }

  Stream<QuerySnapshot> getUnitQuizzesStream(String contentId, String unitId) {
    return allQuizzes
        .where('type', isEqualTo: 'unit')
        .where('contentId', isEqualTo: contentId)
        .where('unitId', isEqualTo: unitId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<DocumentSnapshot> getPersonalizedUnitQuiz(String quizId) async {
    return allQuizzes.doc(quizId).get();
  }

  // ----------------------------------------------------------------------
  // LESSON QUIZ (practice, reuses activity tasks)
  // ----------------------------------------------------------------------
  Future<void> createPersonalizedLessonQuiz({
    required String contentId,
    required String unitId,
    required String lessonId,
    required String quizId,
    required String title,
    required List<String> questionIds,
    required int xpReward,
  }) async {
    await allQuizzes.doc(quizId).set({
      'type':         'lesson',
      'contentId':    contentId,
      'unitId':       unitId,
      'lessonId':     lessonId,
      'title':        title,
      'questionIds':  questionIds,
      'isGraded':     false,
      'passingScore': 0,
      'xpReward':     xpReward.clamp(0, 10),
      'createdAt':    FieldValue.serverTimestamp(),
    });
  }

  Future<void> updatePersonalizedLessonQuiz({
    required String quizId,
    required String title,
    required int xpReward,
    List<String>? questionIds, // optional — only update if provided
  }) {
    final updates = <String, dynamic>{
      'title':    title,
      'xpReward': xpReward.clamp(0, 10),
    };
    if (questionIds != null) {
      updates['questionIds'] = questionIds;
    }
    return _db.collection('quizzes').doc(quizId).update(updates);
  }
 

  Future<void> deletePersonalizedLessonQuiz({required String quizId}) async {
    await allQuizzes.doc(quizId).delete();
  }

  Stream<QuerySnapshot> getLessonQuizzesStream(
      String contentId, String unitId, String lessonId) {
    return allQuizzes
        .where('type', isEqualTo: 'lesson')
        .where('contentId', isEqualTo: contentId)
        .where('unitId', isEqualTo: unitId)
        .where('lessonId', isEqualTo: lessonId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
 
}