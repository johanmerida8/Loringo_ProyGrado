// scripts/migrateQuizzes.js
//
// One-time migration: copies every quiz doc out of the old flat top-level
// `quizzes` collection into its new nested location --
//   content/{contentId}/units/{unitId}/quizzes/{quizId}          (Unit Quiz)
//   content/{contentId}/units/{unitId}/lessons/{lessonId}/quizzes/{quizId}
//                                                                 (Lesson Quiz)
// -- using each doc's OWN stored contentId/unitId/scope/lessonId fields
// (still present on every existing doc) to know where it belongs. Also
// copies every doc in that quiz's `questions` subcollection verbatim.
//
// contentId + unitId are kept on the new doc (denormalized, matches the
// app's Database.createQuiz going forward); scope + lessonId are DROPPED
// from the new doc -- both are now fully expressed by which nested
// collection the doc lives in.
//
// Does NOT touch progress/attempts/reports docs -- those key by quizId
// only and are unaffected by where the quiz definition lives.
// Does NOT delete the old flat docs -- see cleanupLegacyQuizzes.js for
// that, run only after the new app/functions code has been live and
// confirmed working for a while.
//
// Usage:
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
//     node scripts/migrateQuizzes.js [--dry-run]
//
// --dry-run logs exactly what would be written/copied without writing
// anything -- run this first and read the output before the real pass.

const admin = require("firebase-admin");

const DRY_RUN = process.argv.includes("--dry-run");

admin.initializeApp();
const db = admin.firestore();

/**
 * @return {FirebaseFirestore.CollectionReference} The legacy flat
 * top-level `quizzes` collection.
 */
function legacyQuizzesCollection() {
  return db.collection("quizzes");
}

/**
 * @param {string} contentId The quiz's contentId field.
 * @param {string} unitId The quiz's unitId field.
 * @param {string | undefined} lessonId The quiz's lessonId field --
 * present only for scope: 'lesson' docs.
 * @return {FirebaseFirestore.CollectionReference} The new nested
 * collection this quiz belongs in.
 */
function destinationCollection(contentId, unitId, lessonId) {
  const unitRef = db
    .collection("content").doc(contentId)
    .collection("units").doc(unitId);
  return lessonId
    ? unitRef.collection("lessons").doc(lessonId).collection("quizzes")
    : unitRef.collection("quizzes");
}

async function migrate() {
  const legacySnap = await legacyQuizzesCollection().get();
  console.log(`Found ${legacySnap.size} legacy quiz doc(s) to migrate.${DRY_RUN ? " (dry run)" : ""}`);

  let migrated = 0;
  let skipped = 0;
  const perUnitCounts = new Map(); // "contentId/unitId" -> count

  for (const quizDoc of legacySnap.docs) {
    const data = quizDoc.data();
    const contentId = data.contentId;
    const unitId = data.unitId;
    const scope = data.scope;
    const lessonId = data.lessonId;

    if (!contentId || !unitId || (scope !== "unit" && scope !== "lesson")) {
      console.warn(`Skipping ${quizDoc.id}: missing/invalid contentId, unitId, or scope`, data);
      skipped++;
      continue;
    }
    if (scope === "lesson" && !lessonId) {
      console.warn(`Skipping ${quizDoc.id}: scope is 'lesson' but lessonId is missing`, data);
      skipped++;
      continue;
    }

    const destCollection = destinationCollection(contentId, unitId, scope === "lesson" ? lessonId : undefined);
    const destRef = destCollection.doc(quizDoc.id);

    // New doc keeps contentId/unitId; scope/lessonId dropped -- both are
    // now fully expressed by the nested collection this doc lives in.
    const newData = { ...data };
    delete newData.scope;
    delete newData.lessonId;

    const questionsSnap = await quizDoc.ref.collection("questions").get();

    const key = `${contentId}/${unitId}`;
    perUnitCounts.set(key, (perUnitCounts.get(key) || 0) + 1);

    if (DRY_RUN) {
      console.log(
        `[dry run] ${quizDoc.id} -> ${destRef.path} (${questionsSnap.size} question doc(s))`
      );
    } else {
      const batch = db.batch();
      batch.set(destRef, newData);
      for (const qDoc of questionsSnap.docs) {
        batch.set(destRef.collection("questions").doc(qDoc.id), qDoc.data());
      }
      await batch.commit();

      // Spot-check: confirm the copy landed with the same question count.
      const verifySnap = await destRef.collection("questions").get();
      if (verifySnap.size !== questionsSnap.size) {
        console.error(
          `MISMATCH for ${quizDoc.id}: source had ${questionsSnap.size} questions, ` +
          `destination has ${verifySnap.size}`
        );
      }
    }
    migrated++;
  }

  console.log("\n── Summary ──────────────────────────────");
  console.log(`Migrated: ${migrated}`);
  console.log(`Skipped (bad data, needs manual review): ${skipped}`);
  console.log("Per unit:");
  for (const [key, count] of perUnitCounts.entries()) {
    console.log(`  ${key}: ${count} quiz(zes)`);
  }
  if (DRY_RUN) {
    console.log("\nThis was a dry run -- nothing was written. Re-run without --dry-run to apply.");
  } else {
    console.log("\nOld flat docs were left in place untouched. Run cleanupLegacyQuizzes.js " +
      "later, once the new app/functions code has been live and confirmed working.");
  }
}

migrate()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Migration failed:", err);
    process.exit(1);
  });
