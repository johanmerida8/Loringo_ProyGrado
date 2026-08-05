// functions/src/activityCreatedNotifications.ts
//
// Firestore onCreate trigger: notifies the parent the moment a teacher
// creates an activity that's available right away (no "Schedule Activity"
// date set, turn_in_widget.dart). This is the ONE Firestore-triggered
// function in the app, added deliberately as an exception to the
// poll-based design documented in NOTIFICATIONS.md decision #3 — the
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

import { onDocumentCreated } from "firebase-functions/firestore";
import * as logger from "firebase-functions/logger";
import { defineSecret } from "firebase-functions/params";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

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

export const notifyActivityCreated = onDocumentCreated(
  {
    document:
      "content/{contentId}/units/{unitId}/lessons/{lessonId}/activities/{activityId}",
    secrets: [ONESIGNAL_APP_ID, ONESIGNAL_REST_API_KEY],
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const activity = snap.data();

    // Has a future unlock date — notifyScheduledActivities (hourly poll)
    // will notify when it actually opens. Nothing to do here.
    if (activity.scheduledDate) {
      logger.info(
        `notifyActivityCreated: ${event.params.activityId} has a scheduledDate, deferring to notifyScheduledActivities`
      );
      return;
    }

    const db = getFirestore();
    const { contentId } = event.params;

    const contentDoc = await db.collection("content").doc(contentId).get();
    if (!contentDoc.exists) return;

    const assignedGroupIds = (contentDoc.data()?.assignedTo as string[]) ?? [];
    if (assignedGroupIds.length === 0) {
      logger.info(`notifyActivityCreated: content ${contentId} has no assigned groups`);
      return;
    }

    const dueTimestamp = activity.dueDate as Timestamp | undefined;

    // parentUserId -> childNames, same one-push-per-parent aggregation
    // as notifyScheduledActivities.
    const parentsToNotify = new Map<string, Set<string>>();

    for (const groupId of assignedGroupIds) {
      const groupStudentsSnap = await db
        .collection("teacherGroups")
        .doc(groupId)
        .collection("students")
        .get();

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
      logger.info(`notifyActivityCreated: no parents to notify for content ${contentId}`);
      return;
    }

    logger.info(
      `notifyActivityCreated: notifying ${parentsToNotify.size} parent(s) for new activity ${event.params.activityId}`
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

    await Promise.all(sends);
    logger.info("notifyActivityCreated: done");
  }
);
