// functions/src/moderationPolicy.ts
//
// The image-moderation policy as PURE logic (no Firebase imports), so it can
// be unit-tested: which SafeSearch likelihoods block an upload in each mode.
//
//   normal  — blocks POSSIBLE or above in racy (a semi-naked person is
//             "racy" POSSIBLE even when adult is VERY_UNLIKELY), and LIKELY
//             or above in adult / violence / medical. A POSSIBLE adult or
//             violence result still passes, so a cartoon zombie is not
//             rejected.
//   strict  — blocks POSSIBLE or above in adult / racy / violence, so
//             every uncertain result is REJECTED. medical stays at LIKELY
//             (POSSIBLE would flag ordinary health / body illustrations).
//
// `spoof` (memes / edited images) is only logged in both modes.
//
// Whatever the mode, a response that cannot be trusted (no annotation, a
// category Vision could not rate) is never approved: it is a
// MODERATION_SERVICE_ERROR. That rule lives here, in one place.

export type ModerationMode = "normal" | "strict";

// The mode in force. A fixed constant on purpose (no configuration in Firestore):
// changing it means editing this line and redeploying uploadModeratedImage.
export const MODERATION_MODE: ModerationMode = "strict";

export interface SafeSearchAnnotation {
  adult?: string;
  medical?: string;
  spoof?: string;
  violence?: string;
  racy?: string;
}

export type SafeSearchVerdict =
  | { safe: true }
  | {
      safe: false;
      reason: "REJECT_INAPPROPRIATE_IMAGE" | "MODERATION_SERVICE_ERROR";
      category?: string; // categoría que bloqueó (solo para logs)
    };

// Vision's likelihood scale, from least to most likely.
export const LIKELIHOOD_ORDER = [
  "VERY_UNLIKELY",
  "UNLIKELY",
  "POSSIBLE",
  "LIKELY",
  "VERY_LIKELY",
];

type BlockingCategory = "adult" | "racy" | "violence" | "medical";

// The lowest likelihood that blocks each category, per mode.
export const BLOCK_FROM: Record<ModerationMode, Record<BlockingCategory, string>> = {
  normal: {adult: "LIKELY", racy: "POSSIBLE", violence: "LIKELY", medical: "LIKELY"},
  strict: {adult: "POSSIBLE", racy: "POSSIBLE", violence: "POSSIBLE", medical: "LIKELY"},
};

// ── Labels and objects (LABEL_DETECTION / OBJECT_LOCALIZATION) ──────────────
//
// SafeSearch only rates adult / racy / violence / medical / spoof. It says
// nothing about weapons, alcohol, tobacco or drugs, so Vision's own labels
// and objects are checked too. A label / object blocks the image when ONE OF
// ITS WORDS is in the mode's list (so "Handgun" and "Air gun" both match
// "gun" when that word is listed) and its score reaches the mode's minimum.
//
//   normal — firearms and other weapons, explosives, drugs (pills, syringes,
//            cocaine…), alcohol and tobacco. A cartoon knife or a toy water
//            gun passes.
//   strict — also blades and guns of any kind, with lower minimum scores.
export interface VisionLabel {
  description?: string;
  score?: number;
}

export interface VisionObject {
  name?: string;
  score?: number;
}

// Blocked in BOTH modes: this is a children's app, so firearms, explosives,
// drugs (including pills / syringes), alcohol and tobacco never pass. A
// legitimate image of those (e.g. a doctor lesson) can still be uploaded with
// the "Moderación automática" switch off.
const NORMAL_BLOCKED_WORDS = [
  "weapon", "firearm", "handgun", "pistol", "revolver", "rifle", "shotgun",
  "explosive", "grenade", "bomb",
  "drug", "pill", "syringe",
  "cannabis", "marijuana", "cocaine", "heroin", "methamphetamine",
  "alcohol", "beer", "wine", "liquor", "whiskey", "vodka", "cocktail", "champagne",
  "cigarette", "cigar", "tobacco", "smoking",
  "topless", "barechested", "lingerie",
];

// Strict ONLY: things that are harmless in many drawings (a kitchen knife, a
// toy gun, a fairy-tale sword) but are rejected when maximum caution is wanted.
const STRICT_BLOCKED_WORDS = [
  ...NORMAL_BLOCKED_WORDS,
  "gun", "knife", "sword", "dagger", "machete", "blade",
];

// Minimum scores for the "powder in a bag" combination (see evaluateContent).
const COMBO_POWDER_MIN_SCORE = 0.8;
const COMBO_BAG_MIN_SCORE = 0.5;

export const CONTENT_RULES: Record<
  ModerationMode,
  { words: string[]; minLabelScore: number; minObjectScore: number }
> = {
  normal: { words: NORMAL_BLOCKED_WORDS, minLabelScore: 0.75, minObjectScore: 0.7 },
  strict: { words: STRICT_BLOCKED_WORDS, minLabelScore: 0.55, minObjectScore: 0.5 },
};

/**
 * @param {string} text A Vision label or object name, e.g. "Air gun".
 * @param {string[]} words The blocked words of the mode in force.
 * @return {string | null} The blocked word it contains, or null.
 */
function blockedWordIn(text: string, words: string[]): string | null {
  for (const token of text.toLowerCase().split(/[^a-z]+/)) {
    if (!token) continue;
    // Also try the singular ("knives" is not handled; "guns" -> "gun").
    for (const candidate of [token, token.replace(/s$/, "")]) {
      if (words.includes(candidate)) return candidate;
    }
  }
  return null;
}

/**
 * Applies the label / object rules of [mode]. Absent or empty lists are
 * fine (an image may simply have no such label); a Vision error is handled
 * before this, in checkSafeSearch.
 * @param {VisionLabel[] | undefined} labels Vision's labelAnnotations.
 * @param {VisionObject[] | undefined} objects Vision's localizedObjectAnnotations.
 * @param {ModerationMode} mode The mode in force.
 * @return {SafeSearchVerdict} Whether the labels / objects allow the upload.
 */
export function evaluateContent(
  labels: VisionLabel[] | undefined,
  objects: VisionObject[] | undefined,
  mode: ModerationMode
): SafeSearchVerdict {
  const rules = CONTENT_RULES[mode];

  // Vision doesn't name cocaine: a photo of white powder in a bag comes back
  // as "Powder" + "Plastic bag" / "Bag". That combination is rejected (in
  // both modes); "Powder" alone (flour, sugar, paint) passes.
  const hasPowder = (labels ?? []).some(
    (l) => /\bpowder\b/i.test(l.description ?? "") && (l.score ?? 0) >= COMBO_POWDER_MIN_SCORE
  );
  const hasBag =
    (labels ?? []).some((l) => /\bbag\b/i.test(l.description ?? "") && (l.score ?? 0) >= COMBO_BAG_MIN_SCORE) ||
    (objects ?? []).some((o) => /\bbag\b/i.test(o.name ?? "") && (o.score ?? 0) >= COMBO_BAG_MIN_SCORE);
  if (hasPowder && hasBag) {
    return {safe: false, reason: "REJECT_INAPPROPRIATE_IMAGE", category: "combo:powder+bag"};
  }

  for (const label of labels ?? []) {
    const hit = blockedWordIn(label.description ?? "", rules.words);
    if (hit && (label.score ?? 0) >= rules.minLabelScore) {
      return {safe: false, reason: "REJECT_INAPPROPRIATE_IMAGE", category: `label:${label.description}`};
    }
  }
  for (const object of objects ?? []) {
    const hit = blockedWordIn(object.name ?? "", rules.words);
    if (hit && (object.score ?? 0) >= rules.minObjectScore) {
      return {safe: false, reason: "REJECT_INAPPROPRIATE_IMAGE", category: `object:${object.name}`};
    }
  }
  return {safe: true};
}

/**
 * Narrows an unknown value (a Firestore field) to a moderation mode.
 * @param {unknown} value Whatever was stored.
 * @return {ModerationMode | null} The mode, or null if it isn't a valid one.
 */
export function parseModerationMode(value: unknown): ModerationMode | null {
  return value === "normal" || value === "strict" ? value : null;
}

/**
 * Applies the policy of [mode] to a SafeSearch annotation. Fails closed: a
 * missing annotation or a category Vision could not rate is never "safe".
 * @param {SafeSearchAnnotation | undefined} annotation Vision's answer.
 * @param {ModerationMode} mode The mode in force (decided by the server).
 * @return {SafeSearchVerdict} Whether the image may be uploaded.
 */
export function evaluateSafeSearch(
  annotation: SafeSearchAnnotation | undefined,
  mode: ModerationMode
): SafeSearchVerdict {
  if (!annotation) {
    return {safe: false, reason: "MODERATION_SERVICE_ERROR"};
  }
  const thresholds = BLOCK_FROM[mode];
  for (const category of Object.keys(thresholds) as BlockingCategory[]) {
    const level = LIKELIHOOD_ORDER.indexOf(annotation[category] ?? "");
    // "UNKNOWN" / missing: Vision couldn't rate it -> fail closed.
    if (level === -1) {
      return {safe: false, reason: "MODERATION_SERVICE_ERROR", category};
    }
    if (level >= LIKELIHOOD_ORDER.indexOf(thresholds[category])) {
      return {safe: false, reason: "REJECT_INAPPROPRIATE_IMAGE", category};
    }
  }
  return {safe: true};
}
