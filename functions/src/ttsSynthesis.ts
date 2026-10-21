// functions/src/ttsSynthesis.ts
//
// Shared Google Cloud Text-to-Speech synthesis logic for
// generateReadingAudio.ts, generateTaskAudio.ts, and prewarmTtsCache.ts --
// extracted so all three call the same code instead of the two callables'
// near-identical Cloud TTS request logic drifting apart, and so the
// pre-warm trigger (which has no HTTP request to piggyback on) can
// synthesize the exact same way a live callable would.

import { defineSecret } from "firebase-functions/params";
import { HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

export const GOOGLE_TTS_API_KEY = defineSecret("GOOGLE_TTS_API_KEY");

const TTS_ENDPOINT =
  "https://texttospeech.googleapis.com/v1beta1/text:synthesize";

// Maps ReadingVoice.edgeId (lib/services/tts/reading_voices.dart) to a
// Google Cloud TTS voice. Best-effort match on locale + gender/tone from
// the original Edge voice descriptions -- Google's catalog doesn't have
// the same named voices, so this is a reasonable substitute, not an exact
// one. Easy to retune independently of the client.
export const READING_VOICE_MAP: Record<string, { languageCode: string; name: string }> = {
  "en-GB-MaisieNeural": { languageCode: "en-GB", name: "en-GB-Neural2-F" },
  "en-US-AnaNeural": { languageCode: "en-US", name: "en-US-Neural2-F" },
  "en-US-JennyNeural": { languageCode: "en-US", name: "en-US-Neural2-C" },
  "en-US-AvaMultilingualNeural": { languageCode: "en-US", name: "en-US-Neural2-H" },
  "en-GB-SoniaNeural": { languageCode: "en-GB", name: "en-GB-Neural2-A" },
  "en-GB-RyanNeural": { languageCode: "en-GB", name: "en-GB-Neural2-B" },
  "en-GB-OliverNeural": { languageCode: "en-GB", name: "en-GB-Neural2-D" },
  "en-US-GuyNeural": { languageCode: "en-US", name: "en-US-Neural2-J" },
  "en-GB-AlfieNeural": { languageCode: "en-GB", name: "en-GB-Neural2-D" },
};
export const READING_DEFAULT_VOICE_KEY = "en-GB-RyanNeural";
// Reading pages already have a 300-word soft warning in reading_task.dart's
// editor, so this is a hard backstop well above normal use.
export const READING_MAX_CHARS = 4000;

// Maps TtsVoice.edgeId (lib/services/tts/tts_voices.dart) to a Google Cloud
// TTS voice. Covers all 9 catalog entries (7 English, shared with
// ReadingVoice/READING_VOICE_MAP, plus the 2 Spanish voices used by
// screen_eight.dart's bilingual toggle, which reading narration never
// needed).
export const TASK_VOICE_MAP: Record<string, { languageCode: string; name: string }> = {
  "en-GB-MaisieNeural": { languageCode: "en-GB", name: "en-GB-Neural2-F" },
  "en-US-AnaNeural": { languageCode: "en-US", name: "en-US-Neural2-F" },
  "en-US-JennyNeural": { languageCode: "en-US", name: "en-US-Neural2-C" },
  "en-US-AvaMultilingualNeural": { languageCode: "en-US", name: "en-US-Neural2-H" },
  "en-GB-SoniaNeural": { languageCode: "en-GB", name: "en-GB-Neural2-A" },
  "en-GB-RyanNeural": { languageCode: "en-GB", name: "en-GB-Neural2-B" },
  "en-GB-OliverNeural": { languageCode: "en-GB", name: "en-GB-Neural2-D" },
  "es-ES-XimenaNeural": { languageCode: "es-ES", name: "es-ES-Neural2-A" },
  "es-ES-AlvaroNeural": { languageCode: "es-ES", name: "es-ES-Neural2-B" },
};
export const TASK_DEFAULT_VOICE_KEY = "en-GB-SoniaNeural";
// Task prompts are single sentences/dialogue lines, not full pages -- this
// cap is generous headroom over normal use.
export const TASK_MAX_CHARS = 500;

/**
 * Resolves a requested voice key against a catalog, falling back to the
 * default when the requested key is missing/unknown.
 * @param {Record<string, unknown>} voiceMap The voice catalog to check against.
 * @param {string | undefined} requested The caller-requested voice key.
 * @param {string} defaultKey The fallback voice key.
 * @return {string} A voice key guaranteed to exist in voiceMap.
 */
export function resolveVoiceKey(
  voiceMap: Record<string, unknown>,
  requested: string | undefined,
  defaultKey: string
): string {
  return requested && voiceMap[requested] ? requested : defaultKey;
}

export interface WordTimingPayload {
  text: string;
  startMs: number;
  endMs: number;
}

/**
 * Escapes text for safe inclusion inside SSML.
 * @param {string} text Raw text to escape.
 * @return {string} XML-escaped text.
 */
function escapeSsml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

/**
 * Builds SSML with <mark> tags for word-boundary timing. Cloud TTS caps SSML
 * at ~5000 bytes, and a mark per word can blow that budget on long pages, so
 * marks are spaced out (every Nth word) to fit, and un-marked words later
 * have their timing interpolated between the two marks around them. For
 * short/typical pages this still marks every single word (markEvery === 1),
 * giving exact per-word timing identical in spirit to Edge's word-boundary
 * events.
 * @param {string} text Raw page text to narrate.
 * @return {{ssml: string, words: string[], markEvery: number}} The SSML to
 *   send to Cloud TTS, the word list in order, and the mark spacing used.
 */
function buildSsmlWithMarks(
  text: string
): { ssml: string; words: string[]; markEvery: number } {
  const rawWords = text.trim().split(/\s+/).filter((w) => w.length > 0);
  const escapedBytes = Buffer.byteLength(escapeSsml(text), "utf8");
  const overheadBudget = Math.max(4500 - escapedBytes - 40, 0);
  const bytesPerMark = 20; // worst case: <mark name="9999"/>
  const maxMarks = Math.max(Math.floor(overheadBudget / bytesPerMark), 2);
  const markEvery = Math.max(Math.ceil(rawWords.length / maxMarks), 1);

  const parts: string[] = ["<speak>"];
  rawWords.forEach((w, i) => {
    if (i % markEvery === 0) parts.push(`<mark name="${i}"/>`);
    parts.push(`${escapeSsml(w)} `);
  });
  parts.push("<mark name=\"end\"/></speak>");

  return { ssml: parts.join(""), words: rawWords, markEvery };
}

/**
 * Reconstructs per-word start/end timings from Cloud TTS's mark timepoints,
 * interpolating evenly across any un-marked words between two known marks.
 * @param {string[]} words Word list in order, from buildSsmlWithMarks.
 * @param {number} markEvery Mark spacing used when building the SSML.
 * @param {Map<string, number>} timepointByMark Mark name -> time in seconds,
 *   from Cloud TTS's response.
 * @return {WordTimingPayload[]} Per-word start/end timings in milliseconds.
 */
function buildWordTimings(
  words: string[],
  markEvery: number,
  timepointByMark: Map<string, number>
): WordTimingPayload[] {
  const markedIndices: number[] = [];
  for (let i = 0; i < words.length; i += markEvery) markedIndices.push(i);

  const boundarySec = markedIndices.map((i) => timepointByMark.get(String(i)) ?? 0);
  const endSec =
    timepointByMark.get("end") ?? (boundarySec[boundarySec.length - 1] ?? 0) + 1;

  const result: WordTimingPayload[] = [];
  for (let g = 0; g < markedIndices.length; g++) {
    const groupStart = markedIndices[g];
    const groupEnd = g + 1 < markedIndices.length ? markedIndices[g + 1] : words.length;
    const tStart = boundarySec[g];
    const tEnd = g + 1 < markedIndices.length ? boundarySec[g + 1] : endSec;
    const groupWordCount = groupEnd - groupStart;
    const span = tEnd - tStart;

    for (let k = 0; k < groupWordCount; k++) {
      const wordStartSec = tStart + (span * k) / groupWordCount;
      const wordEndSec = tStart + (span * (k + 1)) / groupWordCount;
      result.push({
        text: words[groupStart + k],
        startMs: Math.round(wordStartSec * 1000),
        endMs: Math.round(wordEndSec * 1000),
      });
    }
  }
  return result;
}

export interface ReadingSynthesisResult {
  audioBase64: string;
  words: WordTimingPayload[];
}

/**
 * Synthesizes reading-page narration with per-word timing marks.
 * @param {string} text Page text to narrate.
 * @param {string} voiceKey A key already resolved via resolveVoiceKey against READING_VOICE_MAP.
 * @param {"slow" | "normal"} speed Narration speed.
 * @return {Promise<ReadingSynthesisResult>} The synthesized audio + word timings.
 */
export async function synthesizeReadingAudio(
  text: string,
  voiceKey: string,
  speed: "slow" | "normal"
): Promise<ReadingSynthesisResult> {
  const voiceConfig = READING_VOICE_MAP[voiceKey];
  // speakingRate is a multiplier of natural speed (1.0 = normal). -20%/-50%
  // here mirrors the old Edge TTS prosody rates ('-25%'/'-50%') this
  // replaced -- slow needs to be noticeably slower than normal for young
  // readers following along word-by-word.
  const speakingRate = speed === "slow" ? 0.5 : 0.7;

  const { ssml, words, markEvery } = buildSsmlWithMarks(text);

  const apiKey = GOOGLE_TTS_API_KEY.value();
  const body = {
    input: { ssml },
    voice: { languageCode: voiceConfig.languageCode, name: voiceConfig.name },
    audioConfig: { audioEncoding: "MP3", speakingRate, pitch: 2.0 },
    enableTimePointing: ["SSML_MARK"],
  };

  let response: Response;
  try {
    response = await fetch(`${TTS_ENDPOINT}?key=${apiKey}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch (err) {
    logger.error("Cloud TTS network error", err);
    throw new HttpsError("unavailable", "Could not reach Cloud TTS.");
  }

  if (!response.ok) {
    const errText = await response.text().catch(() => "");
    logger.error("Cloud TTS error response", { status: response.status, body: errText });
    throw new HttpsError("internal", `Cloud TTS request failed (${response.status}).`);
  }

  const json = (await response.json()) as {
    audioContent?: string;
    timepoints?: { markName: string; timeSeconds: number }[];
  };

  if (!json.audioContent) {
    logger.error("Cloud TTS response missing audio content", json);
    throw new HttpsError("internal", "No audio returned by Cloud TTS.");
  }

  const timepointByMark = new Map<string, number>();
  for (const tp of json.timepoints ?? []) {
    timepointByMark.set(tp.markName, tp.timeSeconds);
  }

  return {
    audioBase64: json.audioContent,
    words: buildWordTimings(words, markEvery, timepointByMark),
  };
}

/**
 * Synthesizes a short task prompt/phrase, no word-timing marks.
 * @param {string} text Prompt text to speak.
 * @param {string} voiceKey A key already resolved via resolveVoiceKey against TASK_VOICE_MAP.
 * @return {Promise<string>} Base64-encoded MP3.
 */
export async function synthesizeTaskAudio(text: string, voiceKey: string): Promise<string> {
  const voiceConfig = TASK_VOICE_MAP[voiceKey];
  const apiKey = GOOGLE_TTS_API_KEY.value();
  const body = {
    input: { text },
    voice: { languageCode: voiceConfig.languageCode, name: voiceConfig.name },
    audioConfig: { audioEncoding: "MP3", speakingRate: 1.0, pitch: 2.0 },
  };

  let response: Response;
  try {
    response = await fetch(`${TTS_ENDPOINT}?key=${apiKey}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch (err) {
    logger.error("Cloud TTS network error", err);
    throw new HttpsError("unavailable", "Could not reach Cloud TTS.");
  }

  if (!response.ok) {
    const errText = await response.text().catch(() => "");
    logger.error("Cloud TTS error response", { status: response.status, body: errText });
    throw new HttpsError("internal", `Cloud TTS request failed (${response.status}).`);
  }

  const json = (await response.json()) as { audioContent?: string };
  if (!json.audioContent) {
    logger.error("Cloud TTS response missing audio content", json);
    throw new HttpsError("internal", "No audio returned by Cloud TTS.");
  }

  return json.audioContent;
}
