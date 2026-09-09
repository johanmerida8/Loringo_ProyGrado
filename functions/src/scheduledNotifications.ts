// functions/src/scheduledNotifications.ts
//
// Hourly cron (see notifyScheduledActivities's own doc comment below for
// why hourly, not daily) that finds activities whose `scheduledDate`
// falls in the current hour and pushes a notification to the parent of
// every student who now has access to that newly-unlocked content.
//
// This file also exports notifyClosingSoonActivities: a second,
// separately-scoped hourly function that warns a parent when an
// activity's `closeDate` (the hard turn-in cutoff, turn_in_widget.dart)
// is coming up within the next day and the work is still incomplete —
// kept in this file rather than notifyOverdueActivities.ts since it's a
// look-AHEAD check on a schedule-like date, the same shape as
// notifyScheduledActivities below, not an after-the-fact one like that
// other file's dueDate/closeDate-passed checks.
//
// WHY A SEPARATE FUNCTION FROM sendNotification: sendNotification (see
// notifications.ts) is a generic onCall — the client explicitly invokes
// it with a specific userId/title/body. This is fundamentally
// different: nothing in the app calls this, it fires on its own once a
// day, and it has to first FIGURE OUT who to notify by walking the
// content hierarchy and cross-referencing scheduledDate against
// "today." Bundling that discovery logic into the generic onCall would
// make sendNotification's contract fuzzy (sometimes it's "send to this
// exact user", sometimes it's "go figure out who needs a scheduled-
// content ping"). Keeping them separate keeps each function's job
// single-purpose and easy to explain individually in a jury defense.
//
// WHY PARENT, NOT STUDENT: students have no OneSignal registration in
// this app today (only parents do, via external_user_id tied to their
// Firebase Auth uid) — see the parent-facing NotificationService in the
// Flutter app. Building student-side push means a whole new
// registration/permission flow for a 5-9yo user base that mostly
// doesn't hold the phone; the parent already gets notified for
// progress reports, and deciding when their child sits down to do a
// newly-unlocked activity is the parent's call anyway, consistent with
// the app's existing design principle of not pressuring young learners
// directly. See sendScheduledContentNotification below for the
// message itself — it's deliberately a DIFFERENT template from
// sendReportNotification's, since this is a content-availability
// event, not a progress/result event, and conflating the two under one
// message shape would blur what each notification actually means.

import { onSchedule } from "firebase-functions/scheduler";
import * as logger from "firebase-functions/logger";
import { defineSecret } from "firebase-functions/params";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

const ONESIGNAL_APP_ID = defineSecret("ONESIGNAL_APP_ID");
const ONESIGNAL_REST_API_KEY = defineSecret("ONESIGNAL_REST_API_KEY");

/**
 * Sends one OneSignal push to a single parent (by their Firebase Auth
 * uid, which is what's registered as external_user_id on the client —
 * same identifier sendNotification's userId already assumes). Kept as
 * its own small helper so the main scheduled handler below reads as
 * "find who to notify" -> "notify them", not interleaved with fetch()
 * plumbing.
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
    // Deliberately swallowed, not thrown: one parent's OneSignal
    // failure (e.g. they never enabled notifications, so OneSignal has
    // no record of that external_user_id) shouldn't abort the whole
    // day's run and skip every other parent still queued behind them.
  }
}

/**
 * Formats a due date the same way parents see dates elsewhere in the
 * app: "Jul 30, 2026". Kept deliberately simple (no time-of-day) since
 * this only appears inline in a push notification body.
 * @param {Date} d The due date to format.
 * @return {string} The formatted date, e.g. "Jul 30, 2026".
 */
function formatDueDate(d: Date): string {
  const months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ];
  return `${months[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;
}

/**
 * Formats a close TIME the way a parent reads a clock, e.g. "2:30 PM" --
 * used by notifyClosingSoonActivities so the notification states exactly
 * when the window shuts (the time the teacher actually picked) instead of
 * the generic "within 24 hours" wording that used to be there.
 * @param {Date} d The close date/time to format.
 * @return {string} The formatted time, e.g. "2:30 PM".
 */
// d.getHours()/getMinutes() read the CLOCK's own timezone, which on Cloud
// Functions is UTC regardless of the onSchedule({timeZone}) option below
// (that only controls when the cron trigger fires, not what a Date's
// getters return). A 9:30 PM America/La_Paz (UTC-4) closeDate was landing
// on getHours() as 1 (01:30 UTC), rendering as "1:30 AM" instead of
// "9:30 PM". Intl.DateTimeFormat with an explicit timeZone formats in
// that zone regardless of the runtime's own local time.
function formatCloseTime(d: Date): string {
  return new Intl.DateTimeFormat("en-US", {
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
    timeZone: "America/La_Paz",
  }).format(d);
}

/**
 * Runs once every hour, on the hour. Firestore Cloud Scheduler cron
 * syntax: "0 * * * *" = minute 0 of every hour, in the function's
 * configured timeZone.
 *
 * Catches every activity whose scheduledDate has passed and hasn't been
 * notified yet — NOT a narrow "falls within this specific hour" bucket.
 * An earlier version used a [startOfThisHour, startOfNextHour) window,
 * which had a permanent-miss bug: if a teacher set scheduledDate for
 * later in the SAME hour a run had already fired (e.g. the 03:00 run
 * already executed, then at 03:15 a teacher schedules something for
 * 03:20), that activity's window had already been checked and come up
 * empty — by the 04:00 run, 03:20 was in the past, outside its
 * [04:00, 05:00) window too, so it silently NEVER got caught. A
 * `scheduledDate <= now` catch-up query with a persistent per-activity
 * `scheduledNotificationSentAt` marker (mirrors notifyOverdueActivities
 * .ts's `overdueNotifiedAt` dedup pattern) fixes this: any activity
 * whose time has passed gets caught on the very next run, no matter how
 * close to the hour boundary it was scheduled, and the marker keeps it
 * from re-notifying afterward.
 */
export const notifyScheduledActivities = onSchedule(
  {
    schedule: "0 * * * *",
    timeZone: "America/La_Paz",
    secrets: [ONESIGNAL_APP_ID, ONESIGNAL_REST_API_KEY],
  },
  async () => {
    const db = getFirestore();
    const now = Timestamp.now();

    // collectionGroup query across every 'activities' subcollection in
    // the whole app, regardless of which content/unit/lesson it sits
    // under — this is the only practical way to find "any activity
    // whose scheduled moment has arrived" without walking the entire
    // content -> units -> lessons -> activities tree level by level.
    // Requires a composite index on (scheduledDate) for the 'activities'
    // collection group. Firestore inequality filters exclude documents
    // where the field is null or absent, so activities with no
    // scheduledDate (the vast majority — every pre-existing activity,
    // and any new one that never checked "Schedule Activity") are
    // already excluded here, same as before.
    const dueToOpenSnap = await db
      .collectionGroup("activities")
      .where("scheduledDate", "<=", now)
      .get();

    // Filter out activities already flagged on a previous run — can't
    // fold this into the query above (Firestore doesn't support an
    // inequality-on-one-field + "field is missing" filter together), so
    // it's a plain in-memory pass over what's usually a small result set.
    const toNotify = dueToOpenSnap.docs.filter(
      (doc) => !doc.data().scheduledNotificationSentAt
    );

    if (toNotify.length === 0) {
      logger.info("notifyScheduledActivities: nothing newly scheduled to open");
      return;
    }

    logger.info(
      `notifyScheduledActivities: ${toNotify.length} activity(ies) newly open`
    );

    // Each activity doc's path is content/{contentId}/units/{unitId}/
    // lessons/{lessonId}/activities/{activityId} — contentId is what
    // ties back to the content's owning groupId. Deduplicated into a Map
    // keyed by contentId since multiple activities opening in the same
    // run under the same content shouldn't fan out into separate
    // per-activity notifications to the same parent. Also tracks each
    // activity's dueDate (if any) so the notification can tell the
    // parent when the new work is due, not just that it exists.
    const contentIdsToDueDates = new Map<string, Set<Date>>();
    for (const doc of toNotify) {
      // path segments: content / {contentId} / units / {unitId} /
      // lessons / {lessonId} / activities / {activityId}
      const contentId = doc.ref.path.split("/")[1];
      if (!contentIdsToDueDates.has(contentId)) {
        contentIdsToDueDates.set(contentId, new Set());
      }
      const dueTimestamp = doc.data().dueDate as Timestamp | undefined;
      if (dueTimestamp) {
        contentIdsToDueDates.get(contentId)!.add(dueTimestamp.toDate());
      }
    }

    // parentUserId -> { childNames, dueDates } so a parent with two
    // kids in groups that both unlock content today gets ONE push
    // mentioning both, not two separate pushes.
    const parentsToNotify = new Map<
      string,
      { childNames: Set<string>; dueDates: Set<Date> }
    >();

    for (const [contentId, dueDates] of contentIdsToDueDates) {
      const contentDoc = await db.collection("content").doc(contentId).get();
      if (!contentDoc.exists) continue;

      // Content can be assigned to multiple groups at once -- notify
      // every assigned group's students, not just one.
      const groupIds = (contentDoc.data()?.assignedTo as string[] | undefined) ?? [];
      if (groupIds.length === 0) continue;

      const groupStudentsSnaps = await Promise.all(
        groupIds.map((groupId) =>
          db.collection("teacherGroups").doc(groupId).collection("students").get()
        )
      );

      for (const groupStudentsSnap of groupStudentsSnaps) {
        for (const studentRefDoc of groupStudentsSnap.docs) {
          const studentId = studentRefDoc.id;
          const studentDoc = await db.collection("students").doc(studentId).get();
          if (!studentDoc.exists) continue;

          const studentData = studentDoc.data()!;
          const parentId = studentData.parentId as string | undefined;
          const childName = (studentData.names as string | undefined) ?? "your child";
          if (!parentId) continue;

          if (!parentsToNotify.has(parentId)) {
            parentsToNotify.set(parentId, { childNames: new Set(), dueDates: new Set() });
          }
          const entry = parentsToNotify.get(parentId)!;
          entry.childNames.add(childName);
          for (const d of dueDates) entry.dueDates.add(d);
        }
      }
    }

    logger.info(
      `notifyScheduledActivities: notifying ${parentsToNotify.size} parent(s)`
    );

    const sends: Promise<void>[] = [];
    for (const [parentId, { childNames, dueDates }] of parentsToNotify) {
      const names = Array.from(childNames).join(", ");
      // Deliberately distinct template from sendReportNotification's —
      // this is a content-availability event ("something new is ready
      // to do"), not a progress/result event ("here's how it went").
      // See the file-level comment above for why the two are kept
      // separate rather than sharing one generic message shape.
      const title = "New activity available!";
      const dueLabel = Array.from(dueDates)
        .sort((a, b) => a.getTime() - b.getTime())
        .map(formatDueDate)
        .join(", ");
      const body = dueDates.size > 0 ?
        `New activity for ${names} — due ${dueLabel}.` :
        `New content unlocked today for ${names}.`;

      sends.push(pushToParent(parentId, title, body));
      // Mirrors NotificationService.sendReportNotification's Firestore
      // shape (lib/services/notifications/notification_service.dart)
      // so this shows up in the parent's in-app bell/history too, not
      // just as an OS-level push — previously this function only ever
      // called pushToParent, so scheduled-content pings were invisible
      // in NotificationBadge's `notifications` stream.
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

    // Mark every processed activity so it's never picked up again — the
    // dedup half of the fix described in this function's doc comment.
    // merge:true since these docs already exist (they were just read
    // above); this only adds the one field.
    for (const doc of toNotify) {
      sends.push(
        doc.ref
          .set({ scheduledNotificationSentAt: Timestamp.now() }, { merge: true })
          .then(() => undefined)
      );
    }

    await Promise.all(sends);
    logger.info("notifyScheduledActivities: done");
  }
);

/**
 * Runs hourly, same cadence as notifyScheduledActivities above and for
 * the same reason (closeDate carries a specific time-of-day). Looks
 * ahead 24 hours for activities whose `closeDate` is coming up and that
 * are still incomplete, and warns the parent before the window shuts —
 * complementing notifyOverdueActivities.ts's after-the-fact "window
 * closed" wording with a heads-up beforehand. Dedup marker
 * (`closingSoonNotifiedAt`, on the student's progress doc, same pattern
 * as notifyOverdueActivities.ts's `overdueNotifiedAt`) keeps this to one
 * notification per student/activity pair even though a fixed closeDate
 * stays inside the rolling 24h lookahead window across many consecutive
 * hourly runs.
 */
export const notifyClosingSoonActivities = onSchedule(
  {
    schedule: "0 * * * *",
    timeZone: "America/La_Paz",
    secrets: [ONESIGNAL_APP_ID, ONESIGNAL_REST_API_KEY],
  },
  async () => {
    const db = getFirestore();
    const now = new Date();
    const lookahead = new Date(now.getTime() + 24 * 60 * 60 * 1000);

    // Requires a composite index on (closeDate) for the 'activities'
    // collection group, same as the other two collectionGroup queries
    // in this file/notifyOverdueActivities.ts.
    const closingSoonSnap = await db
      .collectionGroup("activities")
      .where("closeDate", ">=", Timestamp.fromDate(now))
      .where("closeDate", "<", Timestamp.fromDate(lookahead))
      .get();

    if (closingSoonSnap.empty) {
      logger.info("notifyClosingSoonActivities: nothing closing in the next 24h");
      return;
    }

    logger.info(
      `notifyClosingSoonActivities: ${closingSoonSnap.size} activity(ies) closing soon to check`
    );

    // parentId -> Set of "childName: activityTitle" pairs, same
    // one-push-per-parent aggregation as the other two functions.
    const parentsToNotify = new Map<string, Set<string>>();

    for (const activityDoc of closingSoonSnap.docs) {
      const activityId = activityDoc.id;
      const activityTitle = (activityDoc.data().title as string | undefined) ?? "an activity";
      const contentId = activityDoc.ref.path.split("/")[1];
      // The actual clock time the teacher picked for closeDate, e.g.
      // "2:30 PM" -- always defined here since this query already
      // filters to closeDate within the next 24h.
      const closeTimestamp = activityDoc.data().closeDate as Timestamp;
      const closeTimeLabel = formatCloseTime(closeTimestamp.toDate());

      const contentDoc = await db.collection("content").doc(contentId).get();
      if (!contentDoc.exists) continue;

      // Content can be assigned to multiple groups at once -- collect
      // students across all of them, deduped, rather than just one.
      const groupIds = (contentDoc.data()?.assignedTo as string[] | undefined) ?? [];
      if (groupIds.length === 0) continue;

      const groupStudentsSnaps = await Promise.all(
        groupIds.map((groupId) =>
          db.collection("teacherGroups").doc(groupId).collection("students").get()
        )
      );
      // studentId -> the group whose roster it was found under, so the
      // per-student progress lookup below can target the right nested
      // path. A student only ever has one active roster doc at a time,
      // so the last group wins if somehow found in more than one.
      const studentGroupIds = new Map<string, string>();
      for (let i = 0; i < groupStudentsSnaps.length; i++) {
        for (const doc of groupStudentsSnaps[i].docs) {
          studentGroupIds.set(doc.id, groupIds[i]);
        }
      }

      for (const [studentId, studentGroupId] of studentGroupIds) {
        const progressDoc = await db
          .collection("teacherGroups")
          .doc(studentGroupId)
          .collection("students")
          .doc(studentId)
          .collection("progress")
          .doc(activityId)
          .get();
        const isCompleted = progressDoc.exists && progressDoc.data()?.isCompleted === true;
        if (isCompleted) continue;

        if (progressDoc.exists && progressDoc.data()?.closingSoonNotifiedAt) {
          continue;
        }

        const studentDoc = await db.collection("students").doc(studentId).get();
        if (!studentDoc.exists) continue;
        const parentId = studentDoc.data()?.parentId as string | undefined;
        if (!parentId) continue;
        const childName = (studentDoc.data()?.names as string | undefined) ?? "your child";

        if (!parentsToNotify.has(parentId)) {
          parentsToNotify.set(parentId, new Set());
        }
        parentsToNotify.get(parentId)!.add(
          `${childName}: ${activityTitle} closes at ${closeTimeLabel}`
        );

        await progressDoc.ref.set(
          { closingSoonNotifiedAt: Timestamp.now() },
          { merge: true }
        );
      }
    }

    logger.info(
      `notifyClosingSoonActivities: notifying ${parentsToNotify.size} parent(s)`
    );

    const sends: Promise<void>[] = [];
    for (const [parentId, pairs] of parentsToNotify) {
      const summary = Array.from(pairs).slice(0, 5).join("; ");
      const extra = pairs.size > 5 ? ` and ${pairs.size - 5} more` : "";
      const title = "Closing soon";
      // Per-item close time is already embedded in each pairLabel (see
      // above), so the body doesn't need its own generic "within 24
      // hours" tail anymore -- states the actual time instead.
      const body = `${summary}${extra}`;

      sends.push(pushToParent(parentId, title, body));
      sends.push(
        db
          .collection("notifications")
          .add({
            userId: parentId,
            type: "activity_closing_soon",
            title,
            message: body,
            isRead: false,
            createdAt: Timestamp.now(),
          })
          .then(() => undefined)
      );
    }

    await Promise.all(sends);
    logger.info("notifyClosingSoonActivities: done");
  }
);
