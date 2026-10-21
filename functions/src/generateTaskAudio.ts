// functions/src/generateTaskAudio.ts
//
// Firebase Cloud Function (2nd gen, callable) that turns a task prompt
// (dialogue line, sentence, phrase -- see task_tts_service.dart) into audio
// via Google Cloud Text-to-Speech. Sibling to generateReadingAudio.ts, minus
// the SSML <mark> word-timing (task audio has no word-highlight feature).
//
// WHY: task audio previously played through flutter_tts, which delegates to
// each platform's native speech engine (Android/iOS system TTS, the
// browser's Web Speech API on web). That works everywhere but means the
// voice for a given locale differs per platform/browser -- e.g. en-GB comes
// out as a woman's voice on one device and a man's on another. Moving
// synthesis server-side to a specific named Google voice makes it identical
// everywhere, same fix as generateReadingAudio.ts already applied to reading
// narration.
//
// CACHING: server-side, in Firestore's `ttsCache` collection, keyed by a
// hash of (voice, text) -- shared with generateReadingAudio.ts. The audio
// itself lives in Cloudinary (see ttsCacheStorage.ts), not in the Firestore
// document -- Firestore only stores a small { url } pointer.
//
// PRE-WARMING: prewarmTtsCache.ts synthesizes and caches task-prompt audio
// the moment a teacher saves it, so in the common case this function is
// just a cache hit -- a single Firestore read. On a genuine miss, this
// responds with a data: URI right after Cloud TTS finishes rather than
// also waiting on a Cloudinary upload -- see generateReadingAudio.ts's
// header comment for the full rationale.
//
// SECURITY: the API key lives ONLY here, as a Firebase secret, same as
// generateReadingAudio.ts.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import {
  CLOUDINARY_API_KEY,
  CLOUDINARY_API_SECRET,
  lookupCachedAudio,
  queueUploadForCache,
  taskCacheKeyFor,
} from "./ttsCacheStorage";
import {
  GOOGLE_TTS_API_KEY,
  resolveVoiceKey,
  synthesizeTaskAudio,
  TASK_DEFAULT_VOICE_KEY,
  TASK_MAX_CHARS,
  TASK_VOICE_MAP,
} from "./ttsSynthesis";

interface GenerateTaskAudioRequest {
  text?: string;
  voice?: string; // TtsVoice.edgeId
}

interface GenerateTaskAudioResponse {
  audioUrl: string;
  mimeType: string;
}

export const generateTaskAudio = onCall<
  GenerateTaskAudioRequest,
  Promise<GenerateTaskAudioResponse>
>(
  {
    secrets: [GOOGLE_TTS_API_KEY, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET],
    region: "us-central1",
    timeoutSeconds: 30,
  },
  async (request) => {
    // No request.auth check, deliberately -- students (the primary caller,
    // via task_tts_service.dart) never sign into Firebase Auth, they log in
    // with a locally-stored access code only. Matches generateReadingAudio.ts
    // and moderateImage.ts, the other student-reachable callables. MAX_CHARS
    // is the abuse backstop instead.
    const text = (request.data?.text ?? "").trim();
    if (!text) {
      throw new HttpsError("invalid-argument", "text is required.");
    }
    if (text.length > TASK_MAX_CHARS) {
      throw new HttpsError(
        "invalid-argument",
        `text exceeds ${TASK_MAX_CHARS} characters.`
      );
    }

    const voiceKey = resolveVoiceKey(TASK_VOICE_MAP, request.data?.voice, TASK_DEFAULT_VOICE_KEY);

    const db = getFirestore();
    const cacheKey = taskCacheKeyFor(voiceKey, text);

    const cached = await lookupCachedAudio(db, cacheKey);
    if (cached) {
      return { audioUrl: cached.url, mimeType: "audio/mpeg" };
    }

    const audioBase64 = await synthesizeTaskAudio(text, voiceKey);

    // See generateReadingAudio.ts for why this queue write is awaited but
    // the Cloudinary upload itself isn't.
    await queueUploadForCache(db, cacheKey, audioBase64, "task");

    return {
      audioUrl: `data:audio/mpeg;base64,${audioBase64}`,
      mimeType: "audio/mpeg",
    };
  }
);
