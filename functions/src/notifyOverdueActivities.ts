// functions/src/notifyOverdueActivities.ts
//
// Daily cron that finds activities whose `dueDate` has passed and are
// still incomplete for one or more assigned students, and alerts both
// the owning teacher AND the student's parent — the "inactivity" signal
// for this app: a student is flagged not because they haven't opened
// the app (no session tracking exists for students, who log in via
// access code, not Firebase Auth), but because assigned work went past
// its deadline unsubmitted. Originally teacher-only; the parent was
// added once parent_home_screen.dart grew a self-serve Follow-ups
// dashboard (Past Due / Due Today) — a push notification now
// complements that dashboard for a parent who isn't actively checking
// the app, rather than the dashboard being the only way to find out.
//
// Also folds in `closeDate`: since turn_in_widget.dart's validation
// guarantees closeDate >= dueDate whenever both are set, any activity
// whose closeDate has passed necessarily already has its dueDate
// passed too — so it's already caught by this function's existing
// `dueDate < now` query below. No second query needed; the per-activity
// check just upgrades the message to a stronger "window closed" notice
// when that's the case.

import { onSchedule } from "firebase-functions/scheduler";
import * as logger from "firebase-functions/logger";
import { defineSecret } from "firebase-functions/params";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

const ONESIGNAL_APP_ID = defineSecret("ONESIGNAL_APP_ID");
const ONESIGNAL_REST_API_KEY = defineSecret("ONESIGNAL_REST_API_KEY");

/**
 * Sends one OneSignal push to a single teacher, by their Firebase Auth
 * uid (same external_user_id registration OneSignalNotificationService
 * already does for teachers on login — see auth_gate.dart).
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
    // Swallowed, not thrown — same reasoning as scheduledNotifications.ts's
    // pushToParent: one teacher's OneSignal failure shouldn't abort the
    // rest of the run.
  }
}

/**
 * Sends one OneSignal push to a single parent — same shape as
 * scheduledNotifications.ts's pushToParent, duplicated locally rather
 * than imported since each notification function in this codebase is
 * kept self-contained (see scheduledNotifications.ts's file-level
 * comment on why these stay separate, single-purpose files).
 * @param {string} parentUserId The parent's Firebase Auth uid.
 * @param {string} title The push notification title.
 * @param {string} body The push notification body.
 * @return {Promise<void>} Resolves once the push attempt completes.
 */
async function pushToParent(
  parentUserId: string,
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
      include_external_user_ids: [parentUserId],
      headings: { en: title },
      contents: { en: body },
    }),
  });

  if (response.status !== 200) {
    const result = await response.json();
    logger.error(`OneSignal error for parent ${parentUserId}:`, result);
    // Swallowed for the same reason as pushToTeacher above.
  }
}

/**
 * Runs once a day. Unlike notifyScheduledActivities's hourly cadence
 * (which exists because scheduledDate carries a specific time-of-day
 * that's meaningful to hit close to), overdue detection isn't
 * time-critical the same way — a student who missed a deadline doesn't
 * need to be flagged within the hour, once a day is enough to keep
 * teachers informed without extra invocation cost.
 */
export const notifyOverdueActivities = onSchedule(
  {
    schedule: "0 8 * * *",
    timeZone: "America/La_Paz",
    secrets: [ONESIGNAL_APP_ID, ONESIGNAL_REST_API_KEY],
  },
  async () => {
    const db = getFirestore();
    const now = Timestamp.now();

    // collectionGroup query across every 'activities' subcollection —
    // same pattern as scheduledNotifications.ts — for any activity
    // whose deadline has passed. Requires a composite index on
    // (dueDate) for the 'activities' collection group.
    const overdueSnap = await db
      .collectionGroup("activities")
      .where("dueDate", "<", now)
      .get();

    if (overdueSnap.empty) {
      logger.info("notifyOverdueActivities: no overdue activities");
      return;
    }

    logger.info(
      `notifyOverdueActivities: ${overdueSnap.size} overdue activity(ies) to check`
    );

    // teacherId -> Set of "childName: activityTitle" strings, so one
    // teacher gets one push listing every overdue student/activity
    // pair under their groups, not one push per student. parentsToNotify
    // mirrors the same shape, one entry per parent instead of teacher.
    const teachersToNotify = new Map<string, Set<string>>();
    const parentsToNotify = new Map<string, Set<string>>();

    for (const activityDoc of overdueSnap.docs) {
      const activityId = activityDoc.id;
      const activityTitle = (activityDoc.data().title as string | undefined) ?? "an activity";
      // closeDate >= dueDate is enforced client-side (turn_in_widget.dart),
      // so reaching this loop at all already implies dueDate has passed;
      // this just tells us whether the harder cutoff has ALSO passed, to
      // pick the stronger wording below.
      const closeTimestamp = activityDoc.data().closeDate as Timestamp | undefined;
      const isClosed = !!closeTimestamp && closeTimestamp.toMillis() < now.toMillis();
      // path segments: content / {contentId} / units / {unitId} /
      // lessons / {lessonId} / activities / {activityId}
      const contentId = activityDoc.ref.path.split("/")[1];

      const contentDoc = await db.collection("content").doc(contentId).get();
      if (!contentDoc.exists) continue;

      const assignedGroupIds = (contentDoc.data()?.assignedTo as string[]) ?? [];
      if (assignedGroupIds.length === 0) continue;

      for (const groupId of assignedGroupIds) {
        const groupDoc = await db.collection("teacherGroups").doc(groupId).get();
        if (!groupDoc.exists) continue;
        const teacherId = groupDoc.data()?.teacherId as string | undefined;
        if (!teacherId) continue;

        const groupStudentsSnap = await db
          .collection("teacherGroups")
          .doc(groupId)
          .collection("students")
          .get();

        for (const studentRefDoc of groupStudentsSnap.docs) {
          const studentId = studentRefDoc.id;

          const progressDoc = await db
            .collection("students")
            .doc(studentId)
            .collection("progress")
            .doc(activityId)
            .get();
          const isCompleted = progressDoc.exists && progressDoc.data()?.isCompleted === true;
          if (isCompleted) continue;

          // Dedup: skip pairs already flagged to this teacher on a
          // previous run, so staying overdue doesn't re-notify every
          // day. Marker lives on the (possibly not-yet-existent)
          // progress doc itself, since that's the natural per-student
          // per-activity record — merge:true creates it if absent
          // without touching completion fields.
          if (progressDoc.exists && progressDoc.data()?.overdueNotifiedAt) {
            continue;
          }

          const studentDoc = await db.collection("students").doc(studentId).get();
          const childName = (studentDoc.data()?.names as string | undefined) ?? "a student";
          const parentId = studentDoc.data()?.parentId as string | undefined;

          const pairLabel = `${childName}: ${activityTitle}${isClosed ? " (window closed)" : ""}`;

          if (!teachersToNotify.has(teacherId)) {
            teachersToNotify.set(teacherId, new Set());
          }
          teachersToNotify.get(teacherId)!.add(pairLabel);

          if (parentId) {
            if (!parentsToNotify.has(parentId)) {
              parentsToNotify.set(parentId, new Set());
            }
            parentsToNotify.get(parentId)!.add(pairLabel);
          }

          await progressDoc.ref.set(
            { overdueNotifiedAt: Timestamp.now() },
            { merge: true }
          );
        }
      }
    }

    logger.info(
      `notifyOverdueActivities: notifying ${teachersToNotify.size} teacher(s)`
    );

    const sends: Promise<void>[] = [];
    for (const [teacherId, pairs] of teachersToNotify) {
      const summary = Array.from(pairs).slice(0, 5).join("; ");
      const extra = pairs.size > 5 ? ` and ${pairs.size - 5} more` : "";
      const title = "Overdue activity alert";
      const body = `${summary}${extra} — past due and not yet completed.`;

      sends.push(pushToTeacher(teacherId, title, body));
      // Same in-app notification-history pattern as
      // scheduledNotifications.ts's parent write and
      // reportNotifications.ts's sendReportNotification.
      sends.push(
        db
          .collection("notifications")
          .add({
            userId: teacherId,
            type: "activity_overdue",
            title,
            message: body,
            isRead: false,
            createdAt: Timestamp.now(),
          })
          .then(() => undefined)
      );
    }

    logger.info(
      `notifyOverdueActivities: notifying ${parentsToNotify.size} parent(s)`
    );

    for (const [parentId, pairs] of parentsToNotify) {
      const summary = Array.from(pairs).slice(0, 5).join("; ");
      const extra = pairs.size > 5 ? ` and ${pairs.size - 5} more` : "";
      // Distinct copy from the teacher push above — same principle
      // scheduledNotifications.ts follows (different audience, different
      // wording), not a shared generic template.
      const title = "Overdue activity";
      const body = `${summary}${extra} — past due and not yet completed.`;

      sends.push(pushToParent(parentId, title, body));
      sends.push(
        db
          .collection("notifications")
          .add({
            userId: parentId,
            type: "activity_overdue",
            title,
            message: body,
            isRead: false,
            createdAt: Timestamp.now(),
          })
          .then(() => undefined)
      );
    }

    await Promise.all(sends);
    logger.info("notifyOverdueActivities: done");
  }
);
