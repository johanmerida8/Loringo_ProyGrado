// functions/src/prewarmTtsCache.ts
//
// Firestore trigger that pre-synthesizes TTS audio the moment a teacher
// saves task content, instead of waiting for the first student to trigger
// synthesis via generateReadingAudio.ts/generateTaskAudio.ts. This is the
// actual fix for "narration takes ~5s the first time a student opens a
// page" -- by the time any student reaches this content, the ttsCache
// entry (and its Cloudinary audio file) already exists, so the student-
// facing calls are a plain cache hit.
//
// SCOPE: only text that's spoken with a KNOWN, fixed voice gets pre-warmed
// -- see the per-type table below. Voice/speed selection in this app has no
// per-content picker (ReadingTtsService always narrates with
// ReadingVoice.ryan; TaskTtsService's screens pass a fixed voice per
// screen, mostly TtsVoiceDefaults.defaultEnglish/Sonia), so a small, known
// set of (voice[, speed]) combos covers the near-totality of real traffic.
// `fill_blank` is deliberately NOT covered: the audio played there is a
// sentence reassembled client-side from blank/option state
// (screen_four.dart's _fullSentenceWithAnswers) that doesn't exist as a
// single stored field -- replicating that assembly here would duplicate
// fragile logic that can silently drift out of sync. It stays on the
// existing lazy (first-play) synthesis path.
//
// Idempotent: cache keys are content hashes, so re-saving unchanged text
// is a lookupCachedAudio hit and costs nothing -- no explicit diffing
// against the previous document version is needed.

import { onDocumentWritten } from "firebase-functions/firestore";
import * as logger from "firebase-functions/logger";
import { getFirestore, Firestore } from "firebase-admin/firestore";
import {
  CLOUDINARY_API_KEY,
  CLOUDINARY_API_SECRET,
  lookupCachedAudio,
  readingCacheKeyFor,
  taskCacheKeyFor,
  TtsNamespace,
  uploadAndCacheAudio,
} from "./ttsCacheStorage";
import {
  GOOGLE_TTS_API_KEY,
  READING_DEFAULT_VOICE_KEY,
  synthesizeReadingAudio,
  synthesizeTaskAudio,
  TASK_DEFAULT_VOICE_KEY,
} from "./ttsSynthesis";

const SPANISH_DEFAULT_VOICE_KEY = "es-ES-XimenaNeural"; // TtsVoice.ximena

export interface WarmTarget {
  namespace: TtsNamespace;
  text: string;
  voiceKey: string;
  speed?: "slow" | "normal";
}

/**
 * Builds the list of (text, voice[, speed]) combos to pre-warm for a saved
 * task document, based on its `type`. See this file's header comment for
 * the table this implements and why `fill_blank` is excluded. Exported so
 * cleanupOrphanedTtsCache.ts can compute the exact same set of "currently
 * live" cache keys when deciding what's safe to delete -- both files must
 * agree on what counts as referenced.
 * @param {string} type The task's `type` field.
 * @param {Record<string, unknown>} data The task's nested `data` field.
 * @return {WarmTarget[]} Targets to synthesize/cache, empty texts already filtered out.
 */
export function targetsFor(type: string, data: Record<string, unknown>): WarmTarget[] {
  const targets: WarmTarget[] = [];
  const addReading = (text: unknown) => {
    if (typeof text !== "string" || !text.trim()) return;
    for (const speed of ["normal", "slow"] as const) {
      targets.push({ namespace: "reading", text: text.trim(), voiceKey: READING_DEFAULT_VOICE_KEY, speed });
    }
  };
  const addTask = (text: unknown, voiceKey = TASK_DEFAULT_VOICE_KEY) => {
    if (typeof text !== "string" || !text.trim()) return;
    targets.push({ namespace: "task", text: text.trim(), voiceKey });
  };

  switch (type) {
  case "reading":
    // pages entries are either a plain string (legacy tasks) or
    // {text, image} (stories with an optional per-page illustration) --
    // only the text is ever synthesized.
    for (const page of (data.pages as unknown[] | undefined) ?? []) {
      addReading(typeof page === "object" && page !== null ? (page as Record<string, unknown>).text : page);
    }
    break;
  case "repeat_after_me":
  case "listen_and_speak":
    addTask(data.phrase);
    break;
  case "sound_match":
    addTask(data.audioText);
    break;
  case "match":
    for (const pair of (data.pairs as Record<string, unknown>[] | undefined) ?? []) {
      addTask(pair.english);
    }
    break;
  case "complete_the_chat":
    for (const turn of (data.turns as Record<string, unknown>[] | undefined) ?? []) {
      addTask(turn.bubble);
    }
    break;
  case "sentence_builder":
    if (typeof data.sentence === "string" && data.sentence.trim()) {
      addTask(data.sentence);
    } else {
      addTask(data.spanishSentence, SPANISH_DEFAULT_VOICE_KEY);
    }
    break;
  case "arrange": {
    const words = (data.answer as unknown[] | undefined)?.filter((w) => typeof w === "string") as
        | string[]
        | undefined;
    if (words?.length) addTask(words.join(" "));
    break;
  }
  default:
    // fill_blank (deliberately excluded, see header) and any
    // non-speaking types (image_select*, odd_one_out, etc.) -- nothing
    // to pre-warm.
    break;
  }
  return targets;
}

/**
 * Synthesizes and caches a single warm target if it isn't cached already.
 * @param {Firestore} db Firestore instance.
 * @param {WarmTarget} target The (text, voice[, speed]) combo to warm.
 * @return {Promise<void>} Resolves once this target is handled (cached or logged-and-skipped on error).
 */
async function warmOne(db: Firestore, target: WarmTarget): Promise<void> {
  try {
    if (target.namespace === "reading") {
      const cacheKey = readingCacheKeyFor(target.voiceKey, target.speed ?? "normal", target.text);
      if (await lookupCachedAudio(db, cacheKey)) return;
      const { audioBase64, words } = await synthesizeReadingAudio(
        target.text,
        target.voiceKey,
        target.speed ?? "normal"
      );
      await uploadAndCacheAudio(db, cacheKey, audioBase64, "reading", { words });
    } else {
      const cacheKey = taskCacheKeyFor(target.voiceKey, target.text);
      if (await lookupCachedAudio(db, cacheKey)) return;
      const audioBase64 = await synthesizeTaskAudio(target.text, target.voiceKey);
      await uploadAndCacheAudio(db, cacheKey, audioBase64, "task");
    }
  } catch (err) {
    // Best-effort: pre-warming is an optimization, not a correctness
    // requirement -- a failure here just means this utterance stays on
    // the lazy first-play synthesis path, same as before this trigger
    // existed.
    logger.warn("prewarmTtsCache: failed to warm one target", {
      namespace: target.namespace,
      voiceKey: target.voiceKey,
      err,
    });
  }
}

/**
 * Runs async work over a list with bounded concurrency, so a many-page
 * reading task or many-turn dialogue doesn't fan out unbounded parallel
 * Cloud TTS calls.
 * @param {Array<unknown>} items Items to process.
 * @param {number} limit Max concurrent in-flight calls.
 * @param {Function} fn Async work per item.
 * @return {Promise<void>} Resolves once every item has been processed.
 */
export async function withConcurrency<T>(items: T[], limit: number, fn: (item: T) => Promise<void>): Promise<void> {
  let next = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const item = items[next++];
      await fn(item);
    }
  });
  await Promise.all(workers);
}

export const prewarmTtsCache = onDocumentWritten(
  {
    document: "content/{contentId}/units/{unitId}/lessons/{lessonId}/activities/{activityId}/tasks/{taskId}",
    secrets: [GOOGLE_TTS_API_KEY, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET],
    region: "us-central1",
    timeoutSeconds: 300,
  },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return; // deleted -- nothing to warm

    const doc = after.data() ?? {};
    const type = doc.type as string | undefined;
    const taskData = (doc.data as Record<string, unknown> | undefined) ?? {};
    if (!type) return;

    const targets = targetsFor(type, taskData);
    if (!targets.length) return;

    const db = getFirestore();
    await withConcurrency(targets, 3, (target) => warmOne(db, target));
  }
);
