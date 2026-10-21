// functions/src/activityCreatedNotifications.ts
//
// Firestore onCreate trigger: notifies the parent the moment a teacher
// creates an activity that's available right away (no "Schedule Activity"
// date set, turn_in_widget.dart). This is one of the few Firestore-
// triggered functions in the app, added deliberately as an exception to
// the poll-based design documented in NOTIFICATIONS.md decision #3 — the
// hourly notifyScheduledActivities (scheduledNotifications.ts) still
// covers activities that unlock LATER via scheduledDate; this only
// covers the "available immediately" case, which used to wait up to an
// hour for nothing (there's no future moment to poll for — the activity
// is already open the instant it's created).
//
// scheduledDate is validated client-side (turn_in_widget.dart's
// validateTurnInSettings) to always be strictly in the future, so if
// it's present on a freshly-created doc this trigger steps aside and
// lets notifyScheduledActivities pick it up when that time arrives —
// notifying both here and there would double-push the same parent.
//
// REALTIME + SCHEDULED BACKSTOP: same two-export pattern as
// notifyStudentPerformance.ts. notifyActivityCreated (below) fires
// immediately on creation; notifyActivityCreatedFallback is a daily cron
// safety-net that catches anything the trigger missed (cold start,
// deploy gap, transient failure) by scanning activities created in the
// last 48h. Both funnel into notifyForActivity, and both are guarded by
// the SAME activityCreatedNotifiedAt dedup marker on the activity doc, so
// running both is safe, not double-push-risky — same reasoning as
// notifyStudentPerformance.ts's performanceNotifiedAt marker.

import { onDocumentCreated } from "firebase-functions/firestore";
import { onSchedule } from "firebase-functions/scheduler";
import * as logger from "firebase-functions/logger";
import { defineSecret } from "firebase-functions/params";
import {
  getFirestore,
  Timestamp,
  DocumentData,
  DocumentReference,
} from "firebase-admin/firestore";

const ONESIGNAL_APP_ID = defineSecret("ONESIGNAL_APP_ID");
const ONESIGNAL_REST_API_KEY = defineSecret("ONESIGNAL_REST_API_KEY");

/**
 * Sends one OneSignal push to a single parent. Same shape as the
 * pushToParent helper in scheduledNotifications.ts — duplicated rather
 * than shared, consistent with this codebase's existing convention of
 * keeping each notification function file self-contained (see
 * scheduledNotifications.ts's header comment on why).
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
  }
}

/**
 * Formats a due date the same way notifyScheduledActivities does:
 * "Jul 30, 2026", no time-of-day.
 * @param {Date} d The due date to format.
 * @return {string} The formatted date.
 */
function formatDueDate(d: Date): string {
  const months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ];
  return `${months[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;
}

/**
 * Notifies every parent whose child is assigned a newly-available activity,
 * then stamps activityCreatedNotifiedAt on the activity doc so neither the
 * realtime trigger nor the daily fallback scan reports it again. Shared by
 * both exports below -- this is the one place the actual "who gets
 * notified and what it says" logic lives, so it can't drift between the
 * two call sites (same shape as notifyStudentPerformance.ts's
 * reportCompletion).
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {string} contentId The activity's parent content doc id.
 * @param {string} activityId The activity's document id (for logging only).
 * @param {DocumentReference} activityRef Reference to the activity doc.
 * @param {DocumentData} activity The activity doc's field data.
 * @return {Promise<boolean>} true if a notification was actually sent.
 */
async function notifyForActivity(
  db: FirebaseFirestore.Firestore,
  contentId: string,
  activityId: string,
  activityRef: DocumentReference,
  activity: DocumentData
): Promise<boolean> {
  // Has a future unlock date — notifyScheduledActivities (hourly poll)
  // will notify when it actually opens. Nothing to do here.
  if (activity.scheduledDate) {
    logger.info(
      `notifyForActivity: ${activityId} has a scheduledDate, deferring to notifyScheduledActivities`
    );
    return false;
  }

  if (activity.activityCreatedNotifiedAt) {
    return false;
  }

  const contentDoc = await db.collection("content").doc(contentId).get();
  if (!contentDoc.exists) return false;

  // Content can be assigned to multiple groups at once (see
  // shareContentWithGroup/unshareContentFromGroup in database.dart) --
  // notify every group's students, not just one.
  const groupIds = (contentDoc.data()?.assignedTo as string[] | undefined) ?? [];
  if (groupIds.length === 0) {
    logger.info(`notifyForActivity: content ${contentId} isn't assigned to any group`);
    return false;
  }

  const dueTimestamp = activity.dueDate as Timestamp | undefined;

  // parentUserId -> childNames, same one-push-per-parent aggregation
  // as notifyScheduledActivities.
  const parentsToNotify = new Map<string, Set<string>>();

  const groupStudentsSnaps = await Promise.all(
    groupIds.map((groupId) =>
      db.collection("teacherGroups").doc(groupId).collection("students").get()
    )
  );

  for (const groupStudentsSnap of groupStudentsSnaps) {
    for (const studentRefDoc of groupStudentsSnap.docs) {
      const studentDoc = await db.collection("students").doc(studentRefDoc.id).get();
      if (!studentDoc.exists) continue;

      const studentData = studentDoc.data()!;
      const parentId = studentData.parentId as string | undefined;
      if (!parentId) continue;

      const childName = (studentData.names as string | undefined) ?? "your child";
      if (!parentsToNotify.has(parentId)) {
        parentsToNotify.set(parentId, new Set());
      }
      parentsToNotify.get(parentId)!.add(childName);
    }
  }

  if (parentsToNotify.size === 0) {
    logger.info(`notifyForActivity: no parents to notify for content ${contentId}`);
    return false;
  }

  logger.info(
    `notifyForActivity: notifying ${parentsToNotify.size} parent(s) for new activity ${activityId}`
  );

  const title = "New activity available!";

  const sends: Promise<void>[] = [];
  for (const [parentId, childNames] of parentsToNotify) {
    const names = Array.from(childNames).join(", ");
    const body = dueTimestamp ?
      `New activity for ${names} — due ${formatDueDate(dueTimestamp.toDate())}.` :
      `New activity available now for ${names}.`;

    sends.push(pushToParent(parentId, title, body));
    sends.push(
      db
        .collection("notifications")
        .add({
          userId: parentId,
          type: "activity_scheduled",
          title,
          message: body,
          isRead: false,
          createdAt: Timestamp.now(),
        })
        .then(() => undefined)
    );
  }

  sends.push(
    activityRef
      .set({ activityCreatedNotifiedAt: Timestamp.now() }, { merge: true })
      .then(() => undefined)
  );

  await Promise.all(sends);
  return true;
}

// ── Realtime: fires the instant a teacher creates an activity ────────────
export const notifyActivityCreated = onDocumentCreated(
  {
    document:
      "content/{contentId}/units/{unitId}/lessons/{lessonId}/activities/{activityId}",
    secrets: [ONESIGNAL_APP_ID, ONESIGNAL_REST_API_KEY],
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const db = getFirestore();
    const sent = await notifyForActivity(
      db,
      event.params.contentId,
      event.params.activityId,
      snap.ref,
      snap.data()
    );
    logger.info(`notifyActivityCreated: ${event.params.activityId} -> ${sent ? "notified" : "skipped"}`);
  }
);

// ── Daily safety net: catches anything the realtime trigger missed ───────
export const notifyActivityCreatedFallback = onSchedule(
  {
    schedule: "15 8 * * *",
    timeZone: "America/La_Paz",
    secrets: [ONESIGNAL_APP_ID, ONESIGNAL_REST_API_KEY],
  },
  async () => {
    const db = getFirestore();
    const now = Timestamp.now();
    const since = Timestamp.fromMillis(now.toMillis() - 48 * 60 * 60 * 1000);

    // collectionGroup query across every content/.../activities
    // subcollection in the app for anything created in the last 48h.
    // Requires a composite/field-override index on (createdAt) for the
    // 'activities' collection group (see firestore.indexes.json).
    const recentlyCreatedSnap = await db
      .collectionGroup("activities")
      .where("createdAt", ">=", since)
      .get();

    // Filter in-memory: same scheduledDate/dedup checks notifyForActivity
    // itself applies, done here too so the log line below reflects what's
    // actually going to be processed, not just what the query returned.
    const toProcess = recentlyCreatedSnap.docs.filter(
      (doc) => !doc.data().scheduledDate && !doc.data().activityCreatedNotifiedAt
    );

    if (toProcess.length === 0) {
      logger.info("notifyActivityCreatedFallback: nothing missed in the last 48h");
      return;
    }

    logger.info(
      `notifyActivityCreatedFallback: ${toProcess.length} activity(ies) to check`
    );

    let notifiedCount = 0;
    for (const activityDoc of toProcess) {
      // path segments: content / {contentId} / units / ... / activities / {activityId}
      const contentId = activityDoc.ref.path.split("/")[1];
      const sent = await notifyForActivity(
        db,
        contentId,
        activityDoc.id,
        activityDoc.ref,
        activityDoc.data()
      );
      if (sent) notifiedCount++;
    }

    logger.info(`notifyActivityCreatedFallback: sent ${notifiedCount} notification(s)`);
  }
);
