const Set<String> kidsafeModerationBlockedTerms = {
  // =========================
  // Weapons & Violence
  // =========================
  'gun', 'guns', 'weapon', 'weapons', 'firearm', 'firearms',
  'pistol', 'rifle', 'shotgun', 'revolver',
  'ammunition', 'bullet', 'bullets',
  'knife', 'knives', 'blade', 'sword',
  'explosive', 'grenade', 'bomb', 'mines',
  'violence', 'violent', 'fight', 'fighting',
  'blood', 'bleeding', 'gore',
  'corpse', 'dead body', 'death',
  'skull', 'skeleton',
  'war', 'warfare', 'soldier', 'military', 'combat',
  'assassination', 'murder', 'kill', 'killing', 'stab', 'stabbing',

  // =========================
  // Adult / Nudity
  // =========================
  'adult', 'nude', 'nudity', 'naked',
  'sex', 'sexual', 'intercourse',
  'vagina', 'penis', 'breast', 'breasts', 'buttocks', 'genitals',
  'pornography', 'porn', 'xxx',
  'erotic', 'arousal',

  // =========================
  // Drugs & Substances
  // =========================
  'drug', 'drugs', 'cocaine', 'heroin',
  'meth', 'methamphetamine',
  'marijuana', 'cannabis', 'weed',
  'alcohol', 'beer', 'wine', 'liquor',
  'cocktail', 'vodka', 'whiskey',
  'cigarette', 'cigarettes', 'smoking', 'smoke',
  'vape', 'vaping',
  'syringe', 'needle', 'injection',
  'addict', 'addiction', 'overdose',

  // =========================
  // Alcohol Context (important)
  // =========================
  'drink', 'drinking', 'beverage',
  'glass', 'bottle', 'cup',
  'bar', 'pub', 'nightclub', 'party',

  // =========================
  // Illegal Activities
  // =========================
  'robbery', 'theft', 'stealing', 'steal',
  'crime', 'criminal',
  'kidnapping', 'kidnap',
  'abuse', 'assault', 'rape',
  'gang', 'gangster', 'mafia',
  'illegal',

  // =========================
  // Dangerous / Harmful
  // =========================
  'accident', 'crash',
  'burning', 'burn', 'fire',
  'explosion',
  'drowning', 'suffocation',
  'poison', 'toxic',
  'hazard', 'danger', 'dangerous', 'unsafe',

  // =========================
  // Horror / Fear
  // =========================
  'horror', 'scary',
  'ghost', 'demon', 'devil',
  'zombie', 'monster',
  'creepy', 'haunted',

  // =========================
  // Suggestive / Intimate
  // =========================
  'underwear', 'lingerie',
  'suggestive', 'seductive',
  'flirting', 'kiss', 'kissing',

  // =========================
  // Bathroom / Shower Context
  // =========================
  'shower', 'bathroom', 'bath', 'bathtub',
  'wet', 'towel',

  // =========================
  // Gambling
  // =========================
  'gambling', 'casino', 'betting', 'bet',
  'wager', 'lottery', 'slot machine',

  // =========================
  // Adult Lifestyle (light filter)
  // =========================
  'celebrity', 'model', 'selfie', 'posing',
};