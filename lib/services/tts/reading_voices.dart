enum ReadingVoice {
  maisie('en-GB-MaisieNeural', 'Maisie', 'British, child voice — friendliest for young learners'),
  ana('en-US-AnaNeural', 'Ana', 'American, cartoon-style — playful and upbeat'),
  jenny('en-US-JennyNeural', 'Jenny', 'American, warm and comforting'),
  ava('en-US-AvaMultilingualNeural', 'Ava', 'American, expressive — natural storytelling tone'),
  sonia('en-GB-SoniaNeural', 'Sonia', 'British, clear and professional — ideal for instructions'),
  ryan('en-GB-RyanNeural', 'Ryan', 'British, male — calm, steady primary teacher tone'),
  oliver('en-GB-OliverNeural', 'Oliver', 'British, male — crisp, expressive storybook narrator'),
  
  // New Additions for Story Reading
  guy('en-US-GuyNeural', 'Guy', 'American, deep male — rich, classic audiobook narrator tone'),
  alfie('en-GB-AlfieNeural', 'Alfie', 'British, warm male — casual, expressive dialogue reading');

  final String edgeId;
  final String displayName;
  final String description;

  const ReadingVoice(this.edgeId, this.displayName, this.description);
}
