// functions/src/activityUpdatedNotifications.ts
//
// Firestore onUpdate trigger: notifies the parent when a teacher edits an
// activity that already exists -- title, XP reward, difficulty, or any of
// the three turn-in dates (scheduledDate/dueDate/closeDate). Deliberately
// separate from activityCreatedNotifications.ts's onCreate trigger: "this
// activity now exists" and "this activity changed" are different events,
// and conflating them would mean a parent who already saw the create
// notification gets no signal at all when the teacher later pushes the
// due date back.
//
// FIELD WATCHLIST, NOT "any write": an activity doc is written to for
// plenty of reasons that aren't a teacher-facing edit at all --
// activityCreatedNotifiedAt/scheduledNotificationSentAt (both markers
// this file's sibling functions stamp on the doc itself) and order/
// requiredActivityId (rewritten by Database._relinkActivityChain on every
// create/delete/reorder in the lesson, per database.dart). None of those
// should trip a parent-facing "updated" notification, so this only fires
// when one of WATCHED_FIELDS actually changed value.
//
// MARKER RESET: if dueDate/closeDate/scheduledDate actually moved, this
// also clears whichever dedup marker that date's own notifier uses
// (closingSoonNotifiedAt / overdueNotifiedAt / scheduledNotificationSentAt)
// -- otherwise a date already notified once under its OLD value would
// stay silently marked "already notified" forever after being edited,
// even though the new value hasn't been announced to anyone yet.

import { onDocumentUpdated } from "firebase-functions/firestore";
import * as logger from "firebase-functions/logger";
import { defineSecret } from "firebase-functions/params";
import { getFirestore, Timestamp, DocumentData } from "firebase-admin/firestore";

const ONESIGNAL_APP_ID = defineSecret("ONESIGNAL_APP_ID");
const ONESIGNAL_REST_API_KEY = defineSecret("ONESIGNAL_REST_API_KEY");

const WATCHED_FIELDS = [
  "title", "xpBase", "difficulty", "scheduledDate", "dueDate", "closeDate",
] as const;

/**
 * Sends one OneSignal push to a single parent -- same shape as every
 * other notification function in this codebase; duplicated rather than
 * imported per this project's existing single-file-per-concern
 * convention (see scheduledNotifications.ts's file-level comment).
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
 * Timestamp-aware equality check for one field between the before/after
 * snapshots of an update -- Firestore Timestamps aren't `===`-comparable
 * even when they represent the same instant, so those compare by
 * milliseconds; everything else (title/xpBase/difficulty) compares by
 * plain value.
 * @param {DocumentData} before The activity doc's data before the write.
 * @param {DocumentData} after The activity doc's data after the write.
 * @param {string} field The field name to compare.
 * @return {boolean} true if the field's value actually changed.
 */
function fieldChanged(before: DocumentData, after: DocumentData, field: string): boolean {
  const b = before[field];
  const a = after[field];
  if (b instanceof Timestamp || a instanceof Timestamp) {
    const bMillis = b instanceof Timestamp ? b.toMillis() : undefined;
    const aMillis = a instanceof Timestamp ? a.toMillis() : undefined;
    return bMillis !== aMillis;
  }
  return b !== a;
}

export const notifyActivityUpdated = onDocumentUpdated(
  {
    document:
      "content/{contentId}/units/{unitId}/lessons/{lessonId}/activities/{activityId}",
    secrets: [ONESIGNAL_APP_ID, ONESIGNAL_REST_API_KEY],
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const changed = WATCHED_FIELDS.filter((f) => fieldChanged(before, after, f));
    if (changed.length === 0) {
      // Nothing a parent needs to know about changed -- e.g. this write
      // was only a reorder relink or a dedup-marker stamp from a sibling
      // function. Nothing to notify, nothing to reset.
      return;
    }

    const db = getFirestore();
    const { contentId, activityId } = event.params;
    const activityTitle = (after.title as string | undefined) ?? "an activity";

    const contentDoc = await db.collection("content").doc(contentId).get();
    if (!contentDoc.exists) return;

    // Content can be assigned to multiple groups at once -- notify every
    // assigned group's students, not just one (same pattern as every
    // other activity-notification function in this codebase).
    const groupIds = (contentDoc.data()?.assignedTo as string[] | undefined) ?? [];
    if (groupIds.length === 0) return;

    const groupStudentsSnaps = await Promise.all(
      groupIds.map((groupId) =>
        db.collection("teacherGroups").doc(groupId).collection("students").get()
      )
    );
    // studentId -> the group whose roster it was found under, so the
    // per-student progress reset below can target the right nested path.
    const studentGroupIds = new Map<string, string>();
    for (let i = 0; i < groupStudentsSnaps.length; i++) {
      for (const doc of groupStudentsSnaps[i].docs) {
        studentGroupIds.set(doc.id, groupIds[i]);
      }
    }
    const studentIds = new Set(studentGroupIds.keys());
    if (studentIds.size === 0) return;

    const resets: Promise<unknown>[] = [];

    // Reset the per-student dedup marker for whichever date actually
    // moved, so the relevant hourly function re-evaluates against the
    // NEW value on its next run instead of staying silent because of a
    // marker already set against the old one.
    if (changed.includes("closeDate") || changed.includes("dueDate")) {
      for (const [studentId, studentGroupId] of studentGroupIds) {
        const update: Record<string, unknown> = {};
        if (changed.includes("closeDate")) update.closingSoonNotifiedAt = null;
        if (changed.includes("dueDate")) update.overdueNotifiedAt = null;
        resets.push(
          db.collection("teacherGroups").doc(studentGroupId).collection("students")
            .doc(studentId).collection("progress").doc(activityId)
            .set(update, { merge: true })
        );
      }
    }
    // scheduledNotificationSentAt lives on the activity doc itself, not
    // per-student -- only needs one reset, not one per student.
    if (changed.includes("scheduledDate")) {
      resets.push(
        event.data!.after.ref.set({ scheduledNotificationSentAt: null }, { merge: true })
      );
    }

    // parentUserId -> childNames, same one-push-per-parent aggregation as
    // every other activity-notification function in this codebase.
    const parentsToNotify = new Map<string, Set<string>>();
    for (const studentId of studentIds) {
      const studentDoc = await db.collection("students").doc(studentId).get();
      if (!studentDoc.exists) continue;
      const studentData = studentDoc.data()!;
      const parentId = studentData.parentId as string | undefined;
      if (!parentId) continue;
      const childName = (studentData.names as string | undefined) ?? "your child";
      if (!parentsToNotify.has(parentId)) parentsToNotify.set(parentId, new Set());
      parentsToNotify.get(parentId)!.add(childName);
    }

    if (parentsToNotify.size === 0) {
      await Promise.all(resets);
      logger.info(`notifyActivityUpdated: ${activityId} -> no parents to notify, reset [${changed.join(", ")}]`);
      return;
    }

    const title = "Activity has been updated!";
    const sends: Promise<unknown>[] = [...resets];
    for (const [parentId, childNames] of parentsToNotify) {
      const names = Array.from(childNames).join(", ");
      const body = `"${activityTitle}" was updated for ${names}.`;

      sends.push(pushToParent(parentId, title, body));
      sends.push(
        db
          .collection("notifications")
          .add({
            userId: parentId,
            type: "activity_updated",
            title,
            message: body,
            isRead: false,
            createdAt: Timestamp.now(),
          })
          .then(() => undefined)
      );
    }

    await Promise.all(sends);
    logger.info(
      `notifyActivityUpdated: ${activityId} -> notified ${parentsToNotify.size} ` +
      `parent(s), reset [${changed.join(", ")}]`
    );
  }
);
