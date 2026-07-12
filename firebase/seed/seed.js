/**
 * seed.js — M1 emulator seeder.
 *
 * Loads sampleData.js into the Firestore emulator, running every submission through
 * the SAME validateSubmissionDraft() and buildSubmissionSearchFields() the real
 * createSubmission callable (M5) will use — so seeded documents are shaped exactly
 * like production ones would be, not a hand-rolled approximation. This is also,
 * per 10 §4/13 §B2, the intended basis for the eventual production import script:
 * same functions, Admin SDK either way, different target project.
 *
 * Fixes the web seed script's R6 bug (11-RISKS.md): that script silently defaulted
 * FIRESTORE_EMULATOR_HOST to port 4000 (the Emulator UI) while printing "8080". This
 * one prints exactly what it connects to and defaults to the real Firestore port.
 *
 * Idempotent: re-running clears prior seed-* submissions and the seed author's docs,
 * then rewrites them, so `npm run seed` is safe to run repeatedly against a fresh or
 * already-seeded emulator.
 *
 * Usage:
 *   npm run seed
 *   FIRESTORE_EMULATOR_HOST=192.168.1.20:8080 npm run seed   # device-mode emulator
 */

const admin = require("firebase-admin");
const { validateSubmissionDraft } = require("../functions/lib/validation");
const { buildSubmissionSearchFields } = require("../functions/lib/search");
const sampleData = require("./sampleData");

// R6: the exact bug being avoided is a silent, wrong default. Be explicit and loud.
const FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.FIRESTORE_EMULATOR_HOST = FIRESTORE_EMULATOR_HOST;

// Must match the iOS app's GoogleService-Info.plist PROJECT_ID (abwaan-ios/GoogleService-Info.plist),
// not the docs' shorthand "abwaan-dev" — the emulator partitions data by project ID,
// and seeding into the wrong one is invisible to the app.
const PROJECT_ID = process.env.GCLOUD_PROJECT || "project-abwaan-dev-v2";

console.log(`🌱 seeding Firestore emulator at ${FIRESTORE_EMULATOR_HOST}, project ${PROJECT_ID}`);

admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();
const { FieldValue, Timestamp } = admin.firestore;

// A single official seed account attributes every M1 sample entry — the same shape
// B2 proposes for the real launch-content import (13 §B2: "an official Abwaan account").
const SEED_AUTHOR = {
  uid: "seed-official-abwaan",
  usernameLower: "abwaan",
  usernameOriginal: "Abwaan",
  displayName: "Abwaan Archive",
  bio: "Official seed account for M1 sample content. Not yet native-speaker verified (13 §B2).",
};

// Deterministic, staggered timestamps (not serverTimestamp()) so reseeding is
// idempotent and ordering is stable across runs. The Admin SDK bypasses rules
// entirely for this trusted write path, same as the real import script will.
const BASE_MS = Date.parse("2026-01-01T00:00:00Z");
const STAGGER_MS = 60_000;

async function clearPriorSeedData() {
  const subsSnap = await db.collection("submissions").listDocuments();
  const staleSubs = subsSnap.filter((ref) => /^seed-\d+$/.test(ref.id));

  const batch = db.batch();
  for (const ref of staleSubs) batch.delete(ref);
  batch.delete(db.doc(`profiles/${SEED_AUTHOR.uid}`));
  batch.delete(db.doc(`privateUsers/${SEED_AUTHOR.uid}`));
  batch.delete(db.doc(`usernames/${SEED_AUTHOR.usernameLower}`));
  await batch.commit();

  if (staleSubs.length > 0) {
    console.log(`   cleared ${staleSubs.length} prior seed submission(s)`);
  }
}

async function writeSeedAuthor() {
  const now = Timestamp.fromMillis(BASE_MS);
  await db.doc(`profiles/${SEED_AUTHOR.uid}`).set({
    displayName: SEED_AUTHOR.displayName,
    username: SEED_AUTHOR.usernameLower,
    bio: SEED_AUTHOR.bio,
    photoURL: null,
    createdAt: now,
  });
  await db.doc(`privateUsers/${SEED_AUTHOR.uid}`).set({
    email: "",
    providerId: null,
    lastLoginAt: now,
    blockedUids: [],
  });
  await db.doc(`usernames/${SEED_AUTHOR.usernameLower}`).set({
    usernameOriginal: SEED_AUTHOR.usernameOriginal,
    createdAt: now,
  });
  console.log(`   seed author ready: @${SEED_AUTHOR.usernameLower} (${SEED_AUTHOR.uid})`);
}

async function writeSubmissions() {
  const batch = db.batch();
  const summaries = [];

  sampleData.forEach((entry, index) => {
    // The same validation the createSubmission callable will run at M5 — a shape
    // mismatch here is a real bug, not a seeder quirk.
    const validated = validateSubmissionDraft(entry);

    const { searchIndex, searchKeywords } = buildSubmissionSearchFields({
      type: validated.type,
      title: validated.title,
      text: validated.text,
      meaning: validated.meaning,
      authorUsername: SEED_AUTHOR.usernameLower,
    });

    const id = `seed-${index}`;
    const createdAt = Timestamp.fromMillis(BASE_MS + index * STAGGER_MS);

    batch.set(db.doc(`submissions/${id}`), {
      authorUid: SEED_AUTHOR.uid,
      authorUsername: SEED_AUTHOR.usernameLower,
      type: validated.type,
      language: validated.language,
      origin: validated.origin,
      status: "published",
      title: validated.title,
      text: validated.text,
      meaning: validated.meaning,
      translation: validated.translation,
      source: validated.source,
      createdAt,
      updatedAt: null,
      voteUp: 0,
      voteDown: 0,
      voteScore: 0,
      searchIndex,
      searchKeywords,
      openReportCount: 0,
    });

    summaries.push({ id, type: validated.type, searchIndex, keywords: searchKeywords.length });
  });

  await batch.commit();
  return summaries;
}

async function main() {
  await clearPriorSeedData();
  await writeSeedAuthor();
  const summaries = await writeSubmissions();

  console.log(`✅ seeded ${summaries.length} submission(s):`);
  for (const s of summaries) {
    console.log(`   ${s.id} [${s.type}] "${s.searchIndex}" (${s.keywords} keywords)`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("❌ seed failed:", err);
    process.exit(1);
  });
