// scripts/cleanupImageItemFields.js
//
// One-time cleanup: `moderationStatus` and `isVisible` on
// mediaLibrary/{ownerId}/categories/{categoryId}/imageItems/{imageId} were
// leftovers of the old manual approve/reject flow. Moderation is now automatic
// (uploadModeratedImage rejects before anything is saved), every doc was
// always 'approved' / true and nothing reads either field. The app no longer
// writes them; this removes them from the existing docs.
//
// Only docs where moderationStatus === 'approved' and isVisible === true (or
// the field is already missing) are touched. Any doc with another value
// (rejected / hidden) is skipped and reported. `isModerated` and every other
// field are left alone.
//
// Dry run by default: logs what it would do and changes nothing. Pass
// --apply to actually write.
//
// Usage:
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
//     node scripts/cleanupImageItemFields.js            # dry run
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
//     node scripts/cleanupImageItemFields.js --apply    # write

const admin = require("firebase-admin");

const APPLY = process.argv.includes("--apply");
const BATCH_SIZE = 400;

admin.initializeApp();
const db = admin.firestore();

/**
 * Removes the two legacy fields from every mediaLibrary imageItem.
 * @return {Promise<void>}
 */
async function main() {
  const snap = await db.collectionGroup("imageItems").get();

  const toClean = [];
  let skipped = 0;
  let alreadyClean = 0;

  for (const doc of snap.docs) {
    if (!doc.ref.path.startsWith("mediaLibrary/")) continue;
    const data = doc.data();
    const hasStatus = "moderationStatus" in data;
    const hasVisible = "isVisible" in data;

    if (!hasStatus && !hasVisible) {
      alreadyClean++;
      continue;
    }
    const statusOk = !hasStatus || data.moderationStatus === "approved";
    const visibleOk = !hasVisible || data.isVisible === true;
    if (!statusOk || !visibleOk) {
      skipped++;
      console.log(`SKIP ${doc.ref.path}: moderationStatus=` +
        `${data.moderationStatus} isVisible=${data.isVisible}`);
      continue;
    }
    toClean.push(doc.ref);
  }

  console.log(`${APPLY ? "APPLY" : "DRY RUN"}: ${toClean.length} docs to ` +
    `clean, ${skipped} skipped, ${alreadyClean} already clean.`);

  if (!APPLY) {
    console.log("Nothing written. Re-run with --apply to write.");
    return;
  }

  for (let i = 0; i < toClean.length; i += BATCH_SIZE) {
    const batch = db.batch();
    for (const ref of toClean.slice(i, i + BATCH_SIZE)) {
      batch.update(ref, {
        moderationStatus: admin.firestore.FieldValue.delete(),
        isVisible: admin.firestore.FieldValue.delete(),
      });
    }
    await batch.commit();
    console.log(`Committed ${Math.min(i + BATCH_SIZE, toClean.length)}` +
      `/${toClean.length}`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
