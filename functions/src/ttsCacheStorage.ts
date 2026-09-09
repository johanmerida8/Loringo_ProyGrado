// functions/src/ttsCacheStorage.ts
//
// Shared cache glue for generateReadingAudio.ts and generateTaskAudio.ts.
//
// WHY THIS EXISTS: both functions used to write the full base64 MP3 straight
// into a Firestore `ttsCache` document -- one heavy document per distinct
// (voice, text) synthesized anywhere, forever. That doesn't scale: Firestore
// document storage/reads aren't priced or built for holding media blobs, and
// a long reading page's payload could approach the 1MB document limit
// (generateReadingAudio.ts didn't even bother caching for that reason,
// before this change).
//
// FIX: upload the synthesized audio to Cloudinary instead (same media store
// already used for images -- see lib/utils/image_service.dart), server-side,
// the same way deleteCloudinaryImage.ts already talks to Cloudinary's admin
// API with the API secret. Firestore's `ttsCache` document then holds only a
// small pointer: { url, publicId, ...extra, createdAt }.
//
// MIGRATION: old-format documents (written before this change) have
// `audioBase64` but no `url`. lookupCachedAudio treats those as a miss --
// self-healing: the next request for that (voice, text) resynthesizes,
// uploads to Cloudinary, and overwrites the doc (via `.set()`, not merge)
// with the new small shape, dropping the old blob automatically. A one-time
// manual purge of the whole `ttsCache` collection after deploy clears the
// rest immediately instead of waiting on lazy re-requests.

import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import type { Firestore } from "firebase-admin/firestore";
import { FieldValue } from "firebase-admin/firestore";
import { createHash } from "crypto";

export const CLOUDINARY_API_KEY = defineSecret("CLOUDINARY_API_KEY");
export const CLOUDINARY_API_SECRET = defineSecret("CLOUDINARY_API_SECRET");
const CLOUD_NAME = "dmflzlyzk"; // same constant as ImageService.cloudName

// One subfolder per synthesis kind -- keeps the Cloudinary media library
// browsable (generateReadingAudio.ts vs generateTaskAudio.ts output) even
// though these are cache entries, not teacher-curated media.
export type TtsNamespace = "reading" | "task";
const AUDIO_FOLDER: Record<TtsNamespace, string> = {
  reading: "ttsAudio/reading",
  task: "ttsAudio/task",
};

export interface CachedAudio {
  url: string;
  words?: unknown;
}

/**
 * Builds the Firestore cache document ID for a (voice, speed, text) triple.
 * Shared with generateTaskAudio.ts's cache key (via taskCacheKeyFor) in the
 * same `ttsCache` collection -- the "reading::" discriminator keeps a
 * reading page from colliding with a task utterance that happens to have
 * identical text+voice.
 * @param {string} voiceKey ReadingVoice.edgeId used for synthesis.
 * @param {string} speed "slow" or "normal".
 * @param {string} text The page text being narrated.
 * @return {string} A stable hash usable as a Firestore document ID.
 */
export function readingCacheKeyFor(voiceKey: string, speed: string, text: string): string {
  return createHash("sha256").update(`reading::${voiceKey}::${speed}::${text}`).digest("hex");
}

/**
 * Builds the Firestore cache document ID for a (voice, text) pair. See
 * readingCacheKeyFor for why the "task::" discriminator matters.
 * @param {string} voiceKey TtsVoice.edgeId used for synthesis.
 * @param {string} text The prompt text being spoken.
 * @return {string} A stable hash usable as a Firestore document ID.
 */
export function taskCacheKeyFor(voiceKey: string, text: string): string {
  return createHash("sha256").update(`task::${voiceKey}::${text}`).digest("hex");
}

/**
 * Looks up a cached synthesis result. Only documents already migrated to
 * the Cloudinary-backed shape (i.e. carrying a `url`) count as a hit --
 * see the migration note above.
 * @param {Firestore} db Firestore instance.
 * @param {string} cacheKey Document ID, from the caller's cacheKeyFor().
 * @return {Promise<CachedAudio | null>} The cached url/words, or null on a
 *   miss (including legacy pre-migration documents).
 */
export async function lookupCachedAudio(
  db: Firestore,
  cacheKey: string
): Promise<CachedAudio | null> {
  const snap = await db.collection("ttsCache").doc(cacheKey).get();
  if (!snap.exists) return null;

  const data = snap.data();
  const url = data?.url as string | undefined;
  if (!url) return null;

  return { url, words: data?.words };
}

/**
 * Uploads synthesized audio to Cloudinary and writes the small pointer
 * document to `ttsCache/{cacheKey}`. Non-fatal on failure -- the caller
 * already has the synthesized audio and can fall back to serving it
 * directly (e.g. as a data: URI) without caching it.
 * @param {Firestore} db Firestore instance.
 * @param {string} cacheKey Document ID, from the caller's cacheKeyFor().
 * @param {string} audioBase64 Base64-encoded MP3, straight from Cloud TTS.
 * @param {TtsNamespace} namespace Which Cloudinary subfolder (ttsAudio/reading or ttsAudio/task) this belongs in.
 * @param {Record<string, unknown>} extra Extra fields to store alongside
 *   the url (e.g. word timings, for reading pages).
 * @return {Promise<string | null>} The Cloudinary secure_url, or null if
 *   the upload/cache-write failed.
 */
export async function uploadAndCacheAudio(
  db: Firestore,
  cacheKey: string,
  audioBase64: string,
  namespace: TtsNamespace,
  extra: Record<string, unknown> = {}
): Promise<string | null> {
  try {
    const apiKey = CLOUDINARY_API_KEY.value();
    const apiSecret = CLOUDINARY_API_SECRET.value();
    const timestamp = Math.floor(Date.now() / 1000).toString();
    const folder = AUDIO_FOLDER[namespace];

    // Cloudinary's signature is sha1 over the alphabetically-sorted
    // param=value pairs (excluding file/api_key), plus the secret --
    // same recipe as ImageService._generateSignature, just computed with
    // Node's crypto instead of the `crypto` Dart package.
    const toSign = `folder=${folder}&public_id=${cacheKey}&timestamp=${timestamp}${apiSecret}`;
    const signature = createHash("sha1").update(toSign).digest("hex");

    const form = new FormData();
    form.append("file", `data:audio/mpeg;base64,${audioBase64}`);
    form.append("folder", folder);
    form.append("public_id", cacheKey);
    form.append("timestamp", timestamp);
    form.append("api_key", apiKey);
    form.append("signature", signature);

    // Cloudinary files audio under its "video" resource type -- there is
    // no separate "audio" endpoint.
    const response = await fetch(
      `https://api.cloudinary.com/v1_1/${CLOUD_NAME}/video/upload`,
      { method: "POST", body: form }
    );

    if (!response.ok) {
      const errText = await response.text().catch(() => "");
      logger.warn("ttsCacheStorage: Cloudinary upload failed", {
        status: response.status,
        body: errText,
      });
      return null;
    }

    const json = (await response.json()) as {
      secure_url?: string;
      public_id?: string;
    };
    if (!json.secure_url) {
      logger.warn("ttsCacheStorage: Cloudinary response missing secure_url", json);
      return null;
    }

    await db.collection("ttsCache").doc(cacheKey).set({
      url: json.secure_url,
      publicId: json.public_id ?? cacheKey,
      ...extra,
      createdAt: FieldValue.serverTimestamp(),
    });

    return json.secure_url;
  } catch (err) {
    logger.warn("ttsCacheStorage: upload/cache-write failed, serving uncached", err);
    return null;
  }
}

/**
 * Queues a synthesized audio for background Cloudinary upload instead of
 * uploading inline. Used by the two onCall functions on a cache miss so the
 * student gets their answer (a data: URI) right after Cloud TTS finishes,
 * without also waiting on the Cloudinary round trip -- processTtsUploadQueue.ts
 * picks this doc up via a Firestore trigger and does the actual upload.
 * This doc is transient: the trigger deletes it once it's done (success or
 * failure), so it's not a repeat of the old "permanent blob accumulation"
 * problem -- just a brief handoff.
 * @param {Firestore} db Firestore instance.
 * @param {string} cacheKey Document ID, from the caller's cacheKeyFor().
 * @param {string} audioBase64 Base64-encoded MP3, straight from Cloud TTS.
 * @param {TtsNamespace} namespace Which Cloudinary subfolder this belongs in.
 * @param {Record<string, unknown>} extra Extra fields to store alongside
 *   the url once uploaded (e.g. word timings, for reading pages).
 * @return {Promise<void>} Resolves once the queue doc write completes (or
 *   fails silently -- losing the queue entry just means this utterance
 *   stays a cache miss until next played, same as any other best-effort
 *   caching failure here).
 */
export async function queueUploadForCache(
  db: Firestore,
  cacheKey: string,
  audioBase64: string,
  namespace: TtsNamespace,
  extra: Record<string, unknown> = {}
): Promise<void> {
  try {
    await db.collection("ttsUploadQueue").doc(cacheKey).set({
      audioBase64,
      namespace,
      extra,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (err) {
    logger.warn("ttsCacheStorage: failed to queue upload, will stay a cache miss", err);
  }
}

/**
 * Deletes a cache entry entirely -- both the Cloudinary audio file and the
 * `ttsCache/{cacheKey}` pointer doc. Used by cleanupOrphanedTtsCache.ts,
 * ONLY once that sweep has confirmed no task references this (voice, text)
 * combo anymore. Cache keys are content hashes, so the same entry can be
 * shared by multiple tasks/teachers with identical text -- deleting it
 * here is only safe because the caller already checked it's unreferenced
 * everywhere, not just by whichever task last changed.
 * @param {Firestore} db Firestore instance.
 * @param {string} cacheKey Document ID to delete.
 * @param {string} publicId The Cloudinary public_id to destroy (usually equal to cacheKey).
 * @return {Promise<void>} Resolves once both deletes have been attempted
 *   (Cloudinary destroy is best-effort; the Firestore doc is always
 *   removed after).
 */
export async function deleteCachedAudio(
  db: Firestore,
  cacheKey: string,
  publicId: string
): Promise<void> {
  try {
    const apiKey = CLOUDINARY_API_KEY.value();
    const apiSecret = CLOUDINARY_API_SECRET.value();
    const auth = Buffer.from(`${apiKey}:${apiSecret}`).toString("base64");

    const response = await fetch(
      `https://api.cloudinary.com/v1_1/${CLOUD_NAME}/video/destroy`,
      {
        method: "POST",
        headers: {
          "Authorization": `Basic ${auth}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: `public_id=${encodeURIComponent(publicId)}`,
      }
    );
    if (!response.ok) {
      logger.warn("ttsCacheStorage: Cloudinary destroy failed", { cacheKey, status: response.status });
    }
  } catch (err) {
    logger.warn("ttsCacheStorage: Cloudinary destroy error", { cacheKey, err });
  }

  // Delete the Firestore doc regardless of whether the Cloudinary destroy
  // succeeded -- best-effort, same philosophy as the rest of this file. A
  // failed destroy just leaves an unreferenced Cloudinary file behind
  // (no cost/growth concern in Firestore, which is what this whole
  // redesign was about); it won't be retried since it's no longer in
  // ttsCache for the next sweep to find.
  await db.collection("ttsCache").doc(cacheKey).delete();
}
