// lib/services/tts/tts_voices.dart
//
// Curated catalog of Edge TTS neural voices for the app's two active
// languages (English content, Spanish content in bilingual tasks like
// sentence_builder's es_to_en/en_to_es direction). Shared by
// ReadingTtsService (story narration) and TaskTtsService (in-task
// feedback/confirmation). Kept as a small fixed list rather than
// exposing Edge's full 300+ voice catalog.
//
// NOTE ON SPANISH: Edge TTS has no "child" voice for es-ES the way
// en-GB has MaisieNeural -- Ximena/Alvaro are the standard "General"
// tier, same category as Sonia/Ryan in English. Ximena is used as
// TaskTtsService's Spanish default since a softer female General voice
// is the closest available approximation to Maisie's tone; there is no
// verified younger-sounding alternative in this locale as of writing.

enum TtsVoice {
  // -- English --
  maisie('en-GB-MaisieNeural', 'Maisie', 'British, child voice — friendliest for young learners'),
  ana('en-US-AnaNeural', 'Ana', 'American, cartoon-style — playful and upbeat'),
  jenny('en-US-JennyNeural', 'Jenny', 'American, warm and comforting'),
  ava('en-US-AvaMultilingualNeural', 'Ava', 'American, expressive — natural storytelling tone'),
  sonia('en-GB-SoniaNeural', 'Sonia', 'British, clear and professional — ideal for instructions'),
  ryan('en-GB-RyanNeural', 'Ryan', 'British, male — calm, steady primary teacher tone'),
  oliver('en-GB-OliverNeural', 'Oliver', 'British, male — crisp, expressive storybook narrator'),

  // -- Spanish (es-ES) --
  // No child-tier voice exists in this locale; these are the standard
  // "General" pair, same tier as Sonia/Ryan above.
  ximena('es-ES-XimenaNeural', 'Ximena', 'Spanish (Spain), female — clear, friendly default'),
  alvaro('es-ES-AlvaroNeural', 'Álvaro', 'Spanish (Spain), male — calm, steady alternative');

  final String edgeId;
  final String displayName;
  final String description;

  const TtsVoice(this.edgeId, this.displayName, this.description);
}

class TtsVoiceDefaults {
  TtsVoiceDefaults._();
  static const TtsVoice defaultEnglish = TtsVoice.sonia;
}