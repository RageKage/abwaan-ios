/**
 * search.ts — submission search-field derivation, with the two web bugs fixed
 * (10-TECH-PLAN.md §7) and Somali-aware normalization added (13 §A9).
 *
 * Fixes vs. the web's buildSubmissionSearchFields:
 *   1. searchIndex means ONE thing: `title || text`, always. The web used title for
 *      Poetry and text for Proverbs, so prefix search behaved differently per type.
 *   2. The query must be tokenized the same way the document is. `normalizeText` is the
 *      ONE shared function applied to both sides (document here, query in the search
 *      feature at M11). Test it once, trust it everywhere.
 *
 * A9 normalization: fold typographic apostrophes to ASCII ('  '  ʼ  ´  ` → '), because
 * Somali orthography uses the apostrophe for the glottal stop (ba', la'aan) and users
 * type it three different ways. Case-fold; strip other punctuation to spaces; keep
 * letters, numbers, and the apostrophe.
 *
 * Dependency-free so the seeder (Batch 3) and unit tests can import it directly.
 */

export const SEARCH_KEYWORD_LIMIT = 60;
export const SEARCH_SOURCE_LIMIT = 600;
export const SEARCH_TOKEN_MIN = 2;
export const SEARCH_TOKEN_MAX = 24;

const APOSTROPHES = /[‘’ʼ´`']/gu;
// Keep Unicode letters, Unicode numbers, and the (folded) ASCII apostrophe.
const NON_WORD = /[^\p{L}\p{N}']+/gu;

/**
 * The one shared normalizer. Apply to BOTH the document (index time) and the query
 * (search time) so scoped search tells the truth.
 */
export function normalizeText(value: string): string {
  return String(value ?? "")
    .normalize("NFC")
    .replace(APOSTROPHES, "'")
    .toLowerCase()
    .replace(NON_WORD, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/** Split normalized text into length-bounded tokens. */
export function tokenize(value: string): string[] {
  const normalized = normalizeText(value.slice(0, SEARCH_SOURCE_LIMIT));
  if (normalized.length === 0) return [];
  return normalized
    .split(" ")
    .filter(
      (token) =>
        token.length >= SEARCH_TOKEN_MIN && token.length <= SEARCH_TOKEN_MAX,
    );
}

export interface SearchFieldsInput {
  type: string;
  title?: string | null;
  text: string;
  meaning?: string | null;
  authorUsername?: string | null;
}

export interface SearchFields {
  searchIndex: string;
  searchKeywords: string[];
}

export function buildSubmissionSearchFields(
  input: SearchFieldsInput,
): SearchFields {
  const title = String(input.title ?? "").trim();
  const text = String(input.text ?? "").trim();
  const meaning = String(input.meaning ?? "").trim();

  // Fix #1: one meaning for searchIndex — the title if there is one, else the text.
  const searchIndex = normalizeText(title || text);

  const keywordSources: string[] = [
    input.type,
    ...(input.authorUsername ? [input.authorUsername] : []),
    title,
    text,
    meaning,
  ];

  const seen = new Set<string>();
  const searchKeywords: string[] = [];
  for (const source of keywordSources) {
    for (const token of tokenize(source)) {
      if (seen.has(token)) continue;
      seen.add(token);
      searchKeywords.push(token);
      if (searchKeywords.length >= SEARCH_KEYWORD_LIMIT) break;
    }
    if (searchKeywords.length >= SEARCH_KEYWORD_LIMIT) break;
  }

  return { searchIndex, searchKeywords };
}
