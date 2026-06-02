const Set<String> kidsafeModerationBlockedTerms = {
  // Weapons
  'gun', 'firearm', 'pistol', 'rifle', 'shotgun', 'revolver',
  'ammunition', 'bullet',
  'explosive', 'grenade', 'bomb',
  'gore', 'corpse',
  'murder', 'kill', 'killing', 'stab',

  // Nudity explícita (no piel visible general)
  'nudity', 'naked',
  'sex', 'sexual', 'intercourse',
  'vagina', 'penis', 'genitals',
  'pornography', 'porn', 'xxx',
  'erotic',

  // Drogas (solo las específicas)
  'cocaine', 'heroin', 'methamphetamine',
  'marijuana', 'cannabis',
  'cigarette', 'smoking',
  'vape', 'vaping',
  'syringe', 'needle',
  'overdose',

  // Actividades ilegales graves
  'robbery', 'kidnapping',
  'rape', 'assault',
  'gang', 'gangster',

  // Horror explícito
  'demon', 'devil',
  'zombie',

  // Gambling
  'gambling', 'casino', 'pornographic',
};