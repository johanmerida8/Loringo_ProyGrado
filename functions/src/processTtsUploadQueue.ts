// functions/src/processTtsUploadQueue.ts
//
// Firestore onCreate trigger that finishes the Cloudinary upload
// generateReadingAudio.ts/generateTaskAudio.ts hand off on a cache miss.
//
// WHY: those two functions used to await the Cloudinary upload before
// responding to the student, which added the upload's full latency (~seconds)
// on top of Cloud TTS synthesis. Now they respond with a data: URI right
// after synthesis and write a small `ttsUploadQueue/{cacheKey}` doc instead
// -- this trigger picks that doc up, does the actual upload + writes the
// permanent `ttsCache/{cacheKey}` pointer doc (via the same
// uploadAndCacheAudio used by prewarmTtsCache.ts), then deletes the queue
// doc either way.
//
// The queue doc is transient by design -- it holds a base64 blob briefly
// (until this trigger processes it, normally within seconds), then is
// deleted. That's not a repeat of the original "permanent blob
// accumulation in ttsCache" problem this whole redesign was about: nothing
// here sits around forever, and after prewarmTtsCache.ts ships, most
// requests are already-warm cache hits, so this path should fire rarely.
//
// Best-effort like the rest of this caching layer: if the upload fails,
// the queue doc is still deleted (no retry loop) -- the next time that
// (voice, text) is requested, it's just a cache miss again, same as any
// other caching hiccup.

import { onDocumentCreated } from "firebase-functions/firestore";
import * as logger from "firebase-functions/logger";
import { getFirestore } from "firebase-admin/firestore";
import {
  CLOUDINARY_API_KEY,
  CLOUDINARY_API_SECRET,
  TtsNamespace,
  uploadAndCacheAudio,
} from "./ttsCacheStorage";

export const processTtsUploadQueue = onDocumentCreated(
  {
    document: "ttsUploadQueue/{cacheKey}",
    secrets: [CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET],
    region: "us-central1",
  },
  async (event) => {
    const cacheKey = event.params.cacheKey;
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    const audioBase64 = data.audioBase64 as string | undefined;
    const namespace = data.namespace as TtsNamespace | undefined;
    const extra = (data.extra as Record<string, unknown> | undefined) ?? {};

    const db = getFirestore();
    try {
      if (audioBase64 && namespace) {
        await uploadAndCacheAudio(db, cacheKey, audioBase64, namespace, extra);
      } else {
        logger.warn("processTtsUploadQueue: malformed queue doc, skipping", { cacheKey });
      }
    } finally {
      await snap.ref.delete().catch((err) =>
        logger.warn("processTtsUploadQueue: failed to delete queue doc", { cacheKey, err })
      );
    }
  }
);
