/**
 * validation.ts — the single source of truth for Abwaan's write constraints.
 *
 * These limits MIRROR firestore.rules EXACTLY (10-TECH-PLAN.md §11, 11-RISKS.md R15).
 * The rules are the only enforcement for direct client writes (profile displayName/bio,
 * comment body, report fields, blockedUids); the callables enforce the submission-content
 * limits (submissions are callable-write-only). The Swift `SubmissionDraft` (M5) and the
 * seeder (Batch 3) both mirror this file. If a number changes here, it changes in the
 * rules and in Swift in the same breath — no drift.
 *
 * This module is deliberately dependency-free (no firebase-functions import) so it can be
 * imported by the seeder and unit-tested in isolation.
 */

// ---- limits (mirror firestore.rules) ----------------------------------------

export const LIMITS = {
  // profiles — direct client write; rules are the sole enforcement
  displayNameMin: 1,
  displayNameMax: 80,
  bioMax: 500,
  // comments — direct client write
  commentBodyMin: 1,
  commentBodyMax: 2000,
  // reports — direct client write
  reportReasonMax: 32,
  reportDetailsMax: 2000,
  // blockedUids — direct client write (13 §A7)
  blockedUidsMax: 500,
  // submissions — callable-write-only; enforced in createSubmission/updateSubmission
  titleMin: 3,
  titleMax: 120,
  textMin: 1,
  textMax: 4000,
  meaningMin: 1,
  meaningMax: 2000,
  translationMax: 2000,
  sourceNameMax: 200,
  sourceNotesMax: 600,
} as const;

// ---- enums (wire values — note: origin is 'attributed', not the web's 'shared') ----

export const SUBMISSION_TYPES = ["Proverb", "Poetry"] as const;
export const LANGUAGES = ["so", "en"] as const;
export const SUBMISSION_ORIGINS = ["original", "attributed", "unknown"] as const;
export const SUBMISSION_STATUSES = ["published", "hidden"] as const;
export const REPORT_REASONS = [
  "spam",
  "abuse",
  "plagiarism",
  "inaccurate",
  "other",
] as const;

export type SubmissionType = (typeof SUBMISSION_TYPES)[number];
export type LanguageCode = (typeof LANGUAGES)[number];
export type SubmissionOrigin = (typeof SUBMISSION_ORIGINS)[number];
export type SubmissionStatus = (typeof SUBMISSION_STATUSES)[number];
export type ReportReason = (typeof REPORT_REASONS)[number];

// ---- username (mirrors the web's normalizeUsername) -------------------------

export const USERNAME_PATTERN = /^[a-z0-9_]{3,20}$/;

/** Raised by validators. Callables map this to an `invalid-argument` HttpsError. */
export class ValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ValidationError";
  }
}

export function normalizeUsername(raw: string): {
  usernameOriginal: string;
  usernameLower: string;
} {
  const usernameOriginal = String(raw ?? "").trim();
  const usernameLower = usernameOriginal.toLowerCase();
  if (!USERNAME_PATTERN.test(usernameLower)) {
    throw new ValidationError(
      "Username must be 3-20 characters: a-z, 0-9, underscore.",
    );
  }
  return { usernameOriginal, usernameLower };
}

// ---- submission source ------------------------------------------------------

export interface SubmissionSource {
  name: string;
  url: string | null;
  notes: string | null;
}

function isValidUrl(value: string): boolean {
  try {
    // eslint-disable-next-line no-new
    new URL(value);
    return true;
  } catch {
    return false;
  }
}

// ---- submission draft -------------------------------------------------------

export interface SubmissionDraftInput {
  type?: unknown;
  language?: unknown;
  origin?: unknown;
  title?: unknown;
  text?: unknown;
  meaning?: unknown;
  translation?: unknown;
  source?: {
    name?: unknown;
    url?: unknown;
    notes?: unknown;
  } | null;
}

/** A validated, normalized submission ready to be written (sans server-side fields). */
export interface ValidatedSubmission {
  type: SubmissionType;
  language: LanguageCode;
  origin: SubmissionOrigin;
  title: string | null;
  text: string;
  meaning: string | null;
  translation: string | null;
  source: SubmissionSource | null;
}

function asString(value: unknown): string {
  return typeof value === "string" ? value : "";
}

/**
 * Validates and normalizes a submission draft against LIMITS. Throws ValidationError
 * on the first violation. Used by createSubmission/updateSubmission (M5) and the seeder.
 *
 * Rules mirrored:
 *  - title required iff Poetry (3–120); absent/null for Proverb
 *  - text required (1–4000)
 *  - meaning required-or-absent (10 §4 #6): if present, 1–2000; may be null/absent
 *  - translation optional (≤2000)
 *  - source optional; name ≤200, notes ≤600, url must parse
 */
export function validateSubmissionDraft(
  input: SubmissionDraftInput,
): ValidatedSubmission {
  const type = asString(input.type).trim();
  if (!(SUBMISSION_TYPES as readonly string[]).includes(type)) {
    throw new ValidationError(`type must be one of ${SUBMISSION_TYPES.join(", ")}.`);
  }

  const language = asString(input.language).trim();
  if (!(LANGUAGES as readonly string[]).includes(language)) {
    throw new ValidationError(`language must be one of ${LANGUAGES.join(", ")}.`);
  }

  const origin = asString(input.origin).trim() || "original";
  if (!(SUBMISSION_ORIGINS as readonly string[]).includes(origin)) {
    throw new ValidationError(
      `origin must be one of ${SUBMISSION_ORIGINS.join(", ")}.`,
    );
  }

  const text = asString(input.text).trim();
  if (text.length < LIMITS.textMin || text.length > LIMITS.textMax) {
    throw new ValidationError(
      `text must be ${LIMITS.textMin}-${LIMITS.textMax} characters.`,
    );
  }

  let title: string | null = null;
  if (type === "Poetry") {
    title = asString(input.title).trim();
    if (title.length < LIMITS.titleMin || title.length > LIMITS.titleMax) {
      throw new ValidationError(
        `title must be ${LIMITS.titleMin}-${LIMITS.titleMax} characters for Poetry.`,
      );
    }
  } else if (asString(input.title).trim().length > 0) {
    throw new ValidationError("title is only allowed for Poetry.");
  }

  let meaning: string | null = null;
  const meaningRaw = asString(input.meaning).trim();
  if (meaningRaw.length > 0) {
    if (meaningRaw.length < LIMITS.meaningMin || meaningRaw.length > LIMITS.meaningMax) {
      throw new ValidationError(
        `meaning must be ${LIMITS.meaningMin}-${LIMITS.meaningMax} characters when present.`,
      );
    }
    meaning = meaningRaw;
  }

  let translation: string | null = null;
  const translationRaw = asString(input.translation).trim();
  if (translationRaw.length > 0) {
    if (translationRaw.length > LIMITS.translationMax) {
      throw new ValidationError(
        `translation must be ≤${LIMITS.translationMax} characters.`,
      );
    }
    translation = translationRaw;
  }

  let source: SubmissionSource | null = null;
  if (input.source && asString(input.source.name).trim().length > 0) {
    const name = asString(input.source.name).trim();
    if (name.length > LIMITS.sourceNameMax) {
      throw new ValidationError(`source.name must be ≤${LIMITS.sourceNameMax} characters.`);
    }
    const urlRaw = asString(input.source.url).trim();
    if (urlRaw.length > 0 && !isValidUrl(urlRaw)) {
      throw new ValidationError("source.url must be a valid URL.");
    }
    const notesRaw = asString(input.source.notes).trim();
    if (notesRaw.length > LIMITS.sourceNotesMax) {
      throw new ValidationError(`source.notes must be ≤${LIMITS.sourceNotesMax} characters.`);
    }
    source = {
      name,
      url: urlRaw || null,
      notes: notesRaw || null,
    };
  }

  // Membership validated above; narrow the plain strings to their unions.
  return {
    type: type as SubmissionType,
    language: language as LanguageCode,
    origin: origin as SubmissionOrigin,
    title,
    text,
    meaning,
    translation,
    source,
  };
}
