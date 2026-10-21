// Keep identical to functions/src/moderationTerms.ts: the app checks these
// lists first as a free early rejection, and the server checks the same lists
// again before uploading. It is only a cheap first filter — the real moderation
// is Google Vision SafeSearch on the server.

/// Long, unambiguous terms: they match anywhere in the file name (substring),
/// so "nude_photo", "xnudex" and "drug_deal_1" are blocked.
const Set<String> kidsafeModerationBlockedTerms = {
  // Sexual content — English
  'porn', 'pornography', 'pornographic', 'xxx', 'explicit', 'sexually_explicit',
  'sexual', 'sexual_content', 'intercourse', 'hentai', 'erotic', 'erotica', 'onlyfans',
  // Nudity and intimate parts — English
  'nudity', 'nude', 'naked', 'genitals', 'penis', 'vagina', 'nipples', 'topless',
  // Drugs — English
  'cocaine', 'heroin', 'methamphetamine', 'fentanyl', 'marijuana', 'cannabis',
  'drug_deal', 'drug_use',
  // Violence and self-harm — English
  'dismemberment', 'beheading', 'self_harm', 'suicide', 'suicide_attempt', 'graphic_violence',
  // Alcohol and intoxication — English
  'drunk', 'drunken', 'drunkard', 'binge_drinking', 'alcohol_abuse',

  // Contenido sexual — Español
  'porno', 'pornografia', 'pornografico', 'sexo', 'contenido_sexual',
  'contenido_explicito', 'erotico',
  // Desnudez y partes íntimas — Español
  'desnudo', 'desnuda', 'desnudez', 'genitales', 'pezones', 'desvestido', 'desvestida',
  // Drogas — Español
  'cocaina', 'heroina', 'metanfetamina', 'fentanilo', 'marihuana',
  'trafico_de_drogas', 'consumo_de_drogas',
  // Violencia y autolesiones — Español
  'desmembramiento', 'decapitacion', 'autolesion', 'suicidio', 'violencia_grafica',
  // Alcohol e intoxicación — Español
  'borracho', 'borracha', 'embriagado', 'embriagada', 'consumo_excesivo_alcohol',
};

/// Short or ambiguous terms: they only match a WHOLE word of the file name,
/// so "sex.png" is blocked but "essex.png", "method.png" ("meth"),
/// "cracker.png" ("crack") and "breaststroke.png" ("breasts") are not.
const Set<String> kidsafeModerationBlockedWords = {
  'sex', 'meth', 'crack', 'gore', 'breasts', 'senos', 'pene',
};
