// functions/src/notifyStudentPerformance.ts
//
// Notifies the owning teacher, with ONE short push PER completion (not a
// bundled digest — that was tried first and reads as an unreadable wall of
// text once more than a couple of things complete in a day), when a student
// first completes an activity or quiz. Two exports, both funneling into the
// same reportCompletion helper below:
//
//   - notifyStudentPerformanceRealtime — Firestore onDocumentWritten trigger
//     on teacherGroups/{groupId}/students/{studentId}/progress/{progressId}.
//     Fires the instant a student first completes something, so the teacher
//     finds out "in that same moment" instead of waiting for the next
//     scheduled run.
//   - notifyStudentPerformance — daily 8:05am safety-net scan (unchanged
//     query/schedule from before the realtime trigger existed). Catches
//     anything the trigger missed (a cold-start/deploy gap, a transient
//     failure) so nothing silently falls through permanently. In the
//     overwhelmingly common case the trigger already reported everything,
//     so this mostly finds 0 newly-completed docs to send.
//
// Both share the SAME dedup marker (performanceNotifiedAt) on the progress
// doc, so whichever one gets there first "wins" and the other's dedup check
// skips it — running both is safe, not double-push-risky.
//
// WHY THE DEDUP MARKER STILL MATTERS EVEN WITH A REALTIME TRIGGER: unit
// quizzes allow multiple retry attempts (quiz_play_screen.dart's
// maxAttempts), and every attempt independently calls saveQuizCompletion —
// a naive "notify on every write" hook would fire once per retry. Regular
// activities have no attempt cap either, same problem. `firstCompletedAt`
// is written once on first completion and never changes on retries, so
// it's the natural anchor: the realtime trigger only fires the notification
// on the write where firstCompletedAt transitions from unset to set, and
// performanceNotifiedAt then guarantees neither this trigger nor the daily
// scan ever reports that same completion again.
//
// SCORE BANDS: reuses the same 90/70 star thresholds already established
// everywhere else in the codebase (see database.dart's stars calculation
// in saveActivityCompletion/saveQuizCompletion) rather than inventing a new
// cutoff -- stars >= 2 (score >= 70) is "doing well", stars === 1 is
// "needs support".
//
// This is the SECOND Firestore-triggered function in the app (the first is
// activityCreatedNotifications.ts's notifyActivityCreated — see that file
// and NOTIFICATIONS.md for why the app is otherwise poll-based).

import { onSchedule } from "firebase-functions/scheduler";
import { onDocumentWritten } from "firebase-functions/firestore";
import * as logger from "firebase-functions/logger";
import { defineSecret } from "firebase-functions/params";
import { getFirestore, Timestamp, DocumentData, DocumentReference } from "firebase-admin/firestore";

const ONESIGNAL_APP_ID = defineSecret("ONESIGNAL_APP_ID");
const ONESIGNAL_REST_API_KEY = defineSecret("ONESIGNAL_REST_API_KEY");

/**
 * Sends one OneSignal push to a single teacher, by their Firebase Auth uid.
 * Duplicated locally rather than shared -- each notification function file
 * in this codebase is kept self-contained (see scheduledNotifications.ts's
 * file-level comment on why).
 * @param {string} teacherUserId The teacher's Firebase Auth uid.
 * @param {string} title The push notification title.
 * @param {string} body The push notification body.
 * @return {Promise<void>} Resolves once the push attempt completes.
 */
async function pushToTeacher(
  teacherUserId: string,
  title: string,
  body: string
): Promise<void> {
  const response = await fetch("https://onesignal.com/api/v1/notifications", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Basic ${ONESIGNAL_REST_API_KEY.value()}`,
    },
    body: JSON.stringify({
      app_id: ONESIGNAL_APP_ID.value(),
      include_external_user_ids: [teacherUserId],
      headings: { en: title },
      contents: { en: body },
    }),
  });

  if (response.status !== 200) {
    const result = await response.json();
    logger.error(`OneSignal error for teacher ${teacherUserId}:`, result);
    // Swallowed, not thrown -- one teacher's OneSignal failure shouldn't
    // abort the rest of the run, same reasoning as notifyOverdueActivities.
  }
}

/**
 * Resolves a human-readable title for a progress doc's underlying
 * activity/quiz. Quizzes now live nested under
 * content/{contentId}/units/{unitId}/quizzes/{docId} (Unit Quiz) or
 * .../lessons/{lessonId}/quizzes/{docId} (Lesson Quiz) -- lessonId comes
 * straight off the progress doc when present (every quiz completed after
 * the nested-quizzes migration carries it). For a LEGACY progress doc
 * saved before that migration (lessonId absent), falls back to trying the
 * unit-quiz path first, then scanning the unit's lessons for a matching
 * quiz doc -- same fallback the client uses in
 * student_detail_progress_screen.dart's _getQuizInfo. Activities have no
 * stored path beyond contentId+unitId, so that branch loops the unit's
 * lessons looking for a matching activity doc -- bounded by lesson count
 * in one unit, not a full collection scan.
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {string} type Either "quiz" or "activity", from the progress doc.
 * @param {string} docId The progress doc's ID (== the quiz/activity ID).
 * @param {string} contentId The content ID, from the progress doc.
 * @param {string} unitId The unit ID, from the progress doc.
 * @param {string | undefined} lessonId The lesson ID, from the progress
 * doc -- present only for a Lesson Quiz completion, and only once the
 * completion happened after the nested-quizzes migration.
 * @return {Promise<string>} The resolved title, or a generic fallback.
 */
async function resolveTitle(
  db: FirebaseFirestore.Firestore,
  type: string,
  docId: string,
  contentId: string,
  unitId: string,
  lessonId?: string
): Promise<string> {
  if (type === "quiz") {
    const unitRef = db
      .collection("content").doc(contentId)
      .collection("units").doc(unitId);

    if (lessonId) {
      const quizDoc = await unitRef
        .collection("lessons").doc(lessonId)
        .collection("quizzes").doc(docId).get();
      return (quizDoc.data()?.title as string | undefined) ?? "a quiz";
    }

    const unitQuizDoc = await unitRef.collection("quizzes").doc(docId).get();
    if (unitQuizDoc.exists) {
      return (unitQuizDoc.data()?.title as string | undefined) ?? "a quiz";
    }

    const lessonsSnap = await unitRef.collection("lessons").get();
    for (const lessonDoc of lessonsSnap.docs) {
      const quizDoc = await lessonDoc.ref.collection("quizzes").doc(docId).get();
      if (quizDoc.exists) {
        return (quizDoc.data()?.title as string | undefined) ?? "a quiz";
      }
    }
    return "a quiz";
  }

  const lessonsSnap = await db
    .collection("content").doc(contentId)
    .collection("units").doc(unitId)
    .collection("lessons").get();

  for (const lessonDoc of lessonsSnap.docs) {
    const activityDoc = await lessonDoc.ref.collection("activities").doc(docId).get();
    if (activityDoc.exists) {
      return (activityDoc.data()?.title as string | undefined) ?? "an activity";
    }
  }
  return "an activity";
}

/**
 * Reports one student's completion to their teacher: resolves the teacher,
 * sends the push + writes the in-app notifications doc, and stamps
 * performanceNotifiedAt on the progress doc so neither the realtime trigger
 * nor the daily safety-net scan reports it again. Shared by both exports
 * below -- this is the one place the actual "who gets notified and what it
 * says" logic lives, so it can't drift between the two call sites.
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {string} studentId The student's document id.
 * @param {string} groupId The teacher group's document id.
 * @param {DocumentReference} progressRef Reference to the progress doc.
 * @param {DocumentData} data The progress doc's field data.
 * @return {Promise<boolean>} true if a notification was actually sent.
 */
async function reportCompletion(
  db: FirebaseFirestore.Firestore,
  studentId: string,
  groupId: string,
  progressRef: DocumentReference,
  data: DocumentData
): Promise<boolean> {
  if (data.performanceNotifiedAt) return false;

  const stars = data.stars as number | undefined;
  const bestScore = data.bestScore as number | undefined;
  const type = data.type as string | undefined;
  const contentId = data.contentId as string | undefined;
  const unitId = data.unitId as string | undefined;
  const lessonId = data.lessonId as string | undefined;
  // A doc that hasn't recorded a best-scoring attempt yet (shouldn't
  // normally happen alongside firstCompletedAt, but the fields are
  // separately-optional writes) has nothing meaningful to report.
  if (stars === undefined || bestScore === undefined || !type || !contentId || !unitId) {
    return false;
  }

  const studentDoc = await db.collection("students").doc(studentId).get();
  if (!studentDoc.exists) return false;
  const studentName = (studentDoc.data()?.names as string | undefined) ?? "A student";

  const groupDoc = await db.collection("teacherGroups").doc(groupId).get();
  if (!groupDoc.exists) return false;
  const teacherId = groupDoc.data()?.teacherId as string | undefined;
  if (!teacherId) return false;

  const title = await resolveTitle(db, type, progressRef.id, contentId, unitId, lessonId);

  // One short push per completion — "Luca did well in Classroom Objects
  // Quiz" — instead of one bundled, multi-item digest body per teacher.
  const didWell = stars >= 2;
  const pushTitle = didWell ? "Nice work!" : "Needs support";
  const body = `${studentName} ${didWell ? "did well in" : "needs support with"} ${title}`;

  await Promise.all([
    pushToTeacher(teacherId, pushTitle, body),
    db.collection("notifications").add({
      userId: teacherId,
      type: "student_performance",
      title: pushTitle,
      message: body,
      isRead: false,
      createdAt: Timestamp.now(),
    }),
    progressRef.set({ performanceNotifiedAt: Timestamp.now() }, { merge: true }),
  ]);

  return true;
}

// ── Realtime: fires the instant a student first completes something ──────
export const notifyStudentPerformanceRealtime = onDocumentWritten(
  {
    document: "teacherGroups/{groupId}/students/{studentId}/progress/{progressId}",
    secrets: [ONESIGNAL_APP_ID, ONESIGNAL_REST_API_KEY],
    maxInstances: 1,
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after) return; // deletion — nothing to report

    // Only the write where firstCompletedAt transitions from unset to set
    // is a genuine first completion. Every later write to this doc is a
    // retry (or the daily scan's own performanceNotifiedAt stamp, or an
    // improvement-bonus update) — firstCompletedAt never changes once set,
    // so this check alone is what keeps retries from spamming the teacher.
    if (before?.firstCompletedAt || !after.firstCompletedAt) return;

    const db = getFirestore();
    const sent = await reportCompletion(
      db,
      event.params.studentId,
      event.params.groupId,
      event.data!.after.ref,
      after
    );
    logger.info(
      `notifyStudentPerformanceRealtime: ${event.params.progressId} -> ${sent ? "notified" : "skipped"}`
    );
  }
);

// ── Daily safety net: catches anything the realtime trigger missed ───────
export const notifyStudentPerformance = onSchedule(
  {
    schedule: "5 8 * * *",
    timeZone: "America/La_Paz",
    secrets: [ONESIGNAL_APP_ID, ONESIGNAL_REST_API_KEY],
  },
  async () => {
    const db = getFirestore();
    const now = Timestamp.now();
    const since = Timestamp.fromMillis(now.toMillis() - 24 * 60 * 60 * 1000);

    // collectionGroup query across every student's 'progress' subcollection
    // for anything first-completed in the last 24h. Requires a composite
    // index on (firstCompletedAt) for the 'progress' collection group.
    const newlyCompletedSnap = await db
      .collectionGroup("progress")
      .where("firstCompletedAt", ">=", since)
      .get();

    if (newlyCompletedSnap.empty) {
      logger.info("notifyStudentPerformance: no newly-completed progress docs");
      return;
    }

    logger.info(
      `notifyStudentPerformance: ${newlyCompletedSnap.size} newly-completed doc(s) to check`
    );

    let notifiedCount = 0;
    for (const progressDoc of newlyCompletedSnap.docs) {
      // path segments: teacherGroups / {groupId} / students / {studentId} / progress / {docId}
      const pathParts = progressDoc.ref.path.split("/");
      const groupId = pathParts[1];
      const studentId = pathParts[3];
      const sent = await reportCompletion(db, studentId, groupId, progressDoc.ref, progressDoc.data());
      if (sent) notifiedCount++;
    }

    logger.info(`notifyStudentPerformance: sent ${notifiedCount} individual notification(s)`);
  }
);
