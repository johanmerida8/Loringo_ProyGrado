// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:loringo_app/services/firebase_refs.dart';
import 'package:loringo_app/utils/access_code_cipher.dart';
import 'package:loringo_app/utils/access_code_hasher.dart';
import 'package:loringo_app/utils/privacy_policy.dart';

class Database {
  final FirebaseFirestore _db;

  Database({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  // =========================
  // USERS
  // =========================

  CollectionReference get users => _db.collection('users');

  /// Whether an image_manager account already exists — the single-admin
  /// cap is enforced against this same check from two places: here
  /// (inside createUser, the last line of defense) and from
  /// register_screen.dart _before_ the Firebase Auth account is even
  /// created, so a blocked attempt never leaves behind an authenticated
  /// user with no Firestore profile.
  Future<bool> imageManagerExists() async {
    final count = await users
        .where('role', isEqualTo: 'image_manager')
        .get()
        .then((s) => s.docs.length);
    return count >= 1;
  }

  /// [privacyPolicyAccepted] must be true — the caller (register_screen.dart)
  /// gates its own submit button on the same checkbox, but this is checked
  /// again here as the last line of defense, same reasoning as the
  /// image_manager cap re-check just below.
  Future<void> createUser({
    required String uid,
    required String name,
    required String email,
    required String role,
    required bool privacyPolicyAccepted,
  }) async {
    if (!privacyPolicyAccepted) {
      throw Exception('privacy_policy_not_accepted');
    }
    String finalRole = role;
    final nameLower = name.toLowerCase();
    if (nameLower == 'admin' || nameLower == 'administrador') {
      if (await imageManagerExists()) {
        throw Exception('An image manager already exists');
      }
      finalRole = 'image_manager';
    }
    return users.doc(uid).set({
      'name': name,
      'email': email,
      'role': finalRole,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<DocumentSnapshot> getUser(String uid) => users.doc(uid).get();
  Stream<DocumentSnapshot> getUserStream(String uid) =>
      users.doc(uid).snapshots();

  Future<void> updateUser({
    required String uid,
    String? name,
  }) {
    final u = <String, dynamic>{};
    if (name != null) u['name'] = name;
    return users.doc(uid).update(u);
  }

  /// A parent chose "Skip for now" on the forced child-registration screen
  /// (auth_gate.dart's _ParentRouter shows it whenever a parent has zero
  /// children) — persists that choice so they're routed straight into the
  /// app on future launches instead of being forced through it again.
  /// They can still register a child later from the empty-state "Add
  /// Child" button inside the app itself.
  Future<void> skipChildRegistration(String uid) =>
      users.doc(uid).update({'hasSkippedChildSetup': true});

  // =========================
  // STUDENT PROGRESS — lives under the group the student was in when it
  // was earned (teacherGroups/{groupId}/students/{studentId}/progress),
  // not under the student's root doc. See resolveCurrentGroupId below.
  // =========================

  CollectionReference groupProgress(String groupId, String studentId) =>
      teacherGroups
          .doc(groupId)
          .collection('students')
          .doc(studentId)
          .collection('progress');
  CollectionReference groupAttempts(
    String groupId,
    String studentId,
    String activityId,
  ) => groupProgress(groupId, studentId).doc(activityId).collection('attempts');
  CollectionReference groupReports(String groupId, String studentId) =>
      teacherGroups
          .doc(groupId)
          .collection('students')
          .doc(studentId)
          .collection('reports');

  /// The group a student's NEW writes (progress/reports/xp) should go
  /// under — read from the student's root `groupId` pointer. Throws if the
  /// student isn't currently in a group, since there's nowhere valid to
  /// write progress/reports/xp without one.
  Future<String> resolveCurrentGroupId(String studentId) async {
    final studentDoc = await _db.collection('students').doc(studentId).get();
    final groupId = studentDoc.data()?['groupId'] as String?;
    if (groupId == null) {
      throw Exception('Student $studentId is not currently in a group');
    }
    return groupId;
  }

  CollectionReference get students => _db.collection('students');

  static const int maxChildrenPerParent = 8;

  /// Creates a new student document for [parentId]. The access code is
  /// static — set once here, never rotated — and is never written to
  /// Firestore as plain text: `accessCodeHash` (one-way HMAC) is used for
  /// the student-login lookup, and `accessCodeEncrypted` (reversible
  /// AES-256-GCM, see AccessCodeCipher) lets [revealAccessCode] decrypt it
  /// back for the parent later. Returns the plaintext code so the caller
  /// (parent_register_child_screen.dart) can show it to the parent right
  /// after creation too.
  /// [childDataConsentAccepted] must be true — the parent's specific
  /// consent (distinct from their own account's privacy-policy acceptance
  /// in createUser) to collect this particular child's data. Checked here
  /// as the last line of defense, same as the child-cap check below.
  Future<String> createStudent({
    required String parentId,
    required String names,
    required String avatar,
    required bool childDataConsentAccepted,
  }) async {
    if (!childDataConsentAccepted) {
      throw Exception('child_data_consent_not_accepted');
    }
    final existingChildrenCount =
        await students.where('parentId', isEqualTo: parentId).count().get();
    if ((existingChildrenCount.count ?? 0) >= maxChildrenPerParent) {
      throw Exception('max_children_reached');
    }

    final code = await _uniqueAccessCode();
    await students.add({
      'parentId': parentId,
      'names': names,
      'accessCodeHash': AccessCodeHasher.hash(code),
      'accessCodeEncrypted': AccessCodeCipher.encrypt(code),
      'childDataConsentAcceptedAt': FieldValue.serverTimestamp(),
      'childDataConsentVersion': kPrivacyPolicyVersion,
      'avatar': avatar,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return code;
  }

  /// Decrypts and returns a student's static access code — the only way a
  /// parent "views" it after the initial creation screen. Callers must gate
  /// this behind identity confirmation (see identity_confirmation.dart)
  /// before calling, since it returns the real code in the clear.
  ///
  /// Self-heals two legacy shapes for students created before
  /// `accessCodeEncrypted` existed, instead of just throwing:
  ///  - a doc still holding the old plaintext `accessCode` field (from
  ///    before hashing was introduced at all) — migrated in place, so the
  ///    student's real code is preserved rather than lost.
  ///  - a hash-only doc (from the brief window where only `accessCodeHash`
  ///    existed) — the original code was never stored anywhere recoverable
  ///    in that shape, so a new one is issued as a last resort; this is the
  ///    one case where the "code never changes" guarantee can't hold,
  ///    because there is genuinely nothing to recover.
  Future<String> revealAccessCode(String studentId) async {
    final doc = await students.doc(studentId).get();
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) throw Exception('Student not found');

    final encrypted = data['accessCodeEncrypted'] as String?;
    if (encrypted != null) {
      final decrypted = AccessCodeCipher.decrypt(encrypted);
      // Re-sync accessCodeHash to the decrypted value every time, so a
      // hash that ever drifted out of sync with accessCodeEncrypted (by
      // any means) self-heals on the next reveal instead of silently
      // breaking student login. Cheap no-op write when already in sync.
      final expectedHash = AccessCodeHasher.hash(decrypted);
      if (data['accessCodeHash'] != expectedHash) {
        await students.doc(studentId).update({'accessCodeHash': expectedHash});
      }
      return decrypted;
    }

    final legacyPlaintext = data['accessCode'] as String?;
    if (legacyPlaintext != null) {
      await students.doc(studentId).update({
        'accessCodeHash': AccessCodeHasher.hash(legacyPlaintext),
        'accessCodeEncrypted': AccessCodeCipher.encrypt(legacyPlaintext),
        'accessCode': FieldValue.delete(),
      });
      return legacyPlaintext;
    }

    final newCode = await _uniqueAccessCode();
    await students.doc(studentId).update({
      'accessCodeHash': AccessCodeHasher.hash(newCode),
      'accessCodeEncrypted': AccessCodeCipher.encrypt(newCode),
    });
    return newCode;
  }

  /// Generates access codes until one whose hash isn't already in use is
  /// found — guards against the (very unlikely, ~1-in-1.29B) collision the
  /// old plaintext generator never checked for.
  Future<String> _uniqueAccessCode() async {
    while (true) {
      final code = AccessCodeHasher.generateCode();
      final hash = AccessCodeHasher.hash(code);
      final existing =
          await students.where('accessCodeHash', isEqualTo: hash).limit(1).get();
      if (existing.docs.isEmpty) return code;
    }
  }

  /// Student login lookup — hashes the entered code and queries by
  /// `accessCodeHash`, since the plaintext code was never stored.
  ///
  /// Falls back to a legacy plaintext `accessCode` match for students
  /// created before hashing existed at all and never yet migrated by a
  /// parent's [revealAccessCode] call — without this, those students could
  /// never log in again with their real (correct) code, since their doc
  /// has no `accessCodeHash` to match against yet. A match here migrates
  /// the doc in place, same as revealAccessCode's self-heal.
  Future<Map<String, dynamic>?> findStudentByAccessCode(String code) async {
    final hash = AccessCodeHasher.hash(code);
    final snap =
        await students.where('accessCodeHash', isEqualTo: hash).limit(1).get();
    if (snap.docs.isNotEmpty) {
      final doc = snap.docs.first;
      return {'id': doc.id, ...doc.data() as Map<String, dynamic>};
    }

    final normalizedCode = code.trim().toUpperCase();
    final legacySnap = await students
        .where('accessCode', isEqualTo: normalizedCode)
        .limit(1)
        .get();
    if (legacySnap.docs.isEmpty) return null;

    final legacyDoc = legacySnap.docs.first;
    await legacyDoc.reference.update({
      'accessCodeHash': hash,
      'accessCodeEncrypted': AccessCodeCipher.encrypt(normalizedCode),
      'accessCode': FieldValue.delete(),
    });
    final migratedData = Map<String, dynamic>.from(legacyDoc.data() as Map<String, dynamic>)
      ..remove('accessCode');
    return {'id': legacyDoc.id, ...migratedData};
  }

  /// Re-verifies a typed code against a specific student's stored hash —
  /// used by splash_screen.dart's biometric-fallback dialog.
  Future<bool> verifyAccessCode(String studentId, String code) async {
    final doc = await students.doc(studentId).get();
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return false;
    return data['accessCodeHash'] == AccessCodeHasher.hash(code);
  }

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
    required String studentId,
    required String activityId,
    required String contentId,
    required String unitId,
    required int score,
    required int correctAnswers,
    required int wrongAnswers,
    required int xpBase,
    required int bonusXP,
    Map<String, Map<String, dynamic>> taskAnswers = const {},
  }) async {
    final groupId = await resolveCurrentGroupId(studentId);
    final progressRef = groupProgress(groupId, studentId).doc(activityId);
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
    if (bestScore >= 90)
      stars = 3;
    else if (bestScore >= 70)
      stars = 2;

    await groupAttempts(
      groupId,
      studentId,
      activityId,
    ).doc('attempt_$totalAttempts').set({
      'attemptNumber': totalAttempts,
      'score': score,
      'correctAnswers': correctAnswers,
      'wrongAnswers': wrongAnswers,
      'xpEarned': xpEarned,
      'completedAt': now,
    });

    final progressPayload = <String, dynamic>{
      'type': 'activity',
      'contentId': contentId,
      'unitId': unitId,
      'isCompleted': true,
      'firstCompletedAt': firstCompletedAt,
      'lastCompletedAt': now,
      'totalAttempts': totalAttempts,
      'bestScore': bestScore,
      'stars': stars,
      'xpEarned': xpEarned,
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
    await teacherGroups.doc(groupId).collection('students').doc(studentId).update({
      'xp': FieldValue.increment(xpEarned),
      // Season-scoped counter: same increment as `xp`, but reset to 0 by
      // resetLeagueSeasons.ts whenever a league campaign's end date passes.
      // League tier/leaderboard read this field, not lifetime `xp`, so a
      // season can end and mean something without ever touching a
      // student's permanent Total XP.
      'seasonXp': FieldValue.increment(xpEarned),
    });
    return xpEarned;
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
    required String groupId,
    required String studentId,
    required String activityId,
    required String feedback,
  }) async {
    await groupProgress(groupId, studentId).doc(activityId).set({
      'feedback': feedback,
      'feedbackAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Same as saveActivityFeedback but for a Lesson Quiz's progress doc
  /// (groupProgress(groupId, studentId).doc(quizId) — quizzes and
  /// activities share the same progress subcollection, keyed by their own
  /// doc ID, so this is really the same operation with a name that reads
  /// correctly at the call site in the Lesson Quiz review screen).
  Future<void> saveLessonQuizFeedback({
    required String groupId,
    required String studentId,
    required String quizId,
    required String feedback,
  }) async {
    await groupProgress(groupId, studentId).doc(quizId).set({
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
    String? lessonId,
    required int correctAnswers,
    required int totalQuestions,
    required List<Map<String, dynamic>> answers,
    required int xpEarned,
    required bool passed,
    bool isClosedAfterAttempts = false,
  }) async {
    final quizDoc = await quizzesCollection(
      contentId,
      unitId,
      lessonId: lessonId,
    ).doc(quizId).get();
    // lessonId != null is the same unit-vs-lesson signal `scope` used to be
    // — the caller already knows this from which nested collection the
    // quiz lives in, no need to read it back off the doc.
    final scope = lessonId == null ? 'unit' : 'lesson';
    final configuredXp = quizDoc.exists
        ? ((quizDoc.data() as Map<String, dynamic>)['xpReward'] as num?)
                  ?.toInt() ??
              xpEarned
        : xpEarned;

    final groupId = await resolveCurrentGroupId(studentId);
    final progressRef = groupProgress(groupId, studentId).doc(quizId);
    final progressDoc = await progressRef.get();
    int currentAttempts = 0;
    int previousBestScore = -1;
    bool previousPassed = false;
    dynamic firstCompletedAt;
    final now = FieldValue.serverTimestamp();
    final bool wasAlreadyCompleted =
        progressDoc.exists &&
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
    if (scorePercent >= 90)
      stars = 3;
    else if (scorePercent >= 70)
      stars = 2;

    await groupAttempts(groupId, studentId, quizId).doc('attempt_$newAttempts').set({
      'attemptNumber': newAttempts,
      'score': scorePercent,
      'correctAnswers': correctAnswers,
      'wrongAnswers': totalQuestions - correctAnswers,
      'xpEarned': effectiveXpEarned,
      'completedAt': now,
    });

    final progressPayload = <String, dynamic>{
      'type': 'quiz', 'contentId': contentId, 'unitId': unitId,
      if (lessonId != null) 'lessonId': lessonId,
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
      await teacherGroups.doc(groupId).collection('students').doc(studentId).update({
        'xp': FieldValue.increment(effectiveXpEarned),
        'seasonXp': FieldValue.increment(effectiveXpEarned),
      });
      debugPrint('Added $effectiveXpEarned XP to student $studentId');
    } else {
      debugPrint('No XP added (xpEarned = $effectiveXpEarned)');
    }
  }

  Future<void> saveReportOnly({
    required String studentId,
    required String unitId,
    required String unitTitle,
    required int score,
    required int totalQuestions,
    required int stars,
    required String feedback,
  }) async {
    final quizPercent = totalQuestions == 0
        ? 0
        : (score / totalQuestions * 100).round();

    final groupId = await resolveCurrentGroupId(studentId);

    final existingReport = await groupReports(groupId, studentId).doc(unitId).get();
    final previousUnitScores = existingReport.exists
        ? (existingReport.data() as Map<String, dynamic>)['previousUnitScores']
                  as List? ??
              []
        : [];

    int totalActivities = 0;
    int activitiesCompleted = 0;
    int totalLessonQuizzes = 0;
    int completedLessonQuizzes = 0;

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
        final lessonsSnapshot = await personalizedLessons(
          contentId,
          unitId,
        ).get();

        for (final lesson in lessonsSnapshot.docs) {
          final activitiesSnapshot = await personalizedActivities(
            contentId,
            unitId,
            lesson.id,
          ).get();
          totalActivities += activitiesSnapshot.docs.length;
        }

        final lessonQuizIds = <String>{};
        for (final lesson in lessonsSnapshot.docs) {
          final lessonQuizzesSnapshot = await lessonQuizzes(
            contentId,
            unitId,
            lesson.id,
          ).get();
          lessonQuizIds.addAll(lessonQuizzesSnapshot.docs.map((d) => d.id));
        }
        totalLessonQuizzes = lessonQuizIds.length;

        final studentProgressSnapshot = await groupProgress(groupId, studentId).get();

        for (final progressDoc in studentProgressSnapshot.docs) {
          final data = progressDoc.data() as Map<String, dynamic>;
          if (data['unitId'] != unitId || data['isCompleted'] != true) continue;
          if (data['type'] == 'activity') {
            activitiesCompleted++;
          } else if (data['type'] == 'quiz' &&
              lessonQuizIds.contains(progressDoc.id)) {
            completedLessonQuizzes++;
          }
        }
      }
    } catch (e) {
      debugPrint('Error calculating activities for report: $e');
    }

    final activitiesPercent = totalActivities == 0
        ? 0
        : (activitiesCompleted / totalActivities * 100).round();

    await groupReports(groupId, studentId).doc(unitId).set({
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
      'completedLessonQuizzes': completedLessonQuizzes,
      'totalLessonQuizzes': totalLessonQuizzes,
      'previousUnitScores': previousUnitScores,
      'stars': stars,
      'feedback': feedback,
      'generatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    debugPrint('✅ Report saved for student: $studentId, unit: $unitId');
    debugPrint('   Quiz: $score/$totalQuestions ($quizPercent%)');
    debugPrint(
      '   Activities: $activitiesCompleted/$totalActivities ($activitiesPercent%)',
    );
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
    required String groupId,
  }) => personalizedContent.doc(contentId).set({
    'teacherId': teacherId,
    // Groups this content is visible to -- a content can be assigned to
    // multiple groups (see shareContentWithGroup/unshareContentFromGroup
    // below). Starts with just the group it was created for.
    'assignedTo': [groupId],
    'title': title,
    'description': description,
    'ageGroup': ageGroup,
    'order': order,
    'archived': false,
    'createdAt': FieldValue.serverTimestamp(),
  });

  Future<QuerySnapshot> getPersonalizedContent(String groupId) =>
      personalizedContent
          .where('assignedTo', arrayContains: groupId)
          .orderBy('order')
          .get();

  Stream<QuerySnapshot> getPersonalizedContentStream(String groupId) =>
      personalizedContent
          .where('assignedTo', arrayContains: groupId)
          .orderBy('order')
          .snapshots();

  // Adds/removes a group from a content item's `assignedTo` list -- the
  // "share with a parallel group" action on the content card (My Content).
  Future<void> shareContentWithGroup({
    required String contentId,
    required String groupId,
  }) => personalizedContent.doc(contentId).update({
    'assignedTo': FieldValue.arrayUnion([groupId]),
  });

  Future<void> unshareContentFromGroup({
    required String contentId,
    required String groupId,
  }) => personalizedContent.doc(contentId).update({
    'assignedTo': FieldValue.arrayRemove([groupId]),
  });

  Stream<QuerySnapshot> getTeacherContentStream(String teacherId) =>
      personalizedContent
          .where('teacherId', isEqualTo: teacherId)
          .orderBy('order')
          .snapshots();

  // Content across several of a teacher's groups at once (e.g. the Quizzes
  // tab's cross-group aggregation) -- capped at 30 groupIds per Firestore's
  // arrayContainsAny limit, same constraint already accepted by getQuizzesForContentIds.
  Stream<QuerySnapshot> getPersonalizedContentForGroupsStream(
    List<String> groupIds,
  ) => personalizedContent
      .where('assignedTo', arrayContainsAny: groupIds)
      .snapshots();

  // archived is a bool. Drives the Archive/Unarchive transition -- see
  // teacher_content_editor_screen.dart for the menu action that calls this.
  Future<void> setContentArchived({
    required String contentId,
    required bool archived,
  }) => personalizedContent.doc(contentId).update({'archived': archived});

  Future<DocumentSnapshot> getPersonalizedContentDoc(String contentId) =>
      personalizedContent.doc(contentId).get();

  Future<void> updatePersonalizedContent({
    required String contentId,
    required String title,
    required String description,
    required String ageGroup,
    required int order,
  }) => personalizedContent.doc(contentId).update({
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
      final currentOrder =
          (sibling.data() as Map<String, dynamic>)['order'] as int? ?? 0;
      batch.update(sibling.reference, {'order': currentOrder - 1});
    }
    await batch.commit();
  }

  // =========================
  // UNITS / LESSONS / ACTIVITIES / TASKS
  // =========================

  CollectionReference personalizedUnits(String contentId) =>
      personalizedContent.doc(contentId).collection('units');
  CollectionReference personalizedLessons(String contentId, String unitId) =>
      personalizedUnits(contentId).doc(unitId).collection('lessons');
  CollectionReference personalizedActivities(
    String contentId,
    String unitId,
    String lessonId,
  ) => personalizedLessons(
    contentId,
    unitId,
  ).doc(lessonId).collection('activities');
  CollectionReference personalizedTasks(
    String contentId,
    String unitId,
    String lessonId,
    String activityId,
  ) => personalizedActivities(
    contentId,
    unitId,
    lessonId,
  ).doc(activityId).collection('tasks');

  Future<void> createPersonalizedUnit({
    required String groupId,
    required String contentId,
    required String unitId,
    required String title,
    required int order,
  }) => personalizedUnits(contentId).doc(unitId).set({
    'title': title,
    'order': order,
    'createdAt': FieldValue.serverTimestamp(),
  });

  Future<QuerySnapshot> getPersonalizedUnits(
    String groupId,
    String contentId,
  ) => personalizedUnits(contentId).orderBy('order').get();

  Stream<QuerySnapshot> getPersonalizedUnitsStream(
    String groupId,
    String contentId,
  ) => personalizedUnits(contentId).orderBy('order').snapshots();

  Future<void> updatePersonalizedUnit({
    required String groupId,
    required String contentId,
    required String unitId,
    required String title,
    required int order,
  }) => personalizedUnits(
    contentId,
  ).doc(unitId).update({'title': title, 'order': order});

  Future<void> deletePersonalizedUnit(
    String groupId,
    String contentId,
    String unitId,
  ) async {
    final ref = personalizedUnits(contentId).doc(unitId);
    final doc = await ref.get();
    if (!doc.exists) return;
    final deletedOrder = (doc.data() as Map<String, dynamic>)['order'] as int?;

    await ref.delete();

    if (deletedOrder == null) return;

    final siblingsAfter = await personalizedUnits(
      contentId,
    ).where('order', isGreaterThan: deletedOrder).get();
    if (siblingsAfter.docs.isEmpty) return;

    final batch = _db.batch();
    for (final sibling in siblingsAfter.docs) {
      final currentOrder =
          (sibling.data() as Map<String, dynamic>)['order'] as int? ?? 0;
      batch.update(sibling.reference, {'order': currentOrder - 1});
    }
    await batch.commit();
  }

  Future<void> createPersonalizedLesson({
    required String groupId,
    required String contentId,
    required String unitId,
    required String lessonId,
    required String title,
    required int order,
  }) => personalizedLessons(contentId, unitId).doc(lessonId).set({
    'title': title,
    'order': order,
    'createdAt': FieldValue.serverTimestamp(),
  });

  Future<QuerySnapshot> getPersonalizedLessons(
    String groupId,
    String contentId,
    String unitId,
  ) => personalizedLessons(contentId, unitId).orderBy('order').get();

  Stream<QuerySnapshot> getPersonalizedLessonsStream(
    String groupId,
    String contentId,
    String unitId,
  ) => personalizedLessons(contentId, unitId).orderBy('order').snapshots();

  Future<void> updatePersonalizedLesson({
    required String groupId,
    required String contentId,
    required String unitId,
    required String lessonId,
    required String title,
    required int order,
  }) => personalizedLessons(
    contentId,
    unitId,
  ).doc(lessonId).update({'title': title, 'order': order});

  Future<void> deletePersonalizedLesson(
    String groupId,
    String contentId,
    String unitId,
    String lessonId,
  ) async {
    final ref = personalizedLessons(contentId, unitId).doc(lessonId);
    final doc = await ref.get();
    if (!doc.exists) return;
    final deletedOrder = (doc.data() as Map<String, dynamic>)['order'] as int?;

    await ref.delete();

    if (deletedOrder == null) return;

    final siblingsAfter = await personalizedLessons(
      contentId,
      unitId,
    ).where('order', isGreaterThan: deletedOrder).get();
    if (siblingsAfter.docs.isEmpty) return;

    final batch = _db.batch();
    for (final sibling in siblingsAfter.docs) {
      final currentOrder =
          (sibling.data() as Map<String, dynamic>)['order'] as int? ?? 0;
      batch.update(sibling.reference, {'order': currentOrder - 1});
    }
    await batch.commit();
  }

  // requiredActivityId is NOT a parameter here -- it's derived, never
  // manually set. See _relinkActivityChain: after this write, every
  // activity in the lesson gets its requiredActivityId recomputed purely
  // from `order` (each points to whoever's immediately before it, null
  // for the first) so the prerequisite chain can never independently
  // drift out of sync with the visible list order the way a manually-
  // picked reference could (dangling references to deleted activities).
  Future<void> createPersonalizedActivity({
    required String groupId,
    required String contentId,
    required String unitId,
    required String lessonId,
    required String activityId,
    required String title,
    required int order,
    int? xpBase,
    String? difficulty,
    DateTime? scheduledDate,
    DateTime? dueDate,
    DateTime? closeDate,
  }) async {
    await personalizedActivities(
      contentId,
      unitId,
      lessonId,
    ).doc(activityId).set({
      'title': title,
      'order': order,
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
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _relinkActivityChain(contentId, unitId, lessonId);
  }

  Future<QuerySnapshot> getPersonalizedActivities(
    String groupId,
    String contentId,
    String unitId,
    String lessonId,
  ) => personalizedActivities(
    contentId,
    unitId,
    lessonId,
  ).orderBy('order').get();

  Stream<QuerySnapshot> getPersonalizedActivitiesStream(
    String groupId,
    String contentId,
    String unitId,
    String lessonId,
  ) => personalizedActivities(
    contentId,
    unitId,
    lessonId,
  ).orderBy('order').snapshots();

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

    final progressSnapshot = await groupProgress(groupId, studentId).get();
    for (final d in progressSnapshot.docs) {
      final pd = d.data() as Map<String, dynamic>;
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

        final unitQuizzesSnap = await unitQuizzes(contentId, unitId).get();

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

        final bool allActivitiesCompleted =
            unitActivityIds.isNotEmpty &&
            unitActivitiesCompleted == unitActivityIds.length;

        unitCompleted = hasUnitQuiz
            ? (allActivitiesCompleted && unitQuizCompleted)
            : allActivitiesCompleted;
        unitCompletedMap[unitId] = unitCompleted;

        bool isUnitUnlocked = true;
        if (previousUnitIds.isNotEmpty) {
          isUnitUnlocked = previousUnitIds.every(
            (id) => unitCompletedMap[id] ?? false,
          );
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
          final bool isLessonUnlocked =
              isUnitUnlocked && allPreviousLessonsCompleted;

          for (final actDoc in activitiesSnap.docs) {
            final actData = actDoc.data();
            final activityId = actDoc.id;
            final requiredActivityId = actData['requiredActivityId'];
            final isCompleted = completedActivities.containsKey(activityId);
            if (isCompleted) lessonActivitiesCompleted++;
            final stars = isCompleted
                ? (completedActivities[activityId]['stars'] ?? 0)
                : 0;

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
            if (requiredActivityId != null &&
                (requiredActivityId as String).isNotEmpty) {
              isPrerequisiteMet = completedActivities.containsKey(
                requiredActivityId,
              );
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
              lessonActivitiesTotal > 0 &&
              lessonActivitiesCompleted == lessonActivitiesTotal;
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
    int? xpBase,
    String? difficulty,
    DateTime? scheduledDate,
    DateTime? dueDate,
    DateTime? closeDate,
  }) => personalizedActivities(contentId, unitId, lessonId)
      .doc(activityId)
      .update({
        'title': title,
        'order': order,
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
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> deletePersonalizedActivity(
    String groupId,
    String contentId,
    String unitId,
    String lessonId,
    String activityId,
  ) async {
    final ref = personalizedActivities(
      contentId,
      unitId,
      lessonId,
    ).doc(activityId);
    final doc = await ref.get();
    if (!doc.exists) return;
    final data = doc.data() as Map<String, dynamic>;
    final deletedOrder = data['order'] as int?;

    await ref.delete();

    if (deletedOrder != null) {
      final siblingsAfter = await personalizedActivities(
        contentId,
        unitId,
        lessonId,
      ).where('order', isGreaterThan: deletedOrder).get();
      if (siblingsAfter.docs.isNotEmpty) {
        final batch = _db.batch();
        for (final sibling in siblingsAfter.docs) {
          final currentOrder =
              (sibling.data() as Map<String, dynamic>)['order'] as int? ?? 0;
          batch.update(sibling.reference, {'order': currentOrder - 1});
        }
        await batch.commit();
      }
    }

    // Whatever pointed at the deleted activity (if anything) needs its
    // prerequisite recomputed against the new order -- _relinkActivityChain
    // handles this uniformly instead of the old entry-point-only special
    // case, which left a dangling requiredActivityId when an INTERIOR
    // activity was deleted (e.g. deleting #2 from a 1->2->3 chain used to
    // leave #3 permanently pointing at the now-nonexistent #2).
    await _relinkActivityChain(contentId, unitId, lessonId);
  }

  /// Persists a new activity order from a drag-and-drop reorder
  /// (teacher_activity_editor_screen.dart's ReorderableListView) --
  /// [orderedActivityIds] is the full activity list for this lesson in
  /// its new order. Rewrites `order` to match that sequence, then
  /// recomputes the prerequisite chain to match via _relinkActivityChain.
  Future<void> reorderPersonalizedActivities({
    required String contentId,
    required String unitId,
    required String lessonId,
    required List<String> orderedActivityIds,
  }) async {
    final batch = _db.batch();
    for (var i = 0; i < orderedActivityIds.length; i++) {
      batch.update(
        personalizedActivities(
          contentId,
          unitId,
          lessonId,
        ).doc(orderedActivityIds[i]),
        {'order': i + 1},
      );
    }
    await batch.commit();
    await _relinkActivityChain(contentId, unitId, lessonId);
  }

  /// Recomputes requiredActivityId for every activity in a lesson purely
  /// from its current `order` -- activity N's prerequisite is always
  /// activity N-1 (null for the first, making it the chain's entry
  /// point). `order` is the single source of truth for the unlock chain;
  /// this is the ONLY place requiredActivityId ever gets written, called
  /// after create/delete/reorder so the chain can never independently
  /// drift out of sync with the visible list order the way a manually-
  /// picked reference could. Only writes docs whose stored value is
  /// actually wrong, so a no-op call (nothing changed) touches nothing.
  Future<void> _relinkActivityChain(
    String contentId,
    String unitId,
    String lessonId,
  ) async {
    final snap = await personalizedActivities(
      contentId,
      unitId,
      lessonId,
    ).orderBy('order').get();
    final docs = snap.docs;
    final batch = _db.batch();
    var hasWrites = false;
    for (var i = 0; i < docs.length; i++) {
      final correctRequired = i == 0 ? null : docs[i - 1].id;
      final current =
          (docs[i].data() as Map<String, dynamic>)['requiredActivityId']
              as String?;
      if (current != correctRequired) {
        batch.update(docs[i].reference, {
          'requiredActivityId': correctRequired,
        });
        hasWrites = true;
      }
    }
    if (hasWrites) await batch.commit();
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
  }) => personalizedTasks(contentId, unitId, lessonId, activityId)
      .doc(taskId)
      .set({
        'type': type,
        'title': title,
        'question': question,
        'order': order,
        'data': data,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<QuerySnapshot> getPersonalizedTasks(
    String groupId,
    String contentId,
    String unitId,
    String lessonId,
    String activityId,
  ) => personalizedTasks(
    contentId,
    unitId,
    lessonId,
    activityId,
  ).orderBy('order').get();

  Stream<QuerySnapshot> getPersonalizedTasksStream(
    String groupId,
    String contentId,
    String unitId,
    String lessonId,
    String activityId,
  ) => personalizedTasks(
    contentId,
    unitId,
    lessonId,
    activityId,
  ).orderBy('order').snapshots();

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
  }) => personalizedTasks(contentId, unitId, lessonId, activityId)
      .doc(taskId)
      .update({
        'type': type,
        'title': title,
        'question': question,
        'order': order,
        'data': data,
      });

  Future<void> deletePersonalizedTask(
    String groupId,
    String contentId,
    String unitId,
    String lessonId,
    String activityId,
    String taskId,
  ) async {
    final ref = personalizedTasks(
      contentId,
      unitId,
      lessonId,
      activityId,
    ).doc(taskId);
    final doc = await ref.get();
    if (!doc.exists) return;
    final deletedOrder = (doc.data() as Map<String, dynamic>)['order'] as int?;

    await ref.delete();

    if (deletedOrder == null) return;

    final siblingsAfter = await personalizedTasks(
      contentId,
      unitId,
      lessonId,
      activityId,
    ).where('order', isGreaterThan: deletedOrder).get();
    if (siblingsAfter.docs.isEmpty) return;

    final batch = _db.batch();
    for (final sibling in siblingsAfter.docs) {
      final currentOrder =
          (sibling.data() as Map<String, dynamic>)['order'] as int? ?? 0;
      batch.update(sibling.reference, {'order': currentOrder - 1});
    }
    await batch.commit();
  }

  /// Persists a new task order from a drag-and-drop reorder
  /// (teacher_task_editor_screen.dart's ReorderableListView) --
  /// [orderedTaskIds] is the full task list for this activity in its new
  /// order. Tasks have no prerequisite chain (unlike activities), just a
  /// plain sequential `order` used for display and grading order, so this
  /// is a straight batched rewrite -- no relink step needed.
  Future<void> reorderPersonalizedTasks({
    required String contentId,
    required String unitId,
    required String lessonId,
    required String activityId,
    required List<String> orderedTaskIds,
  }) async {
    final batch = _db.batch();
    for (var i = 0; i < orderedTaskIds.length; i++) {
      batch.update(
        personalizedTasks(
          contentId,
          unitId,
          lessonId,
          activityId,
        ).doc(orderedTaskIds[i]),
        {'order': i + 1},
      );
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

  /// Folder-safe form of a category name: lowercase, spaces to
  /// underscores, everything else stripped. `categoryName` (this) is used
  /// as a literal Cloudinary folder path segment (see
  /// image_service.dart's uploadToCloudinary), so it can never contain
  /// spaces or other characters a folder path can't have — `displayName`
  /// on the category doc keeps what the user actually typed (e.g. "Sea
  /// Animals") for the UI to show instead.
  static String sanitizeCategoryName(String raw) => raw
      .trim()
      .replaceAll(' ', '_')
      .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '')
      .toLowerCase();

  Future<String> createCategory({
    required String displayName,
    required String ownerId,
    required String ownerRole,
  }) async {
    final ref = await ownerCategories(ownerId).add({
      'categoryName': sanitizeCategoryName(displayName),
      'displayName': displayName.trim(),
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
      .where('ownerRole', isEqualTo: 'image_manager')
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
          .where('ownerRole', isEqualTo: 'image_manager')
          .orderBy('createdAt')
          .get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getTeacherCategories(
    String teacherId,
  ) async {
    try {
      final snap = await ownerCategories(
        teacherId,
      ).where('ownerRole', isEqualTo: 'teacher').orderBy('createdAt').get();
      return snap.docs
          .map((d) => {'id': d.id, ...(d.data() as Map<String, dynamic>)})
          .toList();
    } catch (_) {
      return [];
    }
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
      categoryItems(
        ownerId,
        categoryId,
      ).orderBy('createdAt', descending: true).snapshots();

  Stream<int> getImagesCountStream(String ownerId, String categoryId) =>
      categoryItems(ownerId, categoryId).snapshots().map((s) => s.docs.length);

  Future<List<Map<String, dynamic>>> getImagesByCategory(
    String ownerId,
    String categoryId,
  ) async {
    try {
      final snap = await categoryItems(
        ownerId,
        categoryId,
      ).orderBy('name').get();
      return snap.docs
          .map((d) => {'id': d.id, ...(d.data() as Map<String, dynamic>)})
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteImage(String ownerId, String categoryId, String imageId) =>
      categoryItems(ownerId, categoryId).doc(imageId).delete();

  Future<void> approveImage({
    required String ownerId,
    required String categoryId,
    required String imageId,
  }) async {
    final uid = authInstance.currentUser?.uid;
    await categoryItems(ownerId, categoryId).doc(imageId).update({
      'moderationStatus': 'approved',
      'isVisible': true,
      'approvedAt': FieldValue.serverTimestamp(),
      'approvedBy': uid,
      'rejectedAt': null,
      'rejectedBy': null,
    });
  }

  Future<void> rejectImage({
    required String ownerId,
    required String categoryId,
    required String imageId,
  }) async {
    final uid = authInstance.currentUser?.uid;
    await categoryItems(ownerId, categoryId).doc(imageId).update({
      'moderationStatus': 'rejected',
      'isVisible': false,
      'rejectedAt': FieldValue.serverTimestamp(),
      'rejectedBy': uid,
    });
  }

  Future<int> getCategoriesCount() async {
    try {
      final snap = await _db
          .collectionGroup('categories')
          .where('ownerRole', isEqualTo: 'image_manager')
          .get();
      return snap.docs.length;
    } catch (e) {
      debugPrint('getCategoriesCount failed: $e');
      return 0;
    }
  }

  Stream<int> getCategoriesCountStream() => _db
      .collectionGroup('categories')
      .where('ownerRole', isEqualTo: 'image_manager')
      .snapshots()
      .map((s) => s.docs.length);

  Future<int> getTotalImagesCount() async {
    try {
      int total = 0;
      final cats = await _db
          .collectionGroup('categories')
          .where('ownerRole', isEqualTo: 'image_manager')
          .get();
      for (final c in cats.docs) {
        final ownerId =
            c.data()['ownerId'] as String? ?? c.reference.parent.parent!.id;
        total += (await categoryItems(ownerId, c.id).get()).docs.length;
      }
      return total;
    } catch (e) {
      debugPrint('getTotalImagesCount failed: $e');
      return 0;
    }
  }

  Stream<int> getImagesCountByCategoryStream(
    String ownerId,
    String categoryId,
  ) => getImagesCountStream(ownerId, categoryId);

  // =========================
  // TEACHER GROUPS
  // =========================

  CollectionReference get teacherGroups => _db.collection('teacherGroups');
  Future<QuerySnapshot> getTeacherGroups(String teacherId) =>
      teacherGroups.where('teacherId', isEqualTo: teacherId).get();
  Stream<QuerySnapshot> getTeacherGroupsStream(String teacherId) =>
      teacherGroups.where('teacherId', isEqualTo: teacherId).snapshots();
  Future<QuerySnapshot> getAllGroups() => teacherGroups.get();

  // ── Group code security — hashing/encryption happen server-side in
  // Cloud Functions (functions/src/groupCode.ts), never in the client, so
  // the pepper/key are never bundled into the compiled app (unlike the
  // student access-code implementation's client-side approach). These
  // three methods are thin wrappers around the matching callables. ──────

  /// Generates a new, unique group code. Does NOT write the group
  /// document — the caller (teacher_home_screen.dart) still creates it,
  /// storing `groupCodeHash`/`groupCodeEncrypted` from the result instead
  /// of a plaintext `groupCode`. Returns the plaintext code once, for the
  /// one-time "group created" display.
  Future<Map<String, String>> generateGroupCode() async {
    final result =
        await FirebaseFunctions.instance.httpsCallable('generateGroupCode').call();
    final data = (result.data as Map).cast<String, dynamic>();
    return data.map((key, value) => MapEntry(key, value as String));
  }

  /// Decrypts and returns a group's static code — only the owning
  /// teacher is authorized (enforced server-side). Used when the teacher
  /// wants to view/share their group's code (e.g.
  /// invite_student_modal.dart).
  Future<String> revealGroupCode(String groupId) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('revealGroupCode')
        .call({'groupId': groupId});
    return (result.data as Map)['groupCode'] as String;
  }

  /// Looks up a group by its join code — used when a parent/student
  /// enters a code to join. Returns null if no group matches.
  Future<Map<String, dynamic>?> findGroupByCode(String code) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('findGroupByCode')
        .call({'code': code});
    if (result.data == null) return null;
    return (result.data as Map).cast<String, dynamic>();
  }

  /// Adds a student to a group's roster and points the student's root
  /// `groupId` at it — called whenever a student joins a group for the
  /// first time or switches to a new one (parent_join_group_screen.dart,
  /// notifications_screen.dart's invitation-accept flow). If the student
  /// was already in a different group, the caller is responsible for
  /// calling [leaveGroup] on the old one first (see switchGroup below for
  /// the common case of doing both at once).
  ///
  /// Every subsequent progress/report/xp write for this student goes
  /// under this new roster doc — nothing is copied in from anywhere, the
  /// student simply starts fresh (`xp: 0`, empty progress/reports) under
  /// the new group, exactly like a first-time join.
  Future<void> joinGroup({
    required String studentId,
    required String groupId,
  }) async {
    final now = FieldValue.serverTimestamp();
    await teacherGroups.doc(groupId).collection('students').doc(studentId).set({
      'studentId': studentId,
      'joinedAt': now,
      'leftAt': null,
      'status': 'active',
      'xp': 0,
      'seasonXp': 0,
    });
    await _db.collection('students').doc(studentId).update({
      'groupId': groupId,
      'groupHistory': FieldValue.arrayUnion([
        {'groupId': groupId, 'joinedAt': DateTime.now()},
      ]),
    });
  }

  /// Deletes every document in [query], chunked into batches of 500
  /// (Firestore's per-batch limit) — the shared leaf-deletion primitive
  /// every cascade-delete method below is built from.
  Future<void> _deleteAllDocs(Query query) async {
    final snap = await query.get();
    if (snap.docs.isEmpty) return;
    for (var i = 0; i < snap.docs.length; i += 500) {
      final batch = _db.batch();
      for (final doc in snap.docs.skip(i).take(500)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  /// Deletes everything tied to one student's membership in one group:
  /// each progress doc's `attempts` subcollection, the progress docs
  /// themselves, the reports, and finally the roster/membership doc.
  /// Shared by [leaveGroup] (one group) and the wider cascade-deletes
  /// below (every group).
  Future<void> _deleteGroupMembershipData(String groupId, String studentId) async {
    final progressSnap = await groupProgress(groupId, studentId).get();
    for (final doc in progressSnap.docs) {
      await _deleteAllDocs(groupAttempts(groupId, studentId, doc.id));
    }
    await _deleteAllDocs(groupProgress(groupId, studentId));
    await _deleteAllDocs(groupReports(groupId, studentId));
    await teacherGroups.doc(groupId).collection('students').doc(studentId).delete();
  }

  /// Ends a student's membership in [groupId] — deletes their roster doc
  /// and every progress/attempts/reports document earned under this
  /// group. The student's root profile and `groupHistory` are untouched
  /// (callers handle clearing the student's root `groupId` separately,
  /// e.g. group_navigation_screen.dart's _removeStudent; `groupHistory`
  /// is only ever appended to by joinGroup, never read or written here).
  Future<void> leaveGroup({
    required String studentId,
    required String groupId,
  }) async {
    await _deleteGroupMembershipData(groupId, studentId);
  }

  /// Convenience for the common "student switches from one group to
  /// another" case — used by parent_join_group_screen.dart and
  /// notifications_screen.dart's invitation-accept flow when the child is
  /// already in a group. [oldGroupId] may be null for a first-time join.
  Future<void> switchGroup({
    required String studentId,
    String? oldGroupId,
    required String newGroupId,
  }) async {
    if (oldGroupId != null && oldGroupId != newGroupId) {
      await leaveGroup(studentId: studentId, groupId: oldGroupId);
    }
    await joinGroup(studentId: studentId, groupId: newGroupId);
  }

  /// Every report ever generated for this student across every group
  /// they've been in, past or present — reads the student's root
  /// `groupHistory` to find each group, then reads that group's own
  /// `reports` subcollection directly. Used by screens that intentionally
  /// want full lifetime history (parent Reports, teacher's "All Units"
  /// report history), not the current-group-only views.
  Future<List<Map<String, dynamic>>> getAllReportsEver(String studentId) async {
    final groupIds = await _groupHistoryIds(studentId);
    final snaps = await Future.wait([
      for (final groupId in groupIds) groupReports(groupId, studentId).get(),
    ]);
    return [
      for (final snap in snaps)
        for (final doc in snap.docs)
          {'id': doc.id, ...doc.data() as Map<String, dynamic>},
    ];
  }

  /// Same idea as getAllReportsEver, for progress docs — used by
  /// aggregations that want a student's full lifetime activity/quiz
  /// history regardless of which group it was earned in (e.g. task-type
  /// insight stats), not current-group-only views.
  Future<List<Map<String, dynamic>>> getAllProgressEver(String studentId) async {
    final groupIds = await _groupHistoryIds(studentId);
    final snaps = await Future.wait([
      for (final groupId in groupIds) groupProgress(groupId, studentId).get(),
    ]);
    return [
      for (final snap in snaps)
        for (final doc in snap.docs)
          {'id': doc.id, ...doc.data() as Map<String, dynamic>},
    ];
  }

  Future<List<String>> _groupHistoryIds(String studentId) async {
    final studentDoc = await _db.collection('students').doc(studentId).get();
    final history = studentDoc.data()?['groupHistory'] as List? ?? [];
    final ids = <String>{
      for (final entry in history)
        if ((entry as Map)['groupId'] != null) entry['groupId'] as String,
    };
    final currentGroupId = studentDoc.data()?['groupId'] as String?;
    if (currentGroupId != null) ids.add(currentGroupId);
    return ids.toList();
  }

  /// Fully deletes a student: every group they were ever in (current +
  /// `groupHistory`) has its progress/attempts/reports/roster doc for this
  /// student removed via [_deleteGroupMembershipData], then the student's
  /// own root doc is deleted last. Used both for a parent removing a
  /// single child (parent_children_screen.dart) and for a parent deleting
  /// their whole account (parent_navigation_screen.dart, looped per
  /// child). Groups/teachers themselves are never touched.
  Future<void> deleteStudentCascade(String studentId) async {
    final groupIds = await _groupHistoryIds(studentId);
    for (final groupId in groupIds) {
      await _deleteGroupMembershipData(groupId, studentId);
    }
    await students.doc(studentId).delete();
  }

  /// Fully deletes everything a teacher exclusively owns: their authored
  /// content, media library categories/images, continue-bookmarks, league
  /// campaign, and — unlike a parent's cascade, which only ever touches
  /// their own children — every `teacherGroups/{groupId}` group they
  /// created, including every student's progress/reports/roster data
  /// earned under those groups. Student root profiles are never deleted
  /// (they keep existing, just lose their history from this teacher's
  /// groups); any student still pointing at a group being deleted has
  /// that dangling `groupId` reference cleared. Callers are responsible
  /// for confirming the teacher has no active (non-archived) groups
  /// before calling this — see teacher_profile_screen.dart's
  /// _deleteAccount, which blocks otherwise.
  Future<void> deleteTeacherOwnedData(String teacherId) async {
    await _deleteAllDocs(
        personalizedContent.where('teacherId', isEqualTo: teacherId));

    final categoriesSnap = await ownerCategories(teacherId).get();
    for (final category in categoriesSnap.docs) {
      await _deleteAllDocs(categoryItems(teacherId, category.id));
      await category.reference.delete();
    }

    await _deleteAllDocs(bookmarksFor(teacherId));
    await _db.collection('teacherContinueBookmarks').doc(teacherId).delete();

    await leagueCampaigns.doc(teacherId).delete();

    final groupsSnap =
        await teacherGroups.where('teacherId', isEqualTo: teacherId).get();
    for (final group in groupsSnap.docs) {
      final rosterSnap =
          await teacherGroups.doc(group.id).collection('students').get();
      for (final roster in rosterSnap.docs) {
        final studentId = roster.id;
        await _deleteGroupMembershipData(group.id, studentId);
        final studentDoc = await students.doc(studentId).get();
        final studentData = studentDoc.data() as Map<String, dynamic>?;
        if (studentData != null && studentData['groupId'] == group.id) {
          await students.doc(studentId).update({'groupId': FieldValue.delete()});
        }
      }
      await group.reference.delete();
    }
  }

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
    assert(
      scope == 'single' || scope == 'all',
      "scope must be 'single' or 'all'",
    );
    assert(
      scope != 'single' || groupId != null,
      'groupId is required when scope is single',
    );
    return leagueCampaigns.doc(teacherId).set({
      'scope': scope,
      // Omitted entirely (not written as an explicit null) when scope is
      // 'all' — there's no single group to reference, and 'scope' already
      // tells any reader why the field isn't there. Every existing reader
      // (teacher_league_screen.dart's `campaign?['groupId'] as String?`)
      // already treats a missing key the same as an explicit null, so
      // this is not a breaking change.
      if (scope == 'single') 'groupId': groupId,
      'startDate': startDate,
      'endDate': endDate,
      'rewards': rewards,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // =========================
  // QUIZ (unit: graded/reports/gates; lesson: ungraded XP-only check-in)
  // =========================
  //
  // Nested under the same content/units/lessons hierarchy the rest of a
  // unit's content already lives in (see personalizedUnits/
  // personalizedLessons above), instead of a flat top-level collection --
  // the path itself now says whether a quiz is a Unit Quiz or a Lesson
  // Quiz, so callers pass `lessonId` (null ⇒ unit quiz) instead of a
  // `scope` string. contentId/unitId are still written onto the quiz doc
  // (denormalized) purely so a future cross-unit query could filter on
  // them without walking the whole tree; nothing currently reads them back
  // off the doc for routing -- every read site already knows contentId/
  // unitId/lessonId from its own context before it ever needs to resolve a
  // quiz doc.

  CollectionReference unitQuizzes(String contentId, String unitId) =>
      personalizedUnits(contentId).doc(unitId).collection('quizzes');
  CollectionReference lessonQuizzes(
    String contentId,
    String unitId,
    String lessonId,
  ) => personalizedLessons(contentId, unitId).doc(lessonId).collection('quizzes');
  CollectionReference quizzesCollection(
    String contentId,
    String unitId, {
    String? lessonId,
  }) => lessonId != null
      ? lessonQuizzes(contentId, unitId, lessonId)
      : unitQuizzes(contentId, unitId);

  Future<void> _assertNoExistingQuiz({
    required String contentId,
    required String unitId,
    String? lessonId,
  }) async {
    final existing = await quizzesCollection(
      contentId,
      unitId,
      lessonId: lessonId,
    ).limit(1).get();
    if (existing.docs.isNotEmpty) {
      throw Exception(
        lessonId == null
            ? 'This unit already has a Quiz. Edit the existing one instead of creating another.'
            : 'This lesson already has a Quiz. Edit the existing one instead of creating another.',
      );
    }
  }

  /// How many Lesson Quizzes exist for a unit -- used both to gate Unit
  /// Quiz creation (see createQuiz below) and by group_quizzes_screen.dart
  /// to show the same count as a progress hint before the teacher even
  /// opens the create form.
  Future<int> countLessonQuizzesForUnit({
    required String contentId,
    required String unitId,
  }) async {
    final lessonsSnap = await personalizedLessons(contentId, unitId).get();
    final counts = await Future.wait(
      lessonsSnap.docs.map(
        (l) => lessonQuizzes(contentId, unitId, l.id).limit(1).get(),
      ),
    );
    return counts.where((snap) => snap.docs.isNotEmpty).length;
  }

  /// Minimum Lesson Quizzes a unit must have before its Unit Quiz can be
  /// created -- keeps a Unit Quiz from being added to a unit with little
  /// or no formative check-in history. Hard block, no override path, same
  /// as _assertNoExistingQuiz above and ContentAssignmentGuard.
  static const int kMinLessonQuizzesForUnitQuiz = 3;

  Future<void> createQuiz({
    required String contentId,
    required String unitId,
    required String quizId,
    required String title,
    required List<Map<String, dynamic>> questions,
    required int passingScore,
    required int xpReward,
    required int maxAttempts,
    required String groupId,
    String? lessonId,
  }) async {
    await _assertNoExistingQuiz(
      contentId: contentId,
      unitId: unitId,
      lessonId: lessonId,
    );

    if (lessonId == null) {
      final lessonQuizCount = await countLessonQuizzesForUnit(
        contentId: contentId,
        unitId: unitId,
      );
      if (lessonQuizCount < kMinLessonQuizzesForUnitQuiz) {
        throw Exception(
          'Add at least $kMinLessonQuizzesForUnitQuiz Lesson Quizzes to this unit before creating its Unit Quiz '
          '($lessonQuizCount/$kMinLessonQuizzesForUnitQuiz so far).',
        );
      }
    }

    final maxXp = lessonId == null ? 100 : 50;
    final quizRef = quizzesCollection(
      contentId,
      unitId,
      lessonId: lessonId,
    ).doc(quizId);
    final batch = _db.batch();

    batch.set(quizRef, {
      'contentId': contentId,
      'unitId': unitId,
      'groupId': groupId,
      'title': title,
      'totalQuestions': questions.length,
      'passingScore': passingScore,
      'xpReward': xpReward.clamp(0, maxXp),
      'isGraded': lessonId == null,
      'maxAttempts': maxAttempts,
      'createdAt': FieldValue.serverTimestamp(),
    });

    for (final q in questions) {
      final qRef = quizRef.collection('questions').doc('q_${q['order']}');
      batch.set(qRef, {
        'question': q['question'],
        'options': q['options'],
        'correctIndex': q['correctIndex'],
        'order': q['order'],
      });
    }
    await batch.commit();
  }

  Future<void> updateQuiz({
    required String contentId,
    required String unitId,
    String? lessonId,
    required String quizId,
    required String title,
    required int passingScore,
    required int xpReward,
    required int maxAttempts,
    required List<Map<String, dynamic>> questions,
  }) async {
    final quizRef = quizzesCollection(
      contentId,
      unitId,
      lessonId: lessonId,
    ).doc(quizId);
    final maxXp = lessonId == null ? 100 : 50;

    await quizRef.update({
      'title': title,
      'passingScore': passingScore,
      'xpReward': xpReward.clamp(0, maxXp),
      'maxAttempts': maxAttempts,
      'totalQuestions': questions.length,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final existingQuestions = await quizRef.collection('questions').get();
    final batch = _db.batch();
    for (final doc in existingQuestions.docs) {
      batch.delete(doc.reference);
    }

    for (final q in questions) {
      final qRef = quizRef.collection('questions').doc('q_${q['order']}');
      batch.set(qRef, {
        'question': q['question'],
        'options': q['options'],
        'correctIndex': q['correctIndex'],
        'order': q['order'],
      });
    }

    await batch.commit();
  }

  Future<void> deleteQuiz({
    required String contentId,
    required String unitId,
    String? lessonId,
    required String quizId,
  }) async {
    final quizRef = quizzesCollection(
      contentId,
      unitId,
      lessonId: lessonId,
    ).doc(quizId);
    final questions = await quizRef.collection('questions').get();
    final batch = _db.batch();
    for (final q in questions.docs) batch.delete(q.reference);
    batch.delete(quizRef);
    await batch.commit();
  }

  Future<QuerySnapshot> getQuizQuestions(
    String contentId,
    String unitId,
    String quizId, {
    String? lessonId,
  }) async {
    return quizzesCollection(contentId, unitId, lessonId: lessonId)
        .doc(quizId)
        .collection('questions')
        .orderBy('order')
        .get();
  }

  Stream<QuerySnapshot> getQuizzesStream(String contentId, String unitId) {
    return unitQuizzes(
      contentId,
      unitId,
    ).orderBy('createdAt', descending: true).snapshots();
  }

  Stream<QuerySnapshot> getLessonQuizzesStream(
    String contentId,
    String unitId,
    String lessonId,
  ) {
    return lessonQuizzes(
      contentId,
      unitId,
      lessonId,
    ).orderBy('createdAt', descending: true).snapshots();
  }

  Future<DocumentSnapshot> getQuiz(
    String contentId,
    String unitId,
    String quizId, {
    String? lessonId,
  }) async {
    return quizzesCollection(contentId, unitId, lessonId: lessonId)
        .doc(quizId)
        .get();
  }

  // =========================
  // DUPLICATE UNIT / LESSON
  // =========================
  //
  // Clones a Unit (or a single Lesson) with everything nested under it --
  // Lessons, Activities, Tasks, and any Lesson/Unit Quizzes (with their
  // questions) -- so a teacher can start from an existing structure
  // instead of rebuilding it from scratch every time.
  //
  // Two things need care, confirmed directly against the schema before
  // writing this:
  //   1. `requiredActivityId` (an Activity's prerequisite pointer to a
  //      sibling Activity within the same Lesson) must be remapped to the
  //      CLONE's own activity IDs, never left pointing at the original.
  //   2. Task/Activity image fields are plain URL strings with no back-
  //      reference to a media-library doc, so they're safe to copy by
  //      value -- no re-upload needed.

  int _cloneIdCounter = 0;

  // Timestamp-based IDs match the scheme every create screen already uses
  // (`'unit_<millis>'`, etc.), plus a counter suffix for uniqueness when
  // many IDs are minted in one fast loop (a plain timestamp alone can
  // collide there).
  String _newCloneId(String prefix) =>
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${_cloneIdCounter++}';

  Future<String> _cloneLessonInto({
    required String contentId,
    required String sourceUnitId,
    required String sourceLessonId,
    required String targetUnitId,
    required String title,
  }) async {
    final targetLessonsRef = personalizedLessons(contentId, targetUnitId);
    final newOrder = (await targetLessonsRef.get()).docs.length + 1;
    final newLessonId = _newCloneId('lesson');
    await targetLessonsRef.doc(newLessonId).set({
      'title': title,
      'order': newOrder,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final activitiesSnap = await personalizedActivities(
      contentId,
      sourceUnitId,
      sourceLessonId,
    ).orderBy('order').get();

    // First pass: mint every new activity ID up front so requiredActivityId
    // remapping (second pass) always has the full map available, regardless
    // of activity order within the lesson.
    final activityIdMap = <String, String>{
      for (final actDoc in activitiesSnap.docs)
        actDoc.id: _newCloneId('activity'),
    };

    for (final actDoc in activitiesSnap.docs) {
      final actData = Map<String, dynamic>.from(
        actDoc.data() as Map<String, dynamic>,
      );
      final oldRequired = actData['requiredActivityId'] as String?;
      actData['requiredActivityId'] = oldRequired != null
          ? activityIdMap[oldRequired]
          : null;
      actData['createdAt'] = FieldValue.serverTimestamp();

      final newActId = activityIdMap[actDoc.id]!;
      await personalizedActivities(
        contentId,
        targetUnitId,
        newLessonId,
      ).doc(newActId).set(actData);

      final tasksSnap = await personalizedTasks(
        contentId,
        sourceUnitId,
        sourceLessonId,
        actDoc.id,
      ).orderBy('order').get();
      for (final taskDoc in tasksSnap.docs) {
        final taskData = Map<String, dynamic>.from(
          taskDoc.data() as Map<String, dynamic>,
        );
        taskData['createdAt'] = FieldValue.serverTimestamp();
        final newTaskId = _newCloneId('task');
        await personalizedTasks(
          contentId,
          targetUnitId,
          newLessonId,
          newActId,
        ).doc(newTaskId).set(taskData);
      }
    }

    final lessonQuizzesSnap = await lessonQuizzes(
      contentId,
      sourceUnitId,
      sourceLessonId,
    ).get();
    for (final quizDoc in lessonQuizzesSnap.docs) {
      await _cloneQuiz(
        quizDoc,
        contentId: contentId,
        newUnitId: targetUnitId,
        newLessonId: newLessonId,
      );
    }

    return newLessonId;
  }

  Future<void> _cloneQuiz(
    QueryDocumentSnapshot quizDoc, {
    required String contentId,
    required String newUnitId,
    String? newLessonId,
  }) async {
    final quizData = Map<String, dynamic>.from(
      quizDoc.data() as Map<String, dynamic>,
    );
    quizData['contentId'] = contentId;
    quizData['unitId'] = newUnitId;
    quizData['createdAt'] = FieldValue.serverTimestamp();

    final newQuizId = _newCloneId('quiz');
    final newQuizRef = quizzesCollection(
      contentId,
      newUnitId,
      lessonId: newLessonId,
    ).doc(newQuizId);
    await newQuizRef.set(quizData);

    final questionsSnap = await quizDoc.reference.collection('questions').get();
    for (final qDoc in questionsSnap.docs) {
      await newQuizRef.collection('questions').doc(qDoc.id).set(qDoc.data());
    }
  }

  /// Clones [lessonId] within the SAME unit, appended after existing
  /// lessons, titled "`<original>` (Copy)".
  Future<String> duplicateLesson({
    required String contentId,
    required String unitId,
    required String lessonId,
  }) async {
    final lessonDoc = await personalizedLessons(
      contentId,
      unitId,
    ).doc(lessonId).get();
    if (!lessonDoc.exists) throw Exception('Lesson not found');
    final title =
        (lessonDoc.data() as Map<String, dynamic>)['title'] as String? ??
        'Lesson';

    return _cloneLessonInto(
      contentId: contentId,
      sourceUnitId: unitId,
      sourceLessonId: lessonId,
      targetUnitId: unitId,
      title: '$title (Copy)',
    );
  }

  /// Clones [unitId] entirely -- every Lesson (and its Activities/Tasks/
  /// lesson Quiz) plus the unit's own Quiz -- into a new unit titled
  /// "`<original>` (Copy)".
  Future<String> duplicateUnit({
    required String contentId,
    required String unitId,
  }) async {
    final unitDoc = await personalizedUnits(contentId).doc(unitId).get();
    if (!unitDoc.exists) throw Exception('Unit not found');
    final unitData = unitDoc.data() as Map<String, dynamic>;
    final title = unitData['title'] as String? ?? 'Unit';

    final unitsRef = personalizedUnits(contentId);
    final newOrder = (await unitsRef.get()).docs.length + 1;
    final newUnitId = _newCloneId('unit');
    await unitsRef.doc(newUnitId).set({
      'title': '$title (Copy)',
      'order': newOrder,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final lessonsSnap = await personalizedLessons(
      contentId,
      unitId,
    ).orderBy('order').get();
    for (final lessonDoc in lessonsSnap.docs) {
      final lessonTitle =
          (lessonDoc.data() as Map<String, dynamic>)['title'] as String? ??
          'Lesson';
      await _cloneLessonInto(
        contentId: contentId,
        sourceUnitId: unitId,
        sourceLessonId: lessonDoc.id,
        targetUnitId: newUnitId,
        title:
            lessonTitle, // no "(Copy)" suffix per-lesson -- the unit title already carries it
      );
    }

    final unitQuizzesSnap = await unitQuizzes(contentId, unitId).get();
    for (final quizDoc in unitQuizzesSnap.docs) {
      await _cloneQuiz(quizDoc, contentId: contentId, newUnitId: newUnitId);
    }

    return newUnitId;
  }

  // =========================
  // CONTINUE-WHERE-YOU-LEFT-OFF BOOKMARKS
  // =========================
  //
  // Multiple bookmarks per teacher, in a subcollection
  // (teacherContinueBookmarks/{teacherId}/bookmarks/{bookmarkId}) -- a
  // teacher can be mid-way through several different units/lessons/
  // activities/tasks at once (possibly across different Content items)
  // and wants to resume any of them independently, not just the single
  // most recent one. Building content is a long multi-screen process, so
  // a teacher taps the bookmark button on whichever CREATE form they're
  // filling out (create_unit_screen.dart and siblings) to record exactly
  // where they were, then picks any of them back up from the bookmark
  // chip on My Content later.
  //
  // Bookmark IDs are DETERMINISTIC (derived from level + the ancestor
  // IDs), not random -- re-bookmarking the same spot (e.g. tapping the
  // button again after typing more into the same still-unsaved Lesson)
  // overwrites that one entry instead of piling up duplicates for the
  // same in-progress item.
  //
  // Not called "draft" anywhere in this feature's UI -- content only ever
  // has an 'archived' bool (see setContentArchived above), and a
  // Unit/Lesson/Activity/Task has no status field of its own at all. This
  // is just a pointer to "where was I typing," unrelated to that.

  CollectionReference bookmarksFor(String teacherId) => _db
      .collection('teacherContinueBookmarks')
      .doc(teacherId)
      .collection('bookmarks');

  String _bookmarkId({
    required String level,
    required String contentId,
    String? unitId,
    String? lessonId,
    String? activityId,
  }) => [
    level,
    contentId,
    unitId,
    lessonId,
    activityId,
  ].map((p) => p ?? '_').join('__');

  /// Resolves display titles for whichever ancestor IDs are non-null, so
  /// ContinueBookmarkButton (on the create/edit forms) doesn't need every
  /// title threaded through as a widget constructor param -- it already
  /// has the IDs on hand, this fills in the names with a few cheap reads
  /// only when the teacher actually taps the bookmark button (not on
  /// every build).
  Future<Map<String, String>> resolveHierarchyTitles({
    required String contentId,
    String? unitId,
    String? lessonId,
    String? activityId,
  }) async {
    final result = <String, String>{};

    final contentDoc = await personalizedContent.doc(contentId).get();
    result['contentTitle'] =
        (contentDoc.data() as Map<String, dynamic>?)?['title'] as String? ??
        'Content';

    if (unitId != null) {
      final unitDoc = await personalizedUnits(contentId).doc(unitId).get();
      result['unitTitle'] =
          (unitDoc.data() as Map<String, dynamic>?)?['title'] as String? ??
          'Unit';
    }
    if (unitId != null && lessonId != null) {
      final lessonDoc = await personalizedLessons(
        contentId,
        unitId,
      ).doc(lessonId).get();
      result['lessonTitle'] =
          (lessonDoc.data() as Map<String, dynamic>?)?['title'] as String? ??
          'Lesson';
    }
    if (unitId != null && lessonId != null && activityId != null) {
      final activityDoc = await personalizedActivities(
        contentId,
        unitId,
        lessonId,
      ).doc(activityId).get();
      result['activityTitle'] =
          (activityDoc.data() as Map<String, dynamic>?)?['title'] as String? ??
          'Activity';
    }

    return result;
  }

  Future<void> saveContinueBookmark({
    required String teacherId,
    required String level, // 'unit' | 'lesson' | 'activity' | 'task'
    required String contentId,
    required String contentTitle,
    String? unitId,
    String? unitTitle,
    String? lessonId,
    String? lessonTitle,
    String? activityId,
    String? activityTitle,
    // Whatever the teacher had typed into the create form at save time
    // (title, and level-specific fields like xpBase/turn-in dates for
    // activities, or type/question/data for tasks) -- so "Continue" can
    // reopen the SAME create form pre-filled, not just the parent list
    // screen with the in-progress text lost.
    Map<String, dynamic>? formData,
  }) => bookmarksFor(teacherId)
      .doc(
        _bookmarkId(
          level: level,
          contentId: contentId,
          unitId: unitId,
          lessonId: lessonId,
          activityId: activityId,
        ),
      )
      .set({
        'level': level,
        'contentId': contentId,
        'contentTitle': contentTitle,
        'unitId': unitId,
        'unitTitle': unitTitle,
        'lessonId': lessonId,
        'lessonTitle': lessonTitle,
        'activityId': activityId,
        'formData': formData,
        'activityTitle': activityTitle,
        'savedAt': FieldValue.serverTimestamp(),
      });

  Stream<QuerySnapshot> getContinueBookmarksStream(String teacherId) =>
      bookmarksFor(teacherId).orderBy('savedAt', descending: true).snapshots();

  Future<void> clearContinueBookmark(String teacherId, String bookmarkId) =>
      bookmarksFor(teacherId).doc(bookmarkId).delete();
}
