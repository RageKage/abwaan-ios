# 03 — Data Model

> Field lists are reconciled across three sources: the TypeScript interfaces in `client/src/data/models/`, the actual write payloads in `functions/src/index.ts` and `client/src/data/firestore/*.repo.ts`, and the constraints in `firestore.rules`. Where they disagree, I say so.

## 0. Cross-cutting conventions

**All timestamps are JavaScript epoch milliseconds stored as Firestore `number`.** Not `Timestamp`, not `serverTimestamp()`. Every write uses `Date.now()` — on the client for comments/favorites/reports/status, on the server for submissions/votes/profiles. This has two consequences for an iOS rewrite:

1. Decoding must map `number` → `Date`, never `Timestamp` → `Date`.
2. Client-written timestamps are **client-clock trusted**. `createdAt` on a comment or report comes from the user's device. The rules only assert `createdAt is number` ([firestore.rules:205](firestore.rules:205)), never that it is close to now.

**Document IDs are load-bearing in three places:**

| Collection | ID | Why |
|---|---|---|
| `usernames/{name}` | lowercased username | Uniqueness via document existence, checked in a transaction |
| `privateUsers/{uid}/favorites/{id}` | the submission ID | Makes favoriting idempotent; no duplicate check needed |
| `submissions/{id}/reports/{uid}` | the reporter's UID | Enforces one report per user per submission structurally |
| `submissions/{id}/votes/{uid}` | the voter's UID | One vote per user per submission |

**Denormalization.** `displayName` and `username` are copied onto `submissions` and `comments` at write time. Reports copy submission title/type/author and reporter username. None of these are back-filled when the source profile changes — a user who edits their display name leaves stale names on all prior submissions and comments.

---

## 1. `profiles/{uid}` — public

Created by the `onAuthUserCreate` trigger ([functions/src/index.ts:189-206](functions/src/index.ts:189)).

| Field | Type | Written by | Notes |
|---|---|---|---|
| `displayName` | `string` | trigger (from provider), user (Settings), `register()` | `""` if the provider gives none |
| `username` | `string \| null` | `claimUsername` callable only | Original casing. `null` until claimed. Immutable thereafter. |
| `bio` | `string` | user (Settings) | `""` initially. No length limit in rules or code. |
| `photoURL` | `string \| null` | trigger only | Copied from the auth provider. **Never read by any component.** |
| `createdAt` | `number` | trigger | |
| `lastLoginAt` | `number` | trigger | Set once at creation. **Never updated on subsequent logins** — nothing writes it again. |
| `submissionCount` | `number` | `onSubmissionCreate` / `onSubmissionDelete` triggers | `FieldValue.increment(±1)` |
| `isAdmin` | `boolean` | **nothing in this codebase** | Must be set out-of-band. Rules forbid clients from writing it. |

TypeScript interface: [profiles.repo.ts:4-13](client/src/data/firestore/profiles.repo.ts:4). Note `isAdmin?: boolean` is optional there but always written as `false` by the trigger.

**Rules** ([firestore.rules:98-109](firestore.rules:98)):
- Read: **public** (`if true`) — anyone, signed in or not, can read any profile.
- Create: owner only, and must not set `username` (or must set it `null`) and must not set `isAdmin: true`.
- Update: owner only, and `username`, `isAdmin`, `submissionCount` must all equal their current values.
- Delete: never.

---

## 2. `privateUsers/{uid}` — private

Created by the same auth trigger ([functions/src/index.ts:207-214](functions/src/index.ts:207)).

| Field | Type | Notes |
|---|---|---|
| `email` | `string` | `""` if the provider gives none |
| `providerId` | `string \| null` | `user.providerData[0].providerId`, e.g. `password`, `google.com` |
| `lastLoginAt` | `number` | Set at creation; never updated afterwards |

**Rules** ([firestore.rules:112-115](firestore.rules:112)): read/create/update owner only; delete never. There is no TypeScript model for this collection and no client code reads it.

### 2a. `privateUsers/{uid}/favorites/{submissionId}`

| Field | Type | Notes |
|---|---|---|
| `submissionId` | `string` | Duplicates the doc ID |
| `savedAt` | `number` | `Date.now()` client-side |

Model: [favorite.ts](client/src/data/models/favorite.ts). Repo: [favorites.repo.ts](client/src/data/firestore/favorites.repo.ts).

**Rules** ([firestore.rules:117-119](firestore.rules:117)): full CRUD, owner only. No field validation whatsoever — a user could write arbitrary fields into their own favorites.

Queried `orderBy('savedAt', 'desc')` with cursor pagination; submissions are then hydrated in `documentId() in [...]` batches of 10.

---

## 3. `usernames/{usernameLower}` — public registry

Written **only** by the `claimUsername` callable, inside a transaction ([functions/src/index.ts:326-332](functions/src/index.ts:326)).

| Field | Type | Notes |
|---|---|---|
| `uid` | `string` | Owner |
| `usernameOriginal` | `string` | Original casing as typed |
| `createdAt` | `number` | |

**Rules** ([firestore.rules:122-125](firestore.rules:122)): `allow read: if true`, `allow write: if false`. Publicly enumerable, Admin-SDK-write-only. No client code reads this collection — availability is discovered only by attempting the claim and catching `already-exists`.

---

## 4. `submissions/{autoId}` — the core collection

Written by `createSubmission` ([functions/src/index.ts:454-482](functions/src/index.ts:454)). This is the authoritative field list; the client's `Submission` interface ([submission.ts:13-39](client/src/data/models/submission.ts:13)) matches it.

| Field | Type | Set on create | Mutable by | Notes |
|---|---|---|---|---|
| `uid` | `string` | caller's UID | never | Author |
| `displayName` | `string` | profile → token name → token email → `"Anonymous"` | never | Denormalized |
| `username` | `string \| null` | from profile | never | Denormalized |
| `type` | `'Proverb' \| 'Poetry'` | ✓ | `updateSubmission` | |
| `language` | `'so' \| 'en'` | ✓ | `updateSubmission` | |
| `origin` | `'original' \| 'shared' \| 'unknown'` | ✓ | `updateSubmission` | UI calls `shared` "attributed" |
| `status` | `'published' \| 'hidden'` | `'published'` | admin, or `onReportCreate` | No moderation queue — everything publishes instantly |
| `statusChangedAt` | `number \| null` | `null` | admin / trigger | |
| `statusChangedBy` | `string \| null` | `null` | admin UID, or the literal `'system'` | |
| `statusReason` | `string \| null` | `null` | admin / trigger | Trigger writes `'auto-report-threshold'` |
| `title` | `string \| null` | title if Poetry, else `null` | `updateSubmission` | 3–120 chars when present |
| `text` | `string` | ✓ | `updateSubmission` | 1–4000 chars |
| `meaning` | `string` | ✓ (may be `""`) | `updateSubmission` | ≤ 2000 |
| `translation` | `string \| null` | ✓ | `updateSubmission` | ≤ 2000 |
| `source` | `Source \| null` | non-null only when `origin === 'shared'` | `updateSubmission` | |
| `createdAt` | `number` | server `Date.now()` | never | |
| `updatedAt` | `number \| null` | `null` | `updateSubmission` | |
| `updatedBy` | `string \| null` | `null` | `updateSubmission` | |
| `voteUp` | `number` | `0` | `voteSubmission` only | `FieldValue.increment` |
| `voteDown` | `number` | `0` | `voteSubmission` only | |
| `voteScore` | `number` | `0` | `voteSubmission` only | `voteUp - voteDown` |
| `searchIndex` | `string` | derived | `updateSubmission` | See below |
| `searchKeywords` | `string[]` | derived | `updateSubmission` | See below |
| `reportCount` | `number` | `0` | `onReportCreate` trigger | Monotonically increasing; **never decremented**, even when reports are dismissed |

`Source` = `{ name: string; url: string \| null; notes: string \| null }` ([submission.ts:7-11](client/src/data/models/submission.ts:7)).

### Search field derivation

Single source of truth: `buildSubmissionSearchFields` at [functions/src/index.ts:128-178](functions/src/index.ts:128).

- `searchIndex` = lowercased **title** for Poetry, lowercased **text** for Proverb. Used for prefix range queries.
- `searchKeywords` = deduplicated token list, in order: lowercased type, lowercased username, then whitespace-split tokens of title, text, and meaning. Constraints: source strings truncated to 600 chars, tokens must be 2–24 chars, array capped at 60 entries.

The client never computes these.

### `normalizeSubmission` defensive defaults

[submissions.repo.ts:27-56](client/src/data/firestore/submissions.repo.ts:27) fills every missing field with a default (`status` → `'published'`, `type` → `'Proverb'`, `language` → `'so'`, `createdAt` → `Date.now()`, …). This means malformed or legacy documents render rather than crash. An iOS decoder should be equally lenient.

### Rules for `submissions` ([firestore.rules:128-167](firestore.rules:128))

- **Read:** `status == 'published'` OR `status` field absent OR caller is admin OR caller is the author. (The "absent" clause supports legacy docs written before `status` existed.)
- **Create:** `if false`. Only the `createSubmission` callable (Admin SDK) can create.
- **Update:** two disjoint branches.
  - *Owner branch*: signed in, is the author, and `uid`, `username`, `displayName`, `status`, `statusChangedAt`, `statusChangedBy`, `statusReason`, `reportCount`, `createdAt`, `voteUp`, `voteDown`, `voteScore` must all be unchanged; `updatedBy` must equal the caller; plus length checks on `title` (3–120), `text` (1–4000), `meaning` (1–2000), `translation` (≤ 2000).
  - *Admin branch*: `|| isAdmin()` — unconditional.
- **Delete:** author or admin.

Two observations on the owner branch:

1. **It is effectively dead for content edits.** All content edits now route through the `updateSubmission` callable, which writes via the Admin SDK and bypasses rules entirely. No client code path performs a rule-checked owner update — `updateSubmissionStatus` is the only client `updateDoc`, and it changes `status`, which the owner branch forbids, so it can only ever pass through the admin branch ([submissions.repo.ts:127-139](client/src/data/firestore/submissions.repo.ts:127)).
2. **The rule requires `meaning.size() >= 1`** ([firestore.rules:164](firestore.rules:164)), but `createSubmission` happily writes `meaning: ""` (it only enforces a maximum). A submission created with an empty meaning could therefore never be updated through the owner branch. Moot given (1), but a real inconsistency.

### Subcollections

#### `submissions/{id}/votes/{uid}`

| Field | Type |
|---|---|
| `value` | `1 \| -1` (a `0` deletes the doc) |
| `createdAt` | `number` |
| `updatedAt` | `number` |

Written only by the `voteSubmission` callable ([functions/src/index.ts:561-575](functions/src/index.ts:561)). **Rules** ([firestore.rules:184-186](firestore.rules:184)): `allow read` for the owning UID only. No `create`/`update`/`delete` rule exists, so all client writes fall through to the default deny. No TypeScript model file.

#### `submissions/{id}/comments/{autoId}`

| Field | Type | Notes |
|---|---|---|
| `submissionId` | `string` | Duplicates the parent ID |
| `uid` | `string` | |
| `displayName` | `string` | Denormalized, rule-verified |
| `username` | `string \| null` | Denormalized, rule-verified |
| `body` | `string` | 1–2000 chars |
| `createdAt` | `number` | Client clock |
| `updatedAt` | `number \| null` | Always `null` — updates are forbidden |

Model: [comment.ts](client/src/data/models/comment.ts). Written client-side via `addDoc`.

**Rules** ([firestore.rules:169-182](firestore.rules:169)):
- Read: gated on `canReadSubmission(id)` — the same published/admin/author logic as the parent.
- Create: signed in, `uid` matches caller, `submissionId` matches the path, caller **has a profile**, and the comment's `username` must equal the profile's username, and `displayName` must equal the profile's display name **or** the auth token's `name` **or** the token's `email`. Body 1–2000.
- Update: never.
- Delete: comment author or admin.

Note that `submissionUsernameAllowed` requires the comment's `username` to equal the profile's `username` exactly. If the profile's username is still `null`, a comment carrying `username: null` satisfies the rule — so the rules alone do *not* require a claimed username in order to comment. What actually prevents it is the router's onboarding gate, which blocks a username-less user from reaching any page. That guard is client-side only.

#### `submissions/{id}/reports/{reporterUid}`

Exactly twelve fields, and the rules enforce that the set is exact — `hasOnly` **and** `hasAll` ([firestore.rules:85-87](firestore.rules:85)).

| Field | Type | Notes |
|---|---|---|
| `submissionId` | `string` | Must equal the path segment |
| `submissionType` | `'Proverb' \| 'Poetry'` | |
| `submissionTitle` | `string` | Denormalized. For a Proverb this is the **full proverb text** ([reports.repo.ts:40](client/src/data/firestore/reports.repo.ts:40)); no length cap in the rules |
| `submissionAuthorUid` | `string` | |
| `submissionAuthorUsername` | `string \| null` | |
| `reporterUid` | `string` | Must equal caller, must equal doc ID |
| `reporterUsername` | `string \| null` | |
| `reason` | `'spam' \| 'abuse' \| 'plagiarism' \| 'inaccurate' \| 'other'` | ≤ 32 chars |
| `details` | `string \| null` | ≤ 2000 chars |
| `status` | `'open' \| 'reviewed' \| 'dismissed'` | Must be `'open'` on create |
| `createdAt` | `number` | Client clock |
| `reviewedAt` | `number \| null` | Must be `null` on create |
| `reviewedBy` | `string \| null` | Must be `null` on create |

Model: [report.ts](client/src/data/models/report.ts).

**Rules** ([firestore.rules:188-217](firestore.rules:188)):
- Create: signed in, doc ID == caller UID, exact key set, `status == 'open'`, review fields `null`, and `!exists()` at that path.
- Read: admin, or the reporter themselves.
- Update: **admin only**, key set still exact, `submissionId` and `reporterUid` and `createdAt` unchanged.
- Delete: admin only.

---

## 5. `rateLimits/{uid}_{action}` — server-internal

| Field | Type |
|---|---|
| `count` | `number` |
| `windowStart` | `number` (epoch ms) |

Read/written transactionally by `checkRateLimit` ([functions/src/index.ts:14-42](functions/src/index.ts:14)). **No rule block exists for this collection**, so the `match /{document=**} { allow read, write: if false; }` catch-all ([firestore.rules:222-224](firestore.rules:222)) denies all client access. Correct by construction — the Admin SDK bypasses rules.

Windows per action: `claimUsername` 5/hour, `createSubmission` 10/hour, `updateSubmission` 30/hour, `voteSubmission` 60/minute.

The window is a fixed (not sliding) bucket: the first call after `windowStart + windowMs` resets `count` to 1.

---

## 6. Relationship diagram

```
Firebase Auth user (uid)
  ├─1:1→ profiles/{uid}                 [public read]
  │        └─ username ──1:1─→ usernames/{usernameLower}   [public read, fn-write]
  ├─1:1→ privateUsers/{uid}             [owner only]
  │        └─1:N→ favorites/{submissionId} ──ref──→ submissions/{id}
  └─1:N→ submissions/{id}   (uid, displayName, username denormalized)
            ├─1:N→ comments/{autoId}    (uid, displayName, username denormalized)
            ├─1:N→ votes/{uid}          (one per user)
            └─1:N→ reports/{reporterUid} (one per user)

rateLimits/{uid}_{action}               [no client access]
```

There are no true joins. Favorites → submissions is resolved with batched `documentId() in [...]` queries of ≤ 10.

---

## 7. Indexes

[firestore.indexes.json](firestore.indexes.json) — 12 composite indexes on `submissions` (COLLECTION scope) and 2 on `reports` (COLLECTION_GROUP scope). `fieldOverrides` is empty.

**`submissions`**

| # | Fields |
|---|---|
| 1 | `uid ASC, createdAt DESC` |
| 2 | `uid ASC, status ASC, createdAt DESC` |
| 3 | `status ASC, createdAt DESC` |
| 4 | `status ASC, voteScore DESC` |
| 5 | `type ASC, status ASC, createdAt DESC` |
| 6 | `language ASC, status ASC, createdAt DESC` |
| 7 | `type ASC, language ASC, status ASC, createdAt DESC` |
| 8 | `type ASC, status ASC, voteScore DESC` |
| 9 | `language ASC, status ASC, voteScore DESC` |
| 10 | `type ASC, language ASC, status ASC, voteScore DESC` |
| 11 | `status ASC, searchIndex ASC` |
| 12 | `status ASC, searchKeywords CONTAINS` |

Indexes 3–10 are the full cross-product needed by the Collections page filter/sort matrix. 11 and 12 back the two halves of dual-query search. 1 and 2 back author listings (`/desk` uses `status: 'all'` → index 1; public profile uses `status: 'published'` → index 2).

**`reports`** (collection-group)

| # | Fields |
|---|---|
| 1 | `status ASC, submissionId ASC` — backs `countOpenReportsBySubmissionIds` |
| 2 | `status ASC, createdAt DESC` — backs the admin report queue |

---

## 8. Cloud Storage

**Not used.** [storage.rules](storage.rules:9) is `allow read, write: if false` for all paths. No client code imports `firebase/storage`. `profiles.photoURL` holds a provider-hosted URL (e.g. `lh3.googleusercontent.com`) and is never rendered — the UI uses letter-initial avatars everywhere.

The Storage emulator is configured on port 9199 ([firebase.json:21-23](firebase.json:21)) and `vite.config.ts` runtime-caches `firebasestorage.googleapis.com`, but nothing exercises either.

## 9. Realtime Database

**Not used.** An emulator is declared on port 9000 ([firebase.json:18-20](firebase.json:18)). No rules file, no code.

---

## 10. Triggered functions (data-model side effects)

| Trigger | Path | Writes |
|---|---|---|
| `onAuthUserCreate` | Auth `onCreate` | `profiles/{uid}` + `privateUsers/{uid}` (both `merge: true`) |
| `onSubmissionCreate` | `submissions/{id}` | `profiles/{uid}.submissionCount += 1` |
| `onSubmissionDelete` | `submissions/{id}` | `profiles/{uid}.submissionCount -= 1`; `bulkWriter` deletes all of `votes`, `comments`, `reports` |
| `onReportCreate` | `submissions/{id}/reports/{uid}` | `reportCount += 1`; if `status == 'published'` and `reportCount >= 3`, sets `status: 'hidden'`, `statusChangedBy: 'system'`, `statusReason: 'auto-report-threshold'` |

No scheduled functions exist.

`onSubmissionDelete` reads each subcollection with `.select()` (projection to keys only) before deleting, which is the right pattern, but it is **not paginated** — a submission with more than a few thousand comments would risk a memory/timeout ceiling ([functions/src/index.ts:257-263](functions/src/index.ts:257)).

---

## 11. Seed data

[TEST_SUBMISSIONS.json](TEST_SUBMISSIONS.json) — 12 records, loaded by [functions/scripts/seed-submissions.cjs](functions/scripts/seed-submissions.cjs) with `--uid`, `--file`, `--project`.

Three things about the seeding path are worth recording, because they affect anyone standing up a local environment for the iOS work:

1. **The fixture's `status` is ignored.** All 12 records carry `"status": "pending"`, which is not a member of the `SubmissionStatus` union. The seeder does not read it — it hard-codes `status: 'published'` on every document it writes ([seed-submissions.cjs:249](functions/scripts/seed-submissions.cjs:249)). So `pending` is a stale leftover in the fixture, not a functional problem. The fixture's pre-computed `searchIndex` / `searchKeywords` are likewise recomputed by the script.
2. **The script is a third copy of `buildSubmissionSearchFields`** ([seed-submissions.cjs:99](functions/scripts/seed-submissions.cjs:99)), alongside the Cloud Function and the fixture's baked-in values. `CLAUDE.md` states this logic lives in exactly one place; it lives in three.
3. **The emulator host default is wrong.** The script defaults `FIRESTORE_EMULATOR_HOST` to `127.0.0.1:4000` while printing `"Defaulting to 127.0.0.1:8080."` ([seed-submissions.cjs:40-43](functions/scripts/seed-submissions.cjs:40)). Port 4000 is the Emulator **UI**; Firestore listens on 8080. Running the seeder without exporting `FIRESTORE_EMULATOR_HOST` yourself will target the wrong port.

Flagged in [06-OPEN-QUESTIONS.md](ios-rebuild-docs/06-OPEN-QUESTIONS.md) Q5.
</content>
