// functions/src/activityUpdatedNotifications.ts
//
// Firestore onUpdate trigger: notifies the parent when a teacher moves an
// existing activity's DUE DATE or CLOSE DATE -- the only edits a parent
// actually has to act on. Title/XP/difficulty edits used to notify too and
// were pure noise; they're ignored now. A scheduledDate change notifies
// nobody here (notifyScheduledActivities announces the activity when it
// actually opens) but still resets its marker below. Deliberately
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
// MARKER RESET: only scheduledDate needs one -- its scheduledNotificationSent
// At marker lives on the activity doc, so a moved scheduledDate clears it.
// dueDate/closeDate need none: the overdue and closing-soon notifiers dedupe
// with a key that includes the date (notifications.dedupKeys), so a moved
// date is simply a new key. (These used to write a marker onto every
// student's progress doc here, which created empty progress docs for
// students who hadn't started the activity.)

import { onDocumentUpdated } from "firebase-functions/firestore";
import * as logger from "firebase-functions/logger";
import { defineSecret } from "firebase-functions/params";
import { getFirestore, Timestamp, DocumentData } from "firebase-admin/firestore";

const ONESIGNAL_APP_ID = defineSecret("ONESIGNAL_APP_ID");
const ONESIGNAL_REST_API_KEY = defineSecret("ONESIGNAL_REST_API_KEY");

// Date fields whose change matters at all...
const WATCHED_FIELDS = ["scheduledDate", "dueDate", "closeDate"] as const;
// ...and the subset that's worth a push to the parent.
const NOTIFY_FIELDS = ["dueDate", "closeDate"] as const;

/**
 * Formats a Timestamp as e.g. "Oct 12" in the app's timezone, for the
 * push body. Null/absent dates render as null so the caller can say the
 * date was removed instead.
 * @param {unknown} value A Firestore Timestamp, or anything else.
 * @return {string | null} The short date, or null if not a Timestamp.
 */
function shortDate(value: unknown): string | null {
  if (!(value instanceof Timestamp)) return null;
  return value.toDate().toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    timeZone: "America/La_Paz",
  });
}

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
      // No date moved -- e.g. a title/XP/difficulty edit, a reorder
      // relink or a dedup-marker stamp from a sibling function. Nothing
      // to notify, nothing to reset.
      return;
    }
    const notifyChanged = NOTIFY_FIELDS.filter((f) => changed.includes(f));

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
    // studentId -> the group whose roster it was found under.
    const studentGroupIds = new Map<string, string>();
    for (let i = 0; i < groupStudentsSnaps.length; i++) {
      for (const doc of groupStudentsSnaps[i].docs) {
        studentGroupIds.set(doc.id, groupIds[i]);
      }
    }
    const studentIds = new Set(studentGroupIds.keys());
    if (studentIds.size === 0) return;

    const resets: Promise<unknown>[] = [];

    // No per-student reset for dueDate/closeDate: the overdue and
    // closing-soon notifiers dedupe with a key that includes the date
    // itself (see notifyOverdueActivities.ts), so moving the date makes a
    // new key and re-arms them. Resetting a marker on every student's
    // progress doc here used to create an empty progress doc for each
    // student who hadn't started the activity.
    // scheduledNotificationSentAt lives on the activity doc itself, not
    // per-student -- only needs one reset, not one per student.
    if (changed.includes("scheduledDate")) {
      resets.push(
        event.data!.after.ref.set({ scheduledNotificationSentAt: null }, { merge: true })
      );
    }

    // Only scheduledDate moved: markers reset, but no parent push.
    if (notifyChanged.length === 0) {
      await Promise.all(resets);
      logger.info(`notifyActivityUpdated: ${activityId} -> reset [${changed.join(", ")}], no push`);
      return;
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

    // e.g. "Due date changed" / "\"Getting Dressed\" for Luca: now due
    // Oct 12 · closes Oct 14."
    const title = notifyChanged.length === 2 ?
      "Activity dates changed" :
      notifyChanged[0] === "dueDate" ? "Due date changed" : "Close date changed";
    const dateParts: string[] = [];
    if (notifyChanged.includes("dueDate")) {
      const d = shortDate(after.dueDate);
      dateParts.push(d ? `now due ${d}` : "no due date anymore");
    }
    if (notifyChanged.includes("closeDate")) {
      const d = shortDate(after.closeDate);
      dateParts.push(d ? `closes ${d}` : "no close date anymore");
    }
    const sends: Promise<unknown>[] = [...resets];
    for (const [parentId, childNames] of parentsToNotify) {
      const names = Array.from(childNames).join(", ");
      const body = `"${activityTitle}" for ${names}: ${dateParts.join(" · ")}.`;

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
