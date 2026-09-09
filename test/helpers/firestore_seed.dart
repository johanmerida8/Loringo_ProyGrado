import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

/// Small seed builders for the Firestore document shapes Database expects,
/// so individual test files don't each hand-roll the same nested documents.
/// Shapes are taken directly from lib/services/database/database.dart —
/// extend this file (don't duplicate seeding logic in test files) as more
/// Database methods get real coverage.

Future<void> seedUser(
  FakeFirebaseFirestore db, {
  required String uid,
  required String name,
  required String email,
  required String role,
  int xp = 0,
  int streak = 0,
}) {
  return db.collection('users').doc(uid).set({
    'name': name,
    'email': email,
    'role': role,
    'xp': xp,
    'streak': streak,
    'language': 'Spanish',
    'state': 1,
  });
}

/// Seeds the root student profile doc. If [groupId] is given, also seeds
/// that group's roster entry for this student (xp lives there now, not on
/// the root doc — see database.dart's TEACHER GROUPS schema comment) so
/// Database methods that resolve the student's current group via
/// resolveCurrentGroupId() have somewhere valid to write.
Future<void> seedStudent(
  FakeFirebaseFirestore db, {
  required String studentId,
  required String studentName,
  String? parentId,
  String? groupId,
  int xp = 0,
}) async {
  await db.collection('students').doc(studentId).set({
    'studentName': studentName,
    if (parentId != null) 'parentId': parentId,
    if (groupId != null) 'groupId': groupId,
  });
  if (groupId != null) {
    await db
        .collection('teacherGroups')
        .doc(groupId)
        .collection('students')
        .doc(studentId)
        .set({
      'studentId': studentId,
      'status': 'active',
      'xp': xp,
    });
  }
}

Future<void> seedTeacherGroup(
  FakeFirebaseFirestore db, {
  required String groupId,
  required String teacherId,
  required String groupCode,
  String name = 'Test Group',
}) {
  return db.collection('teacherGroups').doc(groupId).set({
    'teacherId': teacherId,
    'groupCode': groupCode,
    'name': name,
  });
}

/// Seeds a prior activity-progress doc, as saveActivityCompletion would
/// have left it after a previous attempt — used to exercise the
/// tie/better/worse retry branches without replaying a first attempt.
/// Lives under the group's own roster entry now, so [groupId] must match
/// whatever groupId the student was seeded with (see seedStudent above).
Future<void> seedActivityProgress(
  FakeFirebaseFirestore db, {
  required String studentId,
  required String groupId,
  required String activityId,
  required String contentId,
  required String unitId,
  required int bestScore,
  int totalAttempts = 1,
  int stars = 1,
  int xpEarned = 0,
}) {
  return db
      .collection('teacherGroups')
      .doc(groupId)
      .collection('students')
      .doc(studentId)
      .collection('progress')
      .doc(activityId)
      .set({
    'type': 'activity',
    'contentId': contentId,
    'unitId': unitId,
    'isCompleted': true,
    'totalAttempts': totalAttempts,
    'bestScore': bestScore,
    'stars': stars,
    'xpEarned': xpEarned,
    'taskAnswers': <String, dynamic>{},
  });
}
