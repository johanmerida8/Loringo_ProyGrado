// functions/src/generateReadingAudio.ts
//
// Firebase Cloud Function (2nd gen, callable) that turns page text into
// narrated audio via Google Cloud Text-to-Speech, plus per-word timing (via
// SSML <mark> timepointing) so the Flutter client can highlight the word
// currently being spoken -- see reading_tts_service.dart / screen_seven.dart.
//
// HISTORY: this used to be client-side flutter_edge_tts (Microsoft Edge
// neural voices over a raw dart:io WebSocket) -- worked on mobile/desktop
// only, since dart:io sockets don't exist on Flutter Web. Moving synthesis
// server-side (a plain callable, same mechanism as moderateImage) makes it
// work identically on every platform, web included.
//
// SECURITY: the API key lives ONLY here, as a Firebase secret. It is never
// sent to or embedded in the Flutter client.
//
// CACHING: server-side, in Firestore's `ttsCache` collection -- shared with
// generateTaskAudio.ts's task-audio cache, since both are the same thing (a
// synthesis result cache keyed by what was synthesized) -- keyed by a hash
// of (voice, speed, text). A page's text is fixed content authored once and
// read by every student who reaches it, so only the first synthesis of a
// given (voice, speed, text) anywhere pays for Cloud TTS; every later read
// is a free Firestore lookup. The audio itself lives in Cloudinary (see
// ttsCacheStorage.ts), not in the Firestore document.
//
// PRE-WARMING: prewarmTtsCache.ts synthesizes and caches reading-page audio
// the moment a teacher saves it (for the default voice/both speeds), so in
// the common case this function is just a cache hit -- a single Firestore
// read. On a genuine miss (brand-new content the trigger hasn't finished
// yet, or a non-default voice), this responds with a data: URI right after
// Cloud TTS finishes rather than also waiting on a Cloudinary upload --
// queueUploadForCache hands that off to processTtsUploadQueue.ts to finish
// in the background, so the student isn't stuck waiting on it. The Flutter
// side additionally caches (audioUrl, words) per voice+speed+text in memory
// for the lifetime of the app session (see reading_tts_service.dart's
// _cache) so re-tapping "play" on the same page doesn't even round-trip to
// Firestore.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import {
  CLOUDINARY_API_KEY,
  CLOUDINARY_API_SECRET,
  lookupCachedAudio,
  queueUploadForCache,
  readingCacheKeyFor,
} from "./ttsCacheStorage";
import {
  GOOGLE_TTS_API_KEY,
  READING_DEFAULT_VOICE_KEY,
  READING_MAX_CHARS,
  READING_VOICE_MAP,
  resolveVoiceKey,
  synthesizeReadingAudio,
  WordTimingPayload,
} from "./ttsSynthesis";

interface GenerateReadingAudioRequest {
  text?: string;
  voice?: string; // ReadingVoice.edgeId
  speed?: "slow" | "normal";
}

interface GenerateReadingAudioResponse {
  audioUrl: string;
  mimeType: string;
  words: WordTimingPayload[];
}

export const generateReadingAudio = onCall<
  GenerateReadingAudioRequest,
  Promise<GenerateReadingAudioResponse>
>(
  {
    secrets: [GOOGLE_TTS_API_KEY, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET],
    region: "us-central1",
    timeoutSeconds: 30,
  },
  async (request) => {
    // No request.auth check here, deliberately: students (the primary
    // caller of this function, via reading_tts_service.dart /
    // screen_seven.dart) never sign into Firebase Auth at all — they log
    // in with a locally-stored access code only (see
    // student_auth_service.dart, which is plain SharedPreferences, no
    // signInAnonymously). Requiring request.auth here silently broke
    // narration for every student while only ever working for a teacher
    // previewing (who IS Firebase-authenticated) — matches moderateImage.ts,
    // the other student-reachable callable in this app, which also has no
    // auth gate. MAX_CHARS below is the abuse backstop instead.
    const text = (request.data?.text ?? "").trim();
    if (!text) {
      throw new HttpsError("invalid-argument", "text is required.");
    }
    if (text.length > READING_MAX_CHARS) {
      throw new HttpsError(
        "invalid-argument",
        `text exceeds ${READING_MAX_CHARS} characters.`
      );
    }

    const voiceKey = resolveVoiceKey(READING_VOICE_MAP, request.data?.voice, READING_DEFAULT_VOICE_KEY);
    const speed = request.data?.speed === "slow" ? "slow" : "normal";

    const db = getFirestore();
    const cacheKey = readingCacheKeyFor(voiceKey, speed, text);

    const cached = await lookupCachedAudio(db, cacheKey);
    if (cached) {
      return {
        audioUrl: cached.url,
        mimeType: "audio/mpeg",
        words: (cached.words ?? []) as WordTimingPayload[],
      };
    }

    const { audioBase64, words } = await synthesizeReadingAudio(text, voiceKey, speed);

    // Await the queue write (a single fast Firestore write) but not the
    // Cloudinary upload itself -- that happens in the background via
    // processTtsUploadQueue.ts. Awaiting the queue write (rather than
    // firing it and returning immediately) matters here: once this
    // function's response is sent, the Cloud Run instance can be frozen
    // at any point, so an un-awaited write could get cut off before it
    // ever reaches Firestore.
    await queueUploadForCache(db, cacheKey, audioBase64, "reading", { words });

    return {
      audioUrl: `data:audio/mpeg;base64,${audioBase64}`,
      mimeType: "audio/mpeg",
      words,
    };
  }
);
