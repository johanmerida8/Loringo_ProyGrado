// functions/src/generateReadingAudio.ts
//
// Firebase Cloud Function (2nd gen, callable) that turns page text into
// natural, expressive audio via Gemini TTS, and hands the raw audio bytes
// straight back to the caller — nothing is written to Cloudinary, Storage,
// or any other persistent store. This is intentional: the app calls this
// on-demand each time a student (or teacher, in the reading_task.dart
// preview) wants to hear a given page, so the same page can be re-recorded
// for free any time the teacher edits its text, and there's no audio-file
// lifecycle to manage or clean up.
//
// SECURITY: the Gemini API key lives ONLY here, as a Firebase secret. It is
// never sent to or embedded in the Flutter client — if it were, anyone
// could pull it out of the APK/IPA and burn your quota. The client calls
// this function by name (via callable-functions auth, already tied to
// Firebase Auth), not the Gemini API directly.
//
// COST NOTE: every call is a live Gemini TTS generation — there is no
// caching on the backend. The Flutter side is expected to cache the
// decoded audio bytes in memory for the lifetime of the screen (see
// gemini_tts_service.dart) so re-tapping "play" on the same page within a
// session doesn't re-trigger a paid call. Caching across sessions/devices
// was explicitly ruled out per instruction not to persist audio.

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";

// Set with: firebase functions:secrets:set GEMINI_API_KEY
const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

const MODEL = "gemini-3.1-flash-tts-preview";
const GEMINI_ENDPOINT =
  `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;

// Warm, enthusiastic, storyteller-for-kids voice — matches the "cálido,
// entusiasta, para niños" direction. Achird is one of the 30 prebuilt
// voices; swap here if you want to try others (Kore, Puck, Aoede, etc.)
// without touching the Flutter side, since the voice is chosen
// server-side.
const VOICE_NAME = "Achird";

// Character ceiling per call — Gemini TTS has no hard published limit, but
// very long single calls increase latency and the chance of a partial/cut
// response. Reading pages already have their own 300-word soft warning in
// reading_task.dart's editor, so this is just a hard backstop well above
// that in case a teacher ignores the warning.
const MAX_CHARS = 4000;

interface GenerateReadingAudioRequest {
  text?: string;
}

interface GenerateReadingAudioResponse {
  audioBase64: string;
  mimeType: string;
}

/**
 * Wraps the requested text in a natural-language style instruction, since
 * Gemini TTS follows the prompt's own instructions on tone/pace rather than
 * taking a separate "style" parameter — "how to say it" is expressed as
 * part of the text sent to the model, not a config field.
 *
 * @param {string} text The raw page text to be narrated.
 * @return {string} The full prompt to send to Gemini TTS, with the style
 *   instruction prepended.
 */
function buildStyledPrompt(text: string): string {
  return "Say the following in a warm, cheerful, enthusiastic storyteller " +
    "voice for young children, ages 5 to 9. Speak clearly at a gentle, " +
    "easy-to-follow pace, with playful energy and natural pauses between " +
    `sentences:\n\n${text}`;
}

export const generateReadingAudio = onCall<
  GenerateReadingAudioRequest,
  Promise<GenerateReadingAudioResponse>
>(
  { secrets: [GEMINI_API_KEY], region: "us-central1", timeoutSeconds: 30 },
  async (request) => {
    // Require an authenticated app user — mirrors the access pattern of
    // every other callable in this app (see email.ts, resetPassword.ts,
    // etc.); anonymous/unauthenticated callers are rejected before we
    // spend any Gemini quota.
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in required.");
    }

    const text = (request.data?.text ?? "").trim();
    if (!text) {
      throw new HttpsError("invalid-argument", "text is required.");
    }
    if (text.length > MAX_CHARS) {
      throw new HttpsError(
        "invalid-argument",
        `text exceeds ${MAX_CHARS} characters.`,
      );
    }

    const apiKey = GEMINI_API_KEY.value();

    const body = {
      contents: [{ parts: [{ text: buildStyledPrompt(text) }] }],
      generationConfig: {
        responseModalities: ["AUDIO"],
        speechConfig: {
          voiceConfig: {
            prebuiltVoiceConfig: { voiceName: VOICE_NAME },
          },
        },
      },
    };

    let response: Response;
    try {
      response = await fetch(GEMINI_ENDPOINT, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": apiKey,
        },
        body: JSON.stringify(body),
      });
    } catch (err) {
      logger.error("Gemini TTS network error", err);
      throw new HttpsError("unavailable", "Could not reach Gemini TTS.");
    }

    if (!response.ok) {
      const errText = await response.text().catch(() => "");
      logger.error("Gemini TTS error response", {
        status: response.status,
        body: errText,
      });
      throw new HttpsError(
        "internal",
        `Gemini TTS request failed (${response.status}).`,
      );
    }

    const json = await response.json();
    const part = json?.candidates?.[0]?.content?.parts?.[0];
    const audioData: string | undefined = part?.inlineData?.data;
    const mimeType: string = part?.inlineData?.mimeType || "audio/wav";

    if (!audioData) {
      logger.error("Gemini TTS response missing audio data", json);
      throw new HttpsError("internal", "No audio returned by Gemini TTS.");
    }

    // audioData is already base64 — pass it straight through. The client
    // decodes it and, since Gemini TTS returns raw PCM (no WAV header),
    // wraps it in a WAV header before handing it to the audio player. See
    // gemini_tts_service.dart's _pcmToWav for that step.
    return {
      audioBase64: audioData,
      mimeType,
    };
  },
);
