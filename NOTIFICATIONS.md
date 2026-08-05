# Notifications — what changed and why

Reference doc for the notification-system rework. Read this before touching
anything notification-related so you don't re-derive context that's already
here.

## Where things live

- **Cloud Functions**: `functions/src/`
  - `notifications.ts` — generic `sendNotification` HTTPS callable (client
    passes userId/title/body explicitly). The low-level OneSignal REST call
    every other notification function also does inline (each file is
    self-contained on purpose — see the "why separate functions" note in
    `scheduledNotifications.ts`'s header comment).
  - `reportNotifications.ts` — `sendReportNotification` callable. Looks up
    the student's parent, writes the `notifications` history doc, pushes via
    OneSignal. Called from `unit_quiz_review_screen.dart`'s "Send Report to
    Parent" button, after `Database.saveReportOnly` (which stays client-side
    — it's a multi-collection-scan report-generation algorithm, not
    notification logic).
  - `groupInvitationNotifications.ts` — `sendGroupInvitationNotification`
    callable. Resolves the parent by email server-side, writes the history
    doc, pushes. Called from `invite_student_modal.dart`.
  - `notifyOverdueActivities.ts` — daily 8am scheduled function. Finds
    activities whose `dueDate` has passed and are still incomplete, notifies
    **both the teacher and the parent** (parent was added later — see
    "Design decisions" below). Also upgrades the message to a "window
    closed" variant when `closeDate` has also passed (no second query
    needed — see the file's own comment on why).
  - `scheduledNotifications.ts` — hourly scheduled function, two exports:
    - `notifyScheduledActivities` — notifies the parent when an activity's
      `scheduledDate` has arrived (content newly unlocked).
    - `notifyClosingSoonActivities` — warns the parent when `closeDate` is
      within the next 24h and the activity is still incomplete.
- **Dart**:
  - `lib/screens/teacher/unit_quiz_review_screen.dart` — renamed from
    `student_quiz_review_screen.dart` (it's genuinely unit-quiz-scoped;
    `activity_review_screen.dart` and `lesson_quiz_review_screen.dart` only
    save feedback, never generate a report or notify — confirmed by reading
    all three).
  - `lib/screens/teacher/group_details/invite_student_modal.dart` — calls
    the `sendGroupInvitationNotification` callable instead of inline
    Firestore + OneSignal calls.
  - `lib/services/notifications/notification_service.dart` — **deleted**.
    Its only method (`sendReportNotification`) is fully superseded by the
    Cloud Function of the same name.
  - `lib/services/database/database.dart` — removed the dead
    `generateReport`/`_generateReport` auto-report path from
    `saveQuizCompletion` (confirmed unused: its only live caller,
    `quiz_play_screen.dart`, hardcoded `generateReport: false`).

## Design decisions made along the way

Asked and answered via AskUserQuestion — recorded here so they don't need
re-litigating:

1. **closeDate gets both a warning and an after-the-fact notice.** Before:
   `closeDate` triggered nothing. Now: `notifyClosingSoonActivities` warns
   ahead of time; `notifyOverdueActivities` uses stronger "window closed"
   wording once it's passed.
2. **Overdue now also notifies the parent**, not just the teacher (original
   design was deliberately teacher-only — see the file's old header
   comment). Changed because the parent Follow-ups dashboard
   (`parent_home_screen.dart`) now gives parents a self-serve way to check
   this too; a push complements it for a parent not actively checking the
   app.
3. **Timing stays poll-based** (extend the existing hourly/daily cron jobs)
   rather than adding Firestore-triggered (`onCreate`/`onWrite`) functions —
   there's no trigger-based function anywhere in this codebase, and
   introducing that pattern was out of scope for this work.
4. **Group invitations consolidated onto the same Cloud Functions pattern**
   as report notifications, removing the duplicated inline implementation
   in `invite_student_modal.dart`.
5. **Notification message wording**: kept simple, no "on Loringo" branding
   in the body text (tried it, then explicitly reverted per request), and
   no "Tap to view details" filler.

## Bug found and fixed: scheduled notifications silently never firing

**Symptom**: teacher schedules an activity (`scheduledDate` set correctly —
verified directly in Firestore), but no push, no `notifications` doc, ever.

**Root cause** (confirmed via live Cloud Functions logs + direct Firestore
reads, not guesswork): `notifyScheduledActivities` used to query a narrow
window — `[start of this hour, start of next hour)`, recomputed fresh on
every run. If a teacher scheduled something for later in the *same hour* a
run had already fired (e.g., it's 03:15 and you schedule for 03:20), that
hour's check already happened and missed it. By the next hourly run, 03:20
is already in the past — outside the *new* window too. **Permanently
missed**, every time, for anything scheduled with less than about an hour of
lead time relative to the top of the hour. This is exactly what happened
with two real test activities in the live database (5 min and 2 min of lead
time respectively).

**Fix**: replaced the hour-bucket query with `scheduledDate <= now` (catches
anything whose time has passed, regardless of hour alignment) plus a
persistent `scheduledNotificationSentAt` marker written onto the activity
doc itself, so each one still only notifies once. Same dedup pattern
`notifyOverdueActivities.ts` already used successfully (`overdueNotifiedAt`)
and `notifyClosingSoonActivities` (`closingSoonNotifiedAt`) — this was the
one function still using the old narrow-window approach.

**Also flagged, not yet acted on**: while debugging this, ingress was
temporarily set to allow public access on the affected Cloud Function,
thinking that was needed for the scheduler to reach it. It wasn't the
problem (scheduled functions are invoked by Cloud Scheduler, not public
HTTP) — this should be reverted once things are confirmed working, no
reason to leave a function more open than it needs to be.

## activityCreatedNotifications.ts — the one Firestore-triggered exception

Design decision #3 above said no Firestore-triggered functions, poll-based
only. That held until a real symptom showed it wasn't quite right for one
case: a teacher creates an activity with **no** `scheduledDate` (available
immediately, nothing to poll for) and the parent still waited up to an hour
for the push, because the only thing watching for "new activity" was
`notifyScheduledActivities`'s hourly cron. There's no future moment to poll
toward in that case — the activity is already open the instant it's
created — so polling was strictly worse than a trigger here, not just
slower.

`notifyActivityCreated` (`functions/src/activityCreatedNotifications.ts`) is
an `onDocumentCreated` trigger on
`content/{contentId}/units/{unitId}/lessons/{lessonId}/activities/{activityId}`.
If the new doc has a `scheduledDate`, it steps aside — that's still
`notifyScheduledActivities`'s job when the unlock time arrives (client-side
validation guarantees `scheduledDate` is always in the future at creation
time, so there's no overlap/double-push risk). If there's no
`scheduledDate`, it resolves the parents the same way
`notifyScheduledActivities` does (content → assignedTo groups → students →
parentId) and pushes immediately.

**Not yet deployed** — same as the scheduledDate fix below, this needs
`firebase deploy --only functions` before it does anything in production.

## Status as of last session

- All of the above is implemented, builds clean (`npm run build`), lints
  clean (`npm run lint`).
- **The scheduledDate fix has NOT been deployed yet** — everything else
  (the callables, the overdue/closing-soon additions) IS live in
  `loringo-app` (confirmed via `functions_list_functions` — all appear as
  deployed `v2` functions). Run `firebase deploy --only functions` to ship
  the fix, then re-test with a `scheduledDate` a few minutes out to confirm
  it's caught on the next hourly run.
- Verified directly against the live project (not assumed): function logs
  showed clean hourly runs with correct secrets attached; two real
  activities in Firestore had the exact "just missed the window" timing
  that matches the root cause above.
