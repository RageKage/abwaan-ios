// Abwaan v2 Firestore rules — unit tests (M1).
//
// The rules are the only real security in this system (11-RISKS.md R8). Every rule
// gets both an allow case and a negative case; the Done-when for M1 names two of
// these explicitly ("a non-admin cannot hide a submission, a user cannot claim a
// taken username") and they are here.
//
// Run:  npm test        (starts the firestore emulator via emulators:exec)
// CI-ready: no workflow file yet, but `npm test` is the single entry point.

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  serverTimestamp,
  Timestamp,
} from 'firebase/firestore';

const PROJECT_ID = 'demo-abwaan';

/** @type {import('@firebase/rules-unit-testing').RulesTestEnvironment} */
let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

// --- context helpers ---------------------------------------------------------

const guest = () => testEnv.unauthenticatedContext().firestore();
const asUser = (uid) => testEnv.authenticatedContext(uid).firestore();
const asAdmin = (uid = 'admin1') =>
  testEnv.authenticatedContext(uid, { admin: true }).firestore();

/** Seed documents with rules disabled (stands in for the Admin-SDK callables). */
async function seed(fn) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await fn(ctx.firestore());
  });
}

/** A profile as bootstrapProfile + claimUsername would leave it. */
function profileDoc(overrides = {}) {
  return {
    displayName: 'Alice',
    username: 'alice',
    bio: '',
    photoURL: null,
    createdAt: Timestamp.now(),
    ...overrides,
  };
}

/** A private user doc as bootstrapProfile would leave it. */
function privateDoc(overrides = {}) {
  return {
    email: 'alice@example.com',
    providerId: 'password',
    lastLoginAt: Timestamp.now(),
    blockedUids: [],
    ...overrides,
  };
}

/** A published submission. */
function submissionDoc(overrides = {}) {
  return {
    authorUid: 'bob',
    authorUsername: 'bob',
    type: 'Proverb',
    language: 'so',
    origin: 'original',
    status: 'published',
    text: 'Nabad iyo caano.',
    meaning: 'A blessing of peace and milk.',
    createdAt: Timestamp.now(),
    voteUp: 0,
    voteDown: 0,
    voteScore: 0,
    searchIndex: 'nabad iyo caano',
    searchKeywords: ['nabad', 'caano'],
    openReportCount: 0,
    ...overrides,
  };
}

function validReport(overrides = {}) {
  return {
    submissionId: 'sub1',
    submissionType: 'Proverb',
    submissionTitle: '',
    submissionAuthorUid: 'bob',
    submissionAuthorUsername: 'bob',
    reporterUid: 'alice',
    reporterUsername: 'alice',
    reason: 'spam',
    details: null,
    status: 'open',
    createdAt: serverTimestamp(),
    reviewedAt: null,
    reviewedBy: null,
    ...overrides,
  };
}

// --- profiles ----------------------------------------------------------------

describe('profiles', () => {
  it('are world-readable', async () => {
    await seed((db) => setDoc(doc(db, 'profiles/alice'), profileDoc()));
    await assertSucceeds(getDoc(doc(guest(), 'profiles/alice')));
  });

  it('cannot be created by the client (bootstrapProfile only)', async () => {
    await assertFails(
      setDoc(doc(asUser('alice'), 'profiles/alice'), profileDoc()),
    );
  });

  it('owner can edit displayName and bio', async () => {
    await seed((db) => setDoc(doc(db, 'profiles/alice'), profileDoc()));
    await assertSucceeds(
      updateDoc(doc(asUser('alice'), 'profiles/alice'), {
        displayName: 'Alice A.',
        bio: 'Poet.',
      }),
    );
  });

  it('owner cannot change the immutable username', async () => {
    await seed((db) => setDoc(doc(db, 'profiles/alice'), profileDoc()));
    await assertFails(
      updateDoc(doc(asUser('alice'), 'profiles/alice'), { username: 'alice2' }),
    );
  });

  it('rejects an overlong displayName', async () => {
    await seed((db) => setDoc(doc(db, 'profiles/alice'), profileDoc()));
    await assertFails(
      updateDoc(doc(asUser('alice'), 'profiles/alice'), {
        displayName: 'x'.repeat(81),
      }),
    );
  });

  it('cannot smuggle in an unexpected field (e.g. isAdmin)', async () => {
    await seed((db) => setDoc(doc(db, 'profiles/alice'), profileDoc()));
    await assertFails(
      updateDoc(doc(asUser('alice'), 'profiles/alice'), { isAdmin: true }),
    );
  });

  it('non-owner cannot update', async () => {
    await seed((db) => setDoc(doc(db, 'profiles/alice'), profileDoc()));
    await assertFails(
      updateDoc(doc(asUser('mallory'), 'profiles/alice'), { bio: 'hi' }),
    );
  });

  it('cannot be deleted by the client (deleteAccount callable only)', async () => {
    await seed((db) => setDoc(doc(db, 'profiles/alice'), profileDoc()));
    await assertFails(deleteDoc(doc(asUser('alice'), 'profiles/alice')));
  });
});

// --- privateUsers ------------------------------------------------------------

describe('privateUsers', () => {
  it('are readable only by the owner', async () => {
    await seed((db) => setDoc(doc(db, 'privateUsers/alice'), privateDoc()));
    await assertSucceeds(getDoc(doc(asUser('alice'), 'privateUsers/alice')));
    await assertFails(getDoc(doc(asUser('mallory'), 'privateUsers/alice')));
  });

  it('owner can update blockedUids within the cap', async () => {
    await seed((db) => setDoc(doc(db, 'privateUsers/alice'), privateDoc()));
    await assertSucceeds(
      updateDoc(doc(asUser('alice'), 'privateUsers/alice'), {
        blockedUids: ['bob', 'carol'],
      }),
    );
  });

  it('rejects a blockedUids list over 500 (13 §A7)', async () => {
    await seed((db) => setDoc(doc(db, 'privateUsers/alice'), privateDoc()));
    const tooMany = Array.from({ length: 501 }, (_, i) => `u${i}`);
    await assertFails(
      updateDoc(doc(asUser('alice'), 'privateUsers/alice'), {
        blockedUids: tooMany,
      }),
    );
  });

  it('cannot change the pinned email', async () => {
    await seed((db) => setDoc(doc(db, 'privateUsers/alice'), privateDoc()));
    await assertFails(
      updateDoc(doc(asUser('alice'), 'privateUsers/alice'), {
        email: 'evil@example.com',
      }),
    );
  });

  it('favorites are owner-only and stamped with serverTimestamp', async () => {
    await seed((db) => setDoc(doc(db, 'privateUsers/alice'), privateDoc()));
    await assertSucceeds(
      setDoc(doc(asUser('alice'), 'privateUsers/alice/favorites/sub1'), {
        savedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(asUser('alice'), 'privateUsers/alice/favorites/sub2'), {
        savedAt: Timestamp.now(),
      }),
    );
    await assertFails(
      setDoc(doc(asUser('mallory'), 'privateUsers/alice/favorites/sub3'), {
        savedAt: serverTimestamp(),
      }),
    );
  });
});

// --- usernames registry ------------------------------------------------------

describe('usernames', () => {
  it('are world-readable for availability checks', async () => {
    await seed((db) =>
      setDoc(doc(db, 'usernames/alice'), {
        usernameOriginal: 'Alice',
        createdAt: Timestamp.now(),
      }),
    );
    await assertSucceeds(getDoc(doc(guest(), 'usernames/alice')));
  });

  it('a user cannot claim a taken username (client write is closed)', async () => {
    await seed((db) =>
      setDoc(doc(db, 'usernames/alice'), {
        usernameOriginal: 'Alice',
        createdAt: Timestamp.now(),
      }),
    );
    // Existing handle: cannot overwrite.
    await assertFails(
      setDoc(doc(asUser('mallory'), 'usernames/alice'), {
        usernameOriginal: 'Alice',
        createdAt: serverTimestamp(),
      }),
    );
    // Fresh handle: still cannot self-register (claimUsername callable only).
    await assertFails(
      setDoc(doc(asUser('mallory'), 'usernames/mallory'), {
        usernameOriginal: 'Mallory',
        createdAt: serverTimestamp(),
      }),
    );
  });
});

// --- submissions -------------------------------------------------------------

describe('submissions', () => {
  it('published submissions are readable by a guest', async () => {
    await seed((db) => setDoc(doc(db, 'submissions/sub1'), submissionDoc()));
    await assertSucceeds(getDoc(doc(guest(), 'submissions/sub1')));
  });

  it('hidden submissions are not readable by other users', async () => {
    await seed((db) =>
      setDoc(doc(db, 'submissions/sub1'), submissionDoc({ status: 'hidden' })),
    );
    await assertFails(getDoc(doc(asUser('carol'), 'submissions/sub1')));
  });

  it('hidden submissions are readable by their author', async () => {
    await seed((db) =>
      setDoc(
        doc(db, 'submissions/sub1'),
        submissionDoc({ authorUid: 'carol', status: 'hidden' }),
      ),
    );
    await assertSucceeds(getDoc(doc(asUser('carol'), 'submissions/sub1')));
  });

  it('hidden submissions are readable by an admin', async () => {
    await seed((db) =>
      setDoc(doc(db, 'submissions/sub1'), submissionDoc({ status: 'hidden' })),
    );
    await assertSucceeds(getDoc(doc(asAdmin(), 'submissions/sub1')));
  });

  it('cannot be created by the client (createSubmission callable only)', async () => {
    await assertFails(
      setDoc(doc(asUser('bob'), 'submissions/sub1'), submissionDoc()),
    );
  });

  it('a non-admin cannot hide a submission (Done-when negative)', async () => {
    await seed((db) =>
      setDoc(doc(db, 'submissions/sub1'), submissionDoc({ authorUid: 'bob' })),
    );
    // Even the author cannot flip status directly — that is setSubmissionStatus.
    await assertFails(
      updateDoc(doc(asUser('bob'), 'submissions/sub1'), { status: 'hidden' }),
    );
  });

  it('even an admin cannot hide via a direct write (callable-only)', async () => {
    await seed((db) => setDoc(doc(db, 'submissions/sub1'), submissionDoc()));
    await assertFails(
      updateDoc(doc(asAdmin(), 'submissions/sub1'), { status: 'hidden' }),
    );
  });

  it('author can delete their own submission', async () => {
    await seed((db) =>
      setDoc(doc(db, 'submissions/sub1'), submissionDoc({ authorUid: 'bob' })),
    );
    await assertSucceeds(deleteDoc(doc(asUser('bob'), 'submissions/sub1')));
  });

  it('an admin can delete any submission', async () => {
    await seed((db) => setDoc(doc(db, 'submissions/sub1'), submissionDoc()));
    await assertSucceeds(deleteDoc(doc(asAdmin(), 'submissions/sub1')));
  });

  it('a stranger cannot delete a submission', async () => {
    await seed((db) => setDoc(doc(db, 'submissions/sub1'), submissionDoc()));
    await assertFails(deleteDoc(doc(asUser('mallory'), 'submissions/sub1')));
  });
});

// --- comments ----------------------------------------------------------------

describe('comments', () => {
  async function seedAliceAndSubmission() {
    await seed(async (db) => {
      await setDoc(doc(db, 'profiles/alice'), profileDoc());
      await setDoc(doc(db, 'submissions/sub1'), submissionDoc());
    });
  }

  const commentPath = 'submissions/sub1/comments/c1';

  it('a signed-in user with a username can comment', async () => {
    await seedAliceAndSubmission();
    await assertSucceeds(
      setDoc(doc(asUser('alice'), commentPath), {
        authorUid: 'alice',
        authorUsername: 'alice',
        body: 'Waa run.',
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('a user without a username cannot comment (13 §A8 gate)', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'profiles/carol'), profileDoc({ username: null }));
      await setDoc(doc(db, 'submissions/sub1'), submissionDoc());
    });
    await assertFails(
      setDoc(doc(asUser('carol'), commentPath), {
        authorUid: 'carol',
        authorUsername: null,
        body: 'no handle',
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('cannot spoof another authorUid', async () => {
    await seedAliceAndSubmission();
    await assertFails(
      setDoc(doc(asUser('alice'), commentPath), {
        authorUid: 'bob',
        authorUsername: 'bob',
        body: 'impersonation',
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('cannot claim an authorUsername that mismatches the profile', async () => {
    await seedAliceAndSubmission();
    await assertFails(
      setDoc(doc(asUser('alice'), commentPath), {
        authorUid: 'alice',
        authorUsername: 'someoneelse',
        body: 'wrong handle',
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('rejects an overlong body', async () => {
    await seedAliceAndSubmission();
    await assertFails(
      setDoc(doc(asUser('alice'), commentPath), {
        authorUid: 'alice',
        authorUsername: 'alice',
        body: 'x'.repeat(2001),
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('rejects a client-clock createdAt (serverTimestamp required)', async () => {
    await seedAliceAndSubmission();
    await assertFails(
      setDoc(doc(asUser('alice'), commentPath), {
        authorUid: 'alice',
        authorUsername: 'alice',
        body: 'bad clock',
        createdAt: Timestamp.fromMillis(0),
      }),
    );
  });

  it('author can delete their own comment; a stranger cannot', async () => {
    await seedAliceAndSubmission();
    await seed((db) =>
      setDoc(doc(db, commentPath), {
        authorUid: 'alice',
        authorUsername: 'alice',
        body: 'mine',
        createdAt: Timestamp.now(),
      }),
    );
    await assertFails(deleteDoc(doc(asUser('mallory'), commentPath)));
    await assertSucceeds(deleteDoc(doc(asUser('alice'), commentPath)));
  });
});

// --- reports -----------------------------------------------------------------

describe('reports', () => {
  const reportPath = 'submissions/sub1/reports/alice';

  async function seedAliceAndSubmission() {
    await seed(async (db) => {
      await setDoc(doc(db, 'profiles/alice'), profileDoc());
      await setDoc(doc(db, 'submissions/sub1'), submissionDoc());
    });
  }

  it('a signed-in user with a username can file one report', async () => {
    await seedAliceAndSubmission();
    await assertSucceeds(
      setDoc(doc(asUser('alice'), reportPath), validReport()),
    );
  });

  it('a duplicate report is rejected (!exists guard)', async () => {
    await seedAliceAndSubmission();
    await seed((db) =>
      setDoc(doc(db, reportPath), { ...validReport(), createdAt: Timestamp.now() }),
    );
    await assertFails(setDoc(doc(asUser('alice'), reportPath), validReport()));
  });

  it('a user without a username cannot report (13 §A8 gate)', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'profiles/carol'), profileDoc({ username: null }));
      await setDoc(doc(db, 'submissions/sub1'), submissionDoc());
    });
    await assertFails(
      setDoc(doc(asUser('carol'), 'submissions/sub1/reports/carol'), {
        ...validReport(),
        reporterUid: 'carol',
        reporterUsername: null,
      }),
    );
  });

  it('cannot report under a different reporterUid', async () => {
    await seedAliceAndSubmission();
    await assertFails(
      setDoc(doc(asUser('alice'), reportPath), validReport({ reporterUid: 'bob' })),
    );
  });

  it('rejects an unknown reason', async () => {
    await seedAliceAndSubmission();
    await assertFails(
      setDoc(doc(asUser('alice'), reportPath), validReport({ reason: 'because' })),
    );
  });

  it('rejects an extra key (hasOnly)', async () => {
    await seedAliceAndSubmission();
    await assertFails(
      setDoc(doc(asUser('alice'), reportPath), validReport({ extra: 'nope' })),
    );
  });

  it('a status other than open is rejected on create', async () => {
    await seedAliceAndSubmission();
    await assertFails(
      setDoc(doc(asUser('alice'), reportPath), validReport({ status: 'dismissed' })),
    );
  });

  it('admin can read; a non-reporter user cannot', async () => {
    await seedAliceAndSubmission();
    await seed((db) =>
      setDoc(doc(db, reportPath), { ...validReport(), createdAt: Timestamp.now() }),
    );
    await assertSucceeds(getDoc(doc(asAdmin(), reportPath)));
    await assertSucceeds(getDoc(doc(asUser('alice'), reportPath)));
    await assertFails(getDoc(doc(asUser('mallory'), reportPath)));
  });

  it('client cannot update a report (resolveReport callable only)', async () => {
    await seedAliceAndSubmission();
    await seed((db) =>
      setDoc(doc(db, reportPath), { ...validReport(), createdAt: Timestamp.now() }),
    );
    await assertFails(
      updateDoc(doc(asAdmin(), reportPath), { status: 'dismissed' }),
    );
  });
});

// --- default deny ------------------------------------------------------------

describe('default deny', () => {
  it('rateLimits are inaccessible to clients', async () => {
    await assertFails(getDoc(doc(asUser('alice'), 'rateLimits/alice_vote')));
    await assertFails(
      setDoc(doc(asUser('alice'), 'rateLimits/alice_vote'), { count: 1 }),
    );
  });

  it('an unknown collection is denied', async () => {
    await assertFails(getDoc(doc(asUser('alice'), 'secrets/top')));
    await assertFails(setDoc(doc(asUser('alice'), 'secrets/top'), { x: 1 }));
  });
});
