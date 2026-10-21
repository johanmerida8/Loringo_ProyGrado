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
//
// HISTORY: before anything is reset, the finished season is snapshotted
// into leagueSeasonHistory/{teacherId}_{endDateMillis} — dates, scope,
// prizes, the winner of each prize league and the top 3 of every league —
// which teacher_league_screen.dart's History tab reads. The doc is only
// ever created, never overwritten: if a previous run saved it and then
// failed in the reset/delete, the retry must not replace it with a
// snapshot of already-zeroed seasonXp.

import { onSchedule } from "firebase-functions/scheduler";
import * as logger from "firebase-functions/logger";
import {
  FieldValue,
  getFirestore,
  Timestamp,
  WriteBatch,
} from "firebase-admin/firestore";

// Firestore's hard limit per WriteBatch.
const BATCH_LIMIT = 500;

// Firestore's limit on values in an `in` query.
const IN_QUERY_LIMIT = 30;

// Mirrors kLeagueTiers in lib/models/league_tier.dart — keep both in sync.
const LEAGUE_TIERS: { key: string; min: number; max: number; rewardLocked: boolean }[] = [
  { key: "starter", min: 0, max: 200, rewardLocked: true },
  { key: "bronze", min: 200, max: 500, rewardLocked: false },
  { key: "silver", min: 500, max: 1000, rewardLocked: false },
  { key: "gold", min: 1000, max: 2000, rewardLocked: false },
  { key: "platinum", min: 2000, max: 4000, rewardLocked: false },
  { key: "diamond", min: 4000, max: 999999, rewardLocked: false },
];

const TOP_PER_TIER = 3;

interface SeasonEntry {
  studentId: string;
  name: string;
  groupId: string;
  seasonXp: number;
}

/**
 * Same tier lookup as tierForXp in lib/models/league_tier.dart.
 * @param {number} xp Season XP.
 * @return {string} The tier key.
 */
function tierKeyForXp(xp: number): string {
  const tier = LEAGUE_TIERS.find((t) => xp >= t.min && xp < t.max);
  return (tier ?? LEAGUE_TIERS[LEAGUE_TIERS.length - 1]).key;
}

/**
 * Saves the finished season (winners + top 3 per league) to
 * leagueSeasonHistory, unless a snapshot for it already exists.
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {FirebaseFirestore.QueryDocumentSnapshot} campaignDoc The ending campaign.
 * @param {string[]} groupIds Groups in the campaign's scope.
 * @param {FirebaseFirestore.QuerySnapshot[]} rosterSnaps Active roster per group (seasonXp still intact).
 * @return {Promise<void>} Resolves once the snapshot exists.
 */
async function saveSeasonSnapshot(
  db: FirebaseFirestore.Firestore,
  campaignDoc: FirebaseFirestore.QueryDocumentSnapshot,
  groupIds: string[],
  rosterSnaps: FirebaseFirestore.QuerySnapshot[]
): Promise<void> {
  const campaign = campaignDoc.data();
  const teacherId = campaignDoc.id;
  const endDate = campaign.endDate as Timestamp;
  const historyRef = db
    .collection("leagueSeasonHistory")
    .doc(`${teacherId}_${endDate.toMillis()}`);

  if ((await historyRef.get()).exists) {
    logger.info(`resetLeagueSeasons: history already saved for ${historyRef.id}`);
    return;
  }

  // Names come from the root students collection, same as _loadStudents
  // in teacher_league_screen.dart; group names/colors from teacherGroups.
  const idChunks: string[][] = [];
  for (let i = 0; i < groupIds.length; i += IN_QUERY_LIMIT) {
    idChunks.push(groupIds.slice(i, i + IN_QUERY_LIMIT));
  }
  const [studentSnaps, groupDocs] = await Promise.all([
    Promise.all(
      idChunks.map((chunk) =>
        db.collection("students").where("groupId", "in", chunk).get()
      )
    ),
    Promise.all(
      groupIds.map((id) => db.collection("teacherGroups").doc(id).get())
    ),
  ]);

  const nameById = new Map<string, string>();
  for (const snap of studentSnaps) {
    for (const d of snap.docs) {
      const data = d.data();
      nameById.set(d.id, (data.names as string) ?? (data.name as string) ?? "Student");
    }
  }

  const groups: Record<string, { name: string; color: string }> = {};
  for (const g of groupDocs) {
    if (!g.exists) continue;
    groups[g.id] = {
      name: (g.data()?.name as string) ?? "",
      color: (g.data()?.color as string) ?? "#4CAF50",
    };
  }

  const entries: SeasonEntry[] = [];
  rosterSnaps.forEach((snap, i) => {
    for (const d of snap.docs) {
      entries.push({
        studentId: d.id,
        name: nameById.get(d.id) ?? "Student",
        groupId: groupIds[i],
        seasonXp: Number(d.data().seasonXp ?? 0),
      });
    }
  });

  const rewards = (campaign.rewards as Record<string, string> | undefined) ?? {};
  const tiers: { tierKey: string; top: SeasonEntry[] }[] = [];
  const winners: (SeasonEntry & { tierKey: string; prize: string })[] = [];

  for (const tier of LEAGUE_TIERS) {
    const inTier = entries
      .filter((e) => tierKeyForXp(e.seasonXp) === tier.key)
      .sort((a, b) => b.seasonXp - a.seasonXp);
    if (inTier.length === 0) continue;
    tiers.push({ tierKey: tier.key, top: inTier.slice(0, TOP_PER_TIER) });

    // Same winner rule as the Ranking tab: #1 of an unlocked league that
    // has a prize configured.
    const prize = (rewards[tier.key] ?? "").trim();
    if (!tier.rewardLocked && prize) {
      winners.push({ ...inTier[0], tierKey: tier.key, prize });
    }
  }

  await historyRef.create({
    teacherId,
    scope: (campaign.scope as string | undefined) ?? "all",
    ...(campaign.groupId ? { groupId: campaign.groupId } : {}),
    startDate: campaign.startDate ?? null,
    endDate,
    closedAt: FieldValue.serverTimestamp(),
    rewards,
    participants: entries.length,
    groups,
    winners,
    tiers,
  });
}

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

        // Snapshot first, while seasonXp still holds the season's values.
        await saveSeasonSnapshot(db, campaignDoc, groupIds, rosterSnaps);

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
