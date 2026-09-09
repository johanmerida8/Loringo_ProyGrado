// scripts/cleanupLegacyQuizzes.js
//
// Deletes the old flat top-level `quizzes` collection (and each doc's
// `questions` subcollection) LEFT IN PLACE by migrateQuizzes.js.
//
// DO NOT run this until:
//   1. migrateQuizzes.js has been run successfully in production.
//   2. The new app build (nested quiz paths) and the updated
//      notifyStudentPerformance Cloud Function have been deployed.
//   3. The app has been live for a while with no reports of missing/
//      broken quizzes -- this is the rollback safety net; once you run
//      this, that safety net is gone.
// After running this, also remove the old flat `match /quizzes/{document=**}`
// block from firestore.rules and redeploy rules.
//
// Usage:
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
//     node scripts/cleanupLegacyQuizzes.js [--dry-run]

const admin = require("firebase-admin");

const DRY_RUN = process.argv.includes("--dry-run");

admin.initializeApp();
const db = admin.firestore();

async function cleanup() {
  const legacySnap = await db.collection("quizzes").get();
  console.log(`Found ${legacySnap.size} legacy quiz doc(s) to delete.${DRY_RUN ? " (dry run)" : ""}`);

  let deleted = 0;
  for (const quizDoc of legacySnap.docs) {
    const questionsSnap = await quizDoc.ref.collection("questions").get();

    if (DRY_RUN) {
      console.log(`[dry run] would delete ${quizDoc.ref.path} + ${questionsSnap.size} question doc(s)`);
    } else {
      const batch = db.batch();
      for (const qDoc of questionsSnap.docs) batch.delete(qDoc.ref);
      batch.delete(quizDoc.ref);
      await batch.commit();
    }
    deleted++;
  }

  console.log(`\n${DRY_RUN ? "Would delete" : "Deleted"}: ${deleted} legacy quiz doc(s).`);
  if (!DRY_RUN) {
    console.log("Now remove the old flat `match /quizzes/{document=**}` block from " +
      "firestore.rules and redeploy rules.");
  }
}

cleanup()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Cleanup failed:", err);
    process.exit(1);
  });
