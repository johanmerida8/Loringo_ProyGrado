// scripts/migrateGroupHistory.js
//
// One-time migration: copies each student's legacy `groupHistory` ARRAY
// (on the root students/{studentId} doc) into the new subcollection
//   students/{studentId}/groupHistory/{groupId}  ->  {groupId, joinedAt}
// one doc per group, using the array entry's own `joinedAt` (a Timestamp)
// when it has one. When a group appears more than once in the array
// (it used to duplicate on rejoin), the most recent `joinedAt` wins.
//
// Safe to re-run: an entry that already exists in the subcollection is
// left alone. Does NOT delete the legacy array -- the app still reads it
// as a fallback (Database._groupHistoryIds) until you remove it once every
// student is migrated and verified.
//
// Dry run by default: logs what it would write and writes nothing. Pass
// --apply to actually write.
//
// Usage:
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
//     node scripts/migrateGroupHistory.js            # dry run
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
//     node scripts/migrateGroupHistory.js --apply    # write

const admin = require("firebase-admin");

const APPLY = process.argv.includes("--apply");

admin.initializeApp();
const db = admin.firestore();

/**
 * @param {*} value A Firestore Timestamp, Date, or anything else.
 * @return {number} Milliseconds since epoch, or 0 if not a date.
 */
function toMillis(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return 0;
}

/**
 * Runs the migration over every student doc.
 * @return {Promise<void>} Resolves when finished.
 */
async function main() {
  console.log(APPLY ? "APPLY mode: writing." : "DRY RUN: nothing is written.");
  const snap = await db.collection("students").get();
  let studentsWithArray = 0;
  let toCreate = 0;
  let alreadyThere = 0;

  for (const studentDoc of snap.docs) {
    const legacy = studentDoc.data().groupHistory;
    if (!Array.isArray(legacy) || legacy.length === 0) continue;
    studentsWithArray++;

    // groupId -> the entry with the most recent joinedAt
    const latest = new Map();
    for (const entry of legacy) {
      if (!entry || !entry.groupId) continue;
      const prev = latest.get(entry.groupId);
      if (!prev || toMillis(entry.joinedAt) >= toMillis(prev.joinedAt)) {
        latest.set(entry.groupId, entry);
      }
    }

    const historyCol = studentDoc.ref.collection("groupHistory");
    for (const [groupId, entry] of latest) {
      const ref = historyCol.doc(groupId);
      if ((await ref.get()).exists) {
        alreadyThere++;
        continue;
      }
      toCreate++;
      console.log(`${studentDoc.id}: groupHistory/${groupId}`);
      if (APPLY) {
        await ref.set({
          groupId,
          joinedAt: entry.joinedAt || null,
        });
      }
    }
  }

  console.log(
      `Students with a legacy array: ${studentsWithArray}. ` +
      `${APPLY ? "Created" : "Would create"}: ${toCreate}. ` +
      `Already in the subcollection: ${alreadyThere}.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
