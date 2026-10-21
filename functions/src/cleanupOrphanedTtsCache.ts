// functions/src/cleanupOrphanedTtsCache.ts
//
// Weekly sweep that deletes ttsCache entries (and their Cloudinary audio
// files) no longer referenced by any task -- e.g. a teacher edited a
// reading page's text, or deleted a task outright. Neither ttsCache nor
// Cloudinary has any automatic expiration, so without this, edited/deleted
// content's old audio would just accumulate forever.
//
// WHY A SWEEP, NOT PER-EDIT DELETION: cache keys are content hashes of
// (voice[, speed], text), not tied to any one task -- so the SAME entry
// can be shared by multiple tasks, even across different teachers, that
// happen to have identical text (e.g. two tasks both saying "Correct!").
// Deleting an entry the moment ONE task stops using that text would risk
// deleting audio another task still needs. Instead this does a full
// "what's actually still referenced anywhere" scan -- reusing
// prewarmTtsCache.ts's targetsFor(), the exact same logic that decides
// what to warm, so both files agree on what counts as "live" -- and only
// removes entries missing from that live set. Content edits are
// occasional, not constant, so a bit of lag before an orphan gets swept
// (up to a week) is a fine trade-off for not needing per-edit reference
// counting, which would risk a bug wrongly deleting shared audio.

import { onSchedule } from "firebase-functions/scheduler";
import * as logger from "firebase-functions/logger";
import { getFirestore } from "firebase-admin/firestore";
import {
  CLOUDINARY_API_KEY,
  CLOUDINARY_API_SECRET,
  deleteCachedAudio,
  readingCacheKeyFor,
  taskCacheKeyFor,
} from "./ttsCacheStorage";
import { targetsFor, withConcurrency } from "./prewarmTtsCache";

export const cleanupOrphanedTtsCache = onSchedule(
  {
    schedule: "0 9 * * 0", // weekly, Sunday 9am
    timeZone: "America/La_Paz",
    secrets: [CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET],
    timeoutSeconds: 540,
  },
  async () => {
    const db = getFirestore();

    // Every task across every teacher's content -- collectionGroup so this
    // doesn't need to walk content/units/lessons/activities by hand.
    const tasksSnap = await db.collectionGroup("tasks").get();

    const liveKeys = new Set<string>();
    for (const doc of tasksSnap.docs) {
      const data = doc.data();
      const type = data.type as string | undefined;
      if (!type) continue;
      const taskData = (data.data as Record<string, unknown> | undefined) ?? {};

      for (const target of targetsFor(type, taskData)) {
        const key = target.namespace === "reading" ?
          readingCacheKeyFor(target.voiceKey, target.speed ?? "normal", target.text) :
          taskCacheKeyFor(target.voiceKey, target.text);
        liveKeys.add(key);
      }
    }

    const cacheSnap = await db.collection("ttsCache").get();
    const orphans = cacheSnap.docs.filter((doc) => doc.data().url && !liveKeys.has(doc.id));

    logger.info(
      `cleanupOrphanedTtsCache: ${orphans.length} orphaned of ${cacheSnap.size} total ttsCache entries`
    );

    await withConcurrency(orphans, 5, async (doc) => {
      const publicId = (doc.data().publicId as string | undefined) ?? doc.id;
      await deleteCachedAudio(db, doc.id, publicId);
    });
  }
);
