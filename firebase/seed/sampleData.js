/**
 * sampleData.js — M1 emulator seed corpus.
 *
 * Gemini-sourced Somali proverbs and poetry (Niman, 2026-07-11). Correctly shaped
 * for schema v2, not yet native-speaker verified — translations and the "attributed"
 * entry's provenance need a pass before launch (13 §B2). Fine for M1: the point here
 * is a populated, correctly-shaped emulator, not launch content.
 *
 * Field names match SubmissionDraftInput exactly (functions/src/validation.ts) on
 * purpose — this is what validateSubmissionDraft() consumes, unchanged.
 *
 * Includes one apostrophe entry ("la'aan") to exercise A9 normalization and one
 * multi-line Gabay to exercise text with embedded newlines.
 */

module.exports = [
  {
    type: "Proverb",
    title: null,
    text: "Aqoon la'aan waa iftiin la'aan.",
    meaning:
      "Knowledge is equated to light, and its absence leaves one in darkness. It emphasizes the critical importance of education and awareness in navigating life.",
    translation: "Lack of knowledge is lack of light.",
    language: "so",
    origin: "original",
  },
  {
    type: "Proverb",
    title: null,
    text: "Far keliya fool ma dhaqdo.",
    meaning:
      "A single finger cannot wash a face. This proverb highlights the necessity of cooperation and collective effort to accomplish tasks.",
    translation: "A single finger does not wash a face.",
    language: "so",
    origin: "original",
  },
  {
    type: "Proverb",
    title: null,
    text: "Nin aan dhididin, dhagax kama helo.",
    meaning:
      "He who does not sweat, gets no stones. It teaches that one must work hard and exert effort to achieve anything of value.",
    translation: "A man who does not sweat, does not get stones.",
    language: "so",
    origin: "original",
  },
  {
    type: "Proverb",
    title: null,
    text: "Rag waa ragii hore, hadalna waa tii hore.",
    meaning:
      "Men are the men of the past, and speech is the speech of the past. It expresses nostalgia for the wisdom, integrity, and eloquence of previous generations.",
    translation: "Men are those of the past, and speech is that of the past.",
    language: "so",
    origin: "original",
  },
  {
    type: "Poetry",
    title: "Dardaaran",
    text: "Nin ragow haween u galgalan, waanadaa garane\nGeedkii ninkii la gubay, waad u jeedaan-e\nSida gorayga ciidda leh, ha noqon, gabayga aad sheegto.",
    meaning:
      "This excerpt is attributed to the famous poet Sayid Mohamed Abdulle Hassan, advising men to be mindful of their actions and not to be reckless in their dealings or speech, comparing folly to an ostrich burying its head in the sand.",
    translation:
      "Oh man, do not trifle with women, understand the advice,\nYou see what happened to the man whose tree was burned,\nDo not be like the ostrich in the sand, in the poems you recite.",
    language: "so",
    origin: "attributed",
  },
  {
    type: "Poetry",
    title: "Ninkii aan lahayn",
    text: "Ninkii aan lahayn geel jire\nEe aan lahayn gabay tirshe\nMa guuleysto weligiis.",
    meaning:
      "This classic lines, often associated with nomadic oral tradition, suggest that a man who lacks both wealth (symbolized by camels) and wisdom (symbolized by the ability to compose poetry) will never find success.",
    translation:
      "The man who has no camel herds,\nAnd who has no poetry to compose,\nHe never succeeds.",
    language: "so",
    origin: "original",
  },
];
