// functions/src/resetLeagueSeasons.ts
//
// Daily cron that ends a league campaign once its `endDate` has passed:
// resets every roster doc's `seasonXp` (in scope) back to 0, so league
// tier/leaderboard/reward eligibility — which read `seasonXp`, not the
// lifetime `xp` field (see database.dart's saveActivityCompletion /
// saveQuizCompletion) — start fresh next season, giving real
// promotion/demotion with no special-casing by tier. Lifetime `xp` (the
// Total XP stat) is never touched here.
//
// The campaign doc itself (`leagueCampaigns/{teacherId}`) is deleted once
// its season's roster reset succeeds — duration and prizes disappear with
// it, which is also what tells teacher_league_screen.dart's Rewards tab
// to show "Create Campaign" again instead of "Update Campaign". There's
// no separate teacher-facing delete action; ending a campaign IS deleting
// it. Deleting (rather than just marking it processed) also makes this
// job naturally idempotent: a deleted doc simply won't match the
// `endDate <= now` query on the next run, so no separate dedup marker is
// needed, and a failed/retried run just re-resets seasonXp to 0 again
// (harmless) before retrying the delete.

import { onSchedule } from "firebase-functions/scheduler";
import * as logger from "firebase-functions/logger";
import { getFirestore, Timestamp, WriteBatch } from "firebase-admin/firestore";

// Firestore's hard limit per WriteBatch.
const BATCH_LIMIT = 500;

/**
 * Resets `seasonXp` to 0 on every given roster doc ref, committing in
 * chunks of BATCH_LIMIT since a single WriteBatch can't exceed it — no
 * existing helper in functions/src does this (the only other db.batch()
 * usage, in email.ts, has no chunking and is always well under the limit).
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {FirebaseFirestore.DocumentReference[]} rosterRefs Roster doc refs to reset.
 * @return {Promise<void>} Resolves once every batch has committed.
 */
async function resetSeasonXpInBatches(
  db: FirebaseFirestore.Firestore,
  rosterRefs: FirebaseFirestore.DocumentReference[]
): Promise<void> {
  const commits: Promise<FirebaseFirestore.WriteResult[]>[] = [];
  let batch: WriteBatch = db.batch();
  let count = 0;

  for (const ref of rosterRefs) {
    batch.update(ref, { seasonXp: 0 });
    count++;
    if (count === BATCH_LIMIT) {
      commits.push(batch.commit());
      batch = db.batch();
      count = 0;
    }
  }
  if (count > 0) {
    commits.push(batch.commit());
  }

  await Promise.all(commits);
}

/**
 * Runs once a day — a season boundary isn't time-critical the way a
 * scheduled-activity notification is, so daily (matching
 * notifyOverdueActivities.ts's cadence) is enough to catch an endDate
 * shortly after it passes.
 */
export const resetLeagueSeasons = onSchedule(
  {
    schedule: "0 8 * * *",
    timeZone: "America/La_Paz",
  },
  async () => {
    const db = getFirestore();
    const now = Timestamp.now();

    const dueSnap = await db
      .collection("leagueCampaigns")
      .where("endDate", "<=", now)
      .get();

    if (dueSnap.empty) {
      logger.info("resetLeagueSeasons: no campaigns due for reset");
      return;
    }

    logger.info(
      `resetLeagueSeasons: ${dueSnap.size} campaign(s) due for reset`
    );

    for (const campaignDoc of dueSnap.docs) {
      const teacherId = campaignDoc.id;
      const scope = (campaignDoc.data().scope as string | undefined) ?? "all";
      const campaignGroupId = campaignDoc.data().groupId as string | undefined;

      try {
        // Same scope resolution as _loadStudents (teacher_league_screen.dart)
        // / _loadLeagueStatus (student_league_screen.dart): 'single' targets
        // just the one configured group, 'all' merges every group this
        // teacher has.
        let groupIds: string[];
        if (scope === "single" && campaignGroupId) {
          groupIds = [campaignGroupId];
        } else {
          const groupsSnap = await db
            .collection("teacherGroups")
            .where("teacherId", "==", teacherId)
            .get();
          groupIds = groupsSnap.docs.map((d) => d.id);
        }

        const rosterSnaps = await Promise.all(
          groupIds.map((groupId) =>
            db
              .collection("teacherGroups")
              .doc(groupId)
              .collection("students")
              .where("status", "==", "active")
              .get()
          )
        );
        const rosterRefs = rosterSnaps.flatMap((snap) =>
          snap.docs.map((d) => d.ref)
        );

        await resetSeasonXpInBatches(db, rosterRefs);

        // Deletes duration + prizes together with the season — see the
        // file-level comment on why this is the delete, not a marker.
        await campaignDoc.ref.delete();

        logger.info(
          `resetLeagueSeasons: reset ${rosterRefs.length} roster doc(s) and ` +
            `removed the campaign for teacher ${teacherId} (${groupIds.length} group(s))`
        );
      } catch (e) {
        // One teacher's campaign failing shouldn't abort the rest of the
        // run — same reasoning as the per-recipient error swallowing in
        // notifyOverdueActivities.ts.
        logger.error(`resetLeagueSeasons: failed for teacher ${teacherId}`, e);
      }
    }

    logger.info("resetLeagueSeasons: done");
  }
);
