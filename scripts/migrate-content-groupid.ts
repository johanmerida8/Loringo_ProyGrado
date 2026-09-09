// migrate-content-groupid.ts
//
// One-off migration: replaces `content`'s many-to-many `assignedTo: [groupId,
// ...]` array with a single required `groupId` field (and stamps `groupId`
// onto every `quizzes` doc too, denormalized from its content). See
// CLAUDE.md / the "Content/Quiz ownership migration" plan for the full
// rationale — this script is Phase 1 of that migration.
//
// WHAT IT DOES, per `content` doc:
//   - assignedTo.length === 1  -> set groupId = assignedTo[0], drop assignedTo.
//   - assignedTo.length > 1    -> deep-clone the content doc (+ its full
//     units/lessons/activities/tasks tree + every quiz under it) once per
//     group, each clone getting its own groupId and freshly-minted IDs at
//     every level. The original multi-group doc (and its original quizzes)
//     is deleted once every clone has been written successfully. Any
//     student whose own group matches one of the clones has their
//     `progress`/`reports` docs rewritten to point at that clone's IDs
//     instead of the original (now-deleted) ones.
//   - assignedTo.length === 0  -> orphaned draft, never assigned to any
//     group. Skipped and reported — this script never guesses a group for
//     you; assign one manually (or delete the content) before re-running.
//
// USAGE:
//   cd scripts && npm install
//   # point at your Firebase project — either GOOGLE_APPLICATION_CREDENTIALS
//   # env var pointing at a service account JSON, or run inside an
//   # environment with default application credentials (e.g. `gcloud auth
//   # application-default login` for a project you have access to).
//   npx ts-node migrate-content-groupid.ts              # dry run (default)
//   npx ts-node migrate-content-groupid.ts --apply       # actually writes
//
// STRONGLY RECOMMENDED: run --dry-run first and read the full report,
// resolve every orphaned content item, and test --apply against a Firestore
// export/staging project before ever pointing this at production.

import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

const APPLY = process.argv.includes("--apply");

type IdMap = Map<string, string>; // oldId -> newId

interface CloneResult {
  newContentId: string;
  unitIdMap: IdMap;
  lessonIdMap: IdMap;
  activityIdMap: IdMap;
}

// oldContentId -> groupId -> CloneResult, built up as clones are created.
// Used afterward to remap student progress/report docs.
const cloneIndex = new Map<string, Map<string, CloneResult>>();

let contentRenamed = 0;
let contentCloned = 0;
let contentOrphaned = 0;
let quizzesStamped = 0;
let quizzesCloned = 0;
let progressDocsRewritten = 0;
let progressDocsUnresolved = 0;
const orphanedContentIds: string[] = [];

function newId(prefix: string): string {
  return `${prefix}_${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
}

// Firestore doesn't cascade-delete subcollections -- walks every
// subcollection of `docRef` recursively and deletes each doc (and,
// recursively, each of ITS subcollections) before deleting `docRef` itself.
async function deleteDocRecursive(docRef: FirebaseFirestore.DocumentReference): Promise<void> {
  const subcollections = await docRef.listCollections();
  for (const sub of subcollections) {
    const snap = await sub.get();
    for (const doc of snap.docs) {
      await deleteDocRecursive(doc.ref);
    }
  }
  if (APPLY) await docRef.delete();
}

async function cloneQuizzesForUnit(
  contentId: string,
  unitId: string,
  newContentId: string,
  newUnitId: string,
  lessonIdMap: IdMap
): Promise<void> {
  const quizzesSnap = await db
    .collection("quizzes")
    .where("contentId", "==", contentId)
    .where("unitId", "==", unitId)
    .get();

  for (const quizDoc of quizzesSnap.docs) {
    const data = quizDoc.data();
    const newQuizId = newId("quiz");
    const newLessonId =
      data.scope === "lesson" && data.lessonId ? lessonIdMap.get(data.lessonId) ?? data.lessonId : undefined;

    quizzesCloned++;
    if (APPLY) {
      const newQuizRef = db.collection("quizzes").doc(newQuizId);
      // groupId is stamped in a second pass by the caller (cloneContentForGroup),
      // once it knows the destination groupId -- omitted here so this
      // function stays reusable without needing it threaded through.
      await newQuizRef.set({
        ...data,
        contentId: newContentId,
        unitId: newUnitId,
        ...(newLessonId ? { lessonId: newLessonId } : {}),
      });
      const questionsSnap = await quizDoc.ref.collection("questions").get();
      for (const q of questionsSnap.docs) {
        await newQuizRef.collection("questions").doc(q.id).set(q.data());
      }
    }
  }
}

async function cloneContentForGroup(
  contentId: string,
  contentData: FirebaseFirestore.DocumentData,
  groupId: string
): Promise<CloneResult> {
  const newContentId = newId("content");
  const unitIdMap: IdMap = new Map();
  const lessonIdMap: IdMap = new Map();
  const activityIdMap: IdMap = new Map();

  if (APPLY) {
    const { assignedTo: _assignedTo, ...rest } = contentData;
    await db
      .collection("content")
      .doc(newContentId)
      .set({ ...rest, groupId });
  }

  const unitsSnap = await db.collection("content").doc(contentId).collection("units").get();
  for (const unitDoc of unitsSnap.docs) {
    const newUnitId = newId("unit");
    unitIdMap.set(unitDoc.id, newUnitId);
    if (APPLY) {
      await db
        .collection("content")
        .doc(newContentId)
        .collection("units")
        .doc(newUnitId)
        .set(unitDoc.data());
    }

    const lessonsSnap = await unitDoc.ref.collection("lessons").get();
    for (const lessonDoc of lessonsSnap.docs) {
      const newLessonId = newId("lesson");
      lessonIdMap.set(lessonDoc.id, newLessonId);
      if (APPLY) {
        await db
          .collection("content")
          .doc(newContentId)
          .collection("units")
          .doc(newUnitId)
          .collection("lessons")
          .doc(newLessonId)
          .set(lessonDoc.data());
      }

      const activitiesSnap = await lessonDoc.ref.collection("activities").get();
      // Mint every new activity ID up front so requiredActivityId
      // remapping below always has the full map, regardless of order.
      for (const actDoc of activitiesSnap.docs) {
        activityIdMap.set(actDoc.id, newId("activity"));
      }
      for (const actDoc of activitiesSnap.docs) {
        const newActivityId = activityIdMap.get(actDoc.id)!;
        const actData = actDoc.data();
        const oldRequired = actData.requiredActivityId as string | undefined;
        if (APPLY) {
          await db
            .collection("content")
            .doc(newContentId)
            .collection("units")
            .doc(newUnitId)
            .collection("lessons")
            .doc(newLessonId)
            .collection("activities")
            .doc(newActivityId)
            .set({
              ...actData,
              requiredActivityId: oldRequired ? activityIdMap.get(oldRequired) ?? null : null,
            });
        }

        const tasksSnap = await actDoc.ref.collection("tasks").get();
        for (const taskDoc of tasksSnap.docs) {
          if (APPLY) {
            await db
              .collection("content")
              .doc(newContentId)
              .collection("units")
              .doc(newUnitId)
              .collection("lessons")
              .doc(newLessonId)
              .collection("activities")
              .doc(newActivityId)
              .collection("tasks")
              .doc(newId("task"))
              .set(taskDoc.data());
          }
        }
      }
    }

    await cloneQuizzesForUnit(contentId, unitDoc.id, newContentId, newUnitId, lessonIdMap);
  }

  // Second pass to stamp groupId onto every quiz clone just written (kept
  // separate from cloneQuizzesForUnit so that function stays reusable
  // without needing to know the destination groupId up front).
  if (APPLY) {
    const newQuizzesSnap = await db.collection("quizzes").where("contentId", "==", newContentId).get();
    for (const q of newQuizzesSnap.docs) {
      await q.ref.update({ groupId });
    }
  }

  return { newContentId, unitIdMap, lessonIdMap, activityIdMap };
}

async function processContent(contentDoc: FirebaseFirestore.QueryDocumentSnapshot): Promise<void> {
  const data = contentDoc.data();
  const assignedTo: string[] = Array.isArray(data.assignedTo) ? data.assignedTo : [];

  if (assignedTo.length === 0) {
    contentOrphaned++;
    orphanedContentIds.push(contentDoc.id);
    return;
  }

  if (assignedTo.length === 1) {
    contentRenamed++;
    const groupId = assignedTo[0];
    if (APPLY) {
      await contentDoc.ref.update({ groupId, assignedTo: admin.firestore.FieldValue.delete() });
      const quizzesSnap = await db.collection("quizzes").where("contentId", "==", contentDoc.id).get();
      for (const q of quizzesSnap.docs) {
        await q.ref.update({ groupId });
        quizzesStamped++;
      }
    }
    return;
  }

  // Multi-group: clone once per group, then delete the original.
  contentCloned++;
  const perGroup = new Map<string, CloneResult>();
  for (const groupId of assignedTo) {
    const result = await cloneContentForGroup(contentDoc.id, data, groupId);
    perGroup.set(groupId, result);
  }
  cloneIndex.set(contentDoc.id, perGroup);

  // Delete the original multi-group content doc + its subtree + its
  // original quizzes, now that every clone has been written.
  if (APPLY) {
    const origQuizzesSnap = await db.collection("quizzes").where("contentId", "==", contentDoc.id).get();
    for (const q of origQuizzesSnap.docs) {
      await deleteDocRecursive(q.ref);
    }
    await deleteDocRecursive(contentDoc.ref);
  }
}

// Rewrites students/{id}/progress and students/{id}/reports docs that
// reference a cloned content's OLD ids to point at the clone matching the
// student's own group instead. A progress doc's id IS the activityId/quizId
// it's about (see Database.saveActivityCompletion/saveQuizCompletion), so
// this recreates the doc under the new id and deletes the old one -- a
// plain field update isn't enough here.
async function remapStudentProgress(): Promise<void> {
  if (cloneIndex.size === 0) return;

  const studentsSnap = await db.collection("students").get();
  for (const studentDoc of studentsSnap.docs) {
    const studentGroupId = studentDoc.data().groupId as string | undefined;
    if (!studentGroupId) continue;

    const progressSnap = await studentDoc.ref.collection("progress").get();
    for (const progressDoc of progressSnap.docs) {
      const pd = progressDoc.data();
      const oldContentId = pd.contentId as string | undefined;
      if (!oldContentId || !cloneIndex.has(oldContentId)) continue;

      const clone = cloneIndex.get(oldContentId)!.get(studentGroupId);
      if (!clone) {
        // This student's group wasn't one of the content's assigned
        // groups (shouldn't normally happen) -- report, don't guess.
        progressDocsUnresolved++;
        console.warn(
          `  UNRESOLVED progress doc students/${studentDoc.id}/progress/${progressDoc.id}: ` +
            `contentId ${oldContentId} has no clone for this student's group ${studentGroupId}`
        );
        continue;
      }

      const newContentId = clone.newContentId;
      const newUnitId = pd.unitId ? clone.unitIdMap.get(pd.unitId) : undefined;
      const newLessonId = pd.lessonId ? clone.lessonIdMap.get(pd.lessonId) : undefined;
      // The doc id itself is an activityId for type:'activity' progress
      // docs; quiz-completion progress docs are keyed by quizId, which
      // isn't tracked in activityIdMap (quizzes get fresh ids during
      // cloning but aren't otherwise referenced by progress doc IDs in
      // this codebase's current saveQuizCompletion shape) -- only
      // activity-type docs are renamed here.
      const newDocId =
        pd.type === "activity" ? clone.activityIdMap.get(progressDoc.id) ?? progressDoc.id : progressDoc.id;

      progressDocsRewritten++;
      if (APPLY) {
        await studentDoc.ref
          .collection("progress")
          .doc(newDocId)
          .set({
            ...pd,
            contentId: newContentId,
            ...(newUnitId ? { unitId: newUnitId } : {}),
            ...(newLessonId ? { lessonId: newLessonId } : {}),
          });
        if (newDocId !== progressDoc.id) {
          await progressDoc.ref.delete();
        }
      }
    }

    // `reports` docs are keyed by unitId (see Database.saveReport) and
    // carry unitId as a field too -- remap both the doc id and the field.
    const reportsSnap = await studentDoc.ref.collection("reports").get();
    for (const reportDoc of reportsSnap.docs) {
      const rd = reportDoc.data();
      const oldUnitId = (rd.unitId as string | undefined) ?? reportDoc.id;
      // Reports don't carry contentId directly -- search every clone map
      // for this student's group for a matching old unit id.
      let matched: { newContentId: string; newUnitId: string } | undefined;
      for (const [, perGroup] of cloneIndex) {
        const clone = perGroup.get(studentGroupId);
        if (clone?.unitIdMap.has(oldUnitId)) {
          matched = { newContentId: clone.newContentId, newUnitId: clone.unitIdMap.get(oldUnitId)! };
          break;
        }
      }
      if (!matched) continue;

      progressDocsRewritten++;
      if (APPLY) {
        await studentDoc.ref
          .collection("reports")
          .doc(matched.newUnitId)
          .set({ ...rd, unitId: matched.newUnitId });
        if (matched.newUnitId !== reportDoc.id) {
          await reportDoc.ref.delete();
        }
      }
    }
  }
}

async function main(): Promise<void> {
  console.log(APPLY ? "Running with --apply: WRITES WILL HAPPEN.\n" : "Dry run (pass --apply to write).\n");

  const contentSnap = await db.collection("content").get();
  console.log(`Found ${contentSnap.size} content doc(s).\n`);

  for (const doc of contentSnap.docs) {
    await processContent(doc);
  }

  await remapStudentProgress();

  console.log("\n── Summary ──────────────────────────────────────────────");
  console.log(`content renamed (assignedTo -> groupId, in place): ${contentRenamed}`);
  console.log(`content cloned (multi-group -> one doc per group): ${contentCloned}`);
  console.log(`content orphaned (assignedTo was empty, skipped):  ${contentOrphaned}`);
  console.log(`quizzes stamped with groupId (single-group case):  ${quizzesStamped}`);
  console.log(`quizzes cloned (multi-group case):                 ${quizzesCloned}`);
  console.log(`student progress/report docs rewritten:            ${progressDocsRewritten}`);
  console.log(`student progress docs UNRESOLVED (see warnings):   ${progressDocsUnresolved}`);
  if (orphanedContentIds.length > 0) {
    console.log("\nOrphaned content ids (never assigned to any group -- resolve manually):");
    for (const id of orphanedContentIds) console.log(`  - ${id}`);
  }
  if (!APPLY) {
    console.log("\nThis was a dry run -- nothing was written. Re-run with --apply to write.");
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
