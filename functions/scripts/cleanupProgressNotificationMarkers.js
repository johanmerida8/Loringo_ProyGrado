// scripts/cleanupProgressNotificationMarkers.js
//
// One-time cleanup: the overdue / closing-soon notifiers used to write their
// "already notified" markers (`overdueNotifiedAt`, `closingSoonNotifiedAt`)
// onto each student's progress doc, which created an empty progress doc for
// students who never started the activity. The notifiers now dedupe through
// `notifications.dedupKeys` instead, so those markers are dead weight.
//
// For every teacherGroups/{g}/students/{s}/progress/{id} doc that carries one
// of the two marker fields:
//   - if the doc holds NOTHING else (only marker fields, no subcollections)
//     it is a stray doc created by a notifier -> deleted;
//   - otherwise (a real progress doc) only the marker fields are removed.
//
// `performanceNotifiedAt` is NOT touched: it is written after a completion,
// when the doc already exists.
//
// Heads-up: removing an old marker means that pair has no "already notified"
// record anymore, so an overdue/closing-soon pair that was notified before and
// is STILL incomplete can be notified once more by the next run.
//
// Dry run by default: logs what it would do and changes nothing. Pass
// --apply to actually write.
//
// Usage:
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
//     node scripts/cleanupProgressNotificationMarkers.js            # dry run
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
//     node scripts/cleanupProgressNotificationMarkers.js --apply    # write

const admin = require("firebase-admin");

const APPLY = process.argv.includes("--apply");
const MARKER_FIELDS = ["overdueNotifiedAt", "closingSoonNotifiedAt"];

admin.initializeApp();
const db = admin.firestore();

/**
 * Runs the cleanup over every progress doc.
 * @return {Promise<void>} Resolves when finished.
 */
async function main() {
  console.log(APPLY ? "APPLY mode: writing." : "DRY RUN: nothing is written.");
  const snap = await db.collectionGroup("progress").get();
  let strayDocs = 0;
  let strippedDocs = 0;

  for (const doc of snap.docs) {
    // Only the per-student progress under a group roster:
    // teacherGroups/{g}/students/{s}/progress/{id}
    if (!doc.ref.path.startsWith("teacherGroups/")) continue;
    const data = doc.data();
    const markers = MARKER_FIELDS.filter((f) => f in data);
    if (markers.length === 0) continue;

    const onlyMarkers = Object.keys(data).every((k) => MARKER_FIELDS.includes(k));
    const hasSubcollections = (await doc.ref.listCollections()).length > 0;

    if (onlyMarkers && !hasSubcollections) {
      strayDocs++;
      console.log(`DELETE stray doc ${doc.ref.path}`);
      if (APPLY) await doc.ref.delete();
    } else {
      strippedDocs++;
      console.log(`STRIP ${markers.join(", ")} from ${doc.ref.path}`);
      if (APPLY) {
        const update = {};
        for (const f of markers) update[f] = admin.firestore.FieldValue.delete();
        await doc.ref.update(update);
      }
    }
  }

  console.log(
      `${APPLY ? "Deleted" : "Would delete"} stray docs: ${strayDocs}. ` +
      `${APPLY ? "Stripped" : "Would strip"} marker fields from real docs: ` +
      `${strippedDocs}.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
