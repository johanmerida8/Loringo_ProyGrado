// functions/src/moderationTerms.ts
//
// File-name terms that block an image upload, checked SERVER-side in
// uploadModeratedImage.ts (the app checks the same lists client-side first,
// as a free early rejection: lib/utils/moderation_terms.dart — keep the lists
// identical). This is only a cheap first filter; the real moderation is
// Google Vision SafeSearch (safeSearch.ts).
//
// Two lists:
//   - BLOCKED_FILENAME_TERMS: long, unambiguous terms; match anywhere in the
//     file name (substring), so "nude_photo", "xnudex" and "drug_deal_1" hit.
//   - BLOCKED_FILENAME_WORDS: short or ambiguous terms; match only a WHOLE
//     word of the file name (words are separated by "_", "-", "." or spaces),
//     so "sex.png" is blocked but "essex.png", "method.png" ("meth"),
//     "cracker.png" ("crack") and "breaststroke.png" ("breasts") are not.

export const BLOCKED_FILENAME_TERMS: readonly string[] = [
  // Sexual content — English
  "porn", "pornography", "pornographic", "xxx", "explicit", "sexually_explicit",
  "sexual", "sexual_content", "intercourse", "hentai", "erotic", "erotica", "onlyfans",
  // Nudity and intimate parts — English
  "nudity", "nude", "naked", "genitals", "penis", "vagina", "nipples", "topless",
  // Drugs — English
  "cocaine", "heroin", "methamphetamine", "fentanyl", "marijuana", "cannabis",
  "drug_deal", "drug_use",
  // Violence and self-harm — English
  "dismemberment", "beheading", "self_harm", "suicide", "suicide_attempt", "graphic_violence",
  // Alcohol and intoxication — English
  "drunk", "drunken", "drunkard", "binge_drinking", "alcohol_abuse",

  // Contenido sexual — Español
  "porno", "pornografia", "pornografico", "sexo", "contenido_sexual",
  "contenido_explicito", "erotico",
  // Desnudez y partes íntimas — Español
  "desnudo", "desnuda", "desnudez", "genitales", "pezones", "desvestido", "desvestida",
  // Drogas — Español
  "cocaina", "heroina", "metanfetamina", "fentanilo", "marihuana",
  "trafico_de_drogas", "consumo_de_drogas",
  // Violencia y autolesiones — Español
  "desmembramiento", "decapitacion", "autolesion", "suicidio", "violencia_grafica",
  // Alcohol e intoxicación — Español
  "borracho", "borracha", "embriagado", "embriagada", "consumo_excesivo_alcohol",
];

export const BLOCKED_FILENAME_WORDS: readonly string[] = [
  "sex", "meth", "crack", "gore", "breasts", "senos", "pene",
];

/**
 * Looks for a blocked term in an image's file name.
 * @param {string} fileName The uploaded file's name, e.g. "perro.png".
 * @return {string | null} The matched term, or null if the name is clean.
 */
export function findBlockedTermInFileName(fileName: string): string | null {
  // "drug deal" / "drug-deal" / "drug.deal" all become "drug_deal".
  const name = fileName.toLowerCase().replace(/\.[^.]*$/, "").replace(/[\s\-.]+/g, "_");
  for (const word of name.split("_")) {
    if (BLOCKED_FILENAME_WORDS.includes(word) || BLOCKED_FILENAME_TERMS.includes(word)) {
      return word;
    }
  }
  for (const term of BLOCKED_FILENAME_TERMS) {
    if (name.includes(term)) return term;
  }
  return null;
}
