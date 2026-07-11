# 13 — Review and Revisions

> Independent pass over docs 01-12, focused on app design, system logic, and general software quality. Organized as decisions, not commentary. Everything here is veto-able. Items marked **ADOPT** are the ones I would fold into the M1 schema sign-off; items marked **CONSIDER** are optional.

---

## Part A — Schema v2 revisions

These are the changes I would make to the 10 §4 draft before signing it at M1. They compound: together they remove two triggers, two counter fields, one whole class of drift bugs, and the v1/v2 functions split.

### A1. Delete the profile counters. Use aggregation queries. **ADOPT**

The v2 draft carries `submissionCount` and adds `publishedCount`, each maintained by triggers, each a drift risk (the web already proved counters go stale, and Q6 exists because of it). Neither field backs a query. They exist only to be displayed.

Firestore has native `count()` aggregation queries. One aggregation read costs 1 document read per 1000 matched, which at this corpus size is effectively free.

- Public profile: `count()` on `submissions where authorUid == X and status == published`. Composite index 2 already covers it.
- Desk header: `count()` with `status: all`, or just show the loaded count since the author is looking at the full list anyway.

**Removes:** two fields, the `onSubmissionCreate` trigger, half of `onSubmissionDelete`, the entire Q6 bug class, and a small privacy leak (public `submissionCount` minus `publishedCount` currently reveals how many hidden submissions a person has).

### A2. Kill the auth trigger. Bootstrap the profile from a callable. **ADOPT**

The `onAuthUserCreate` trigger is the source of three documented problems:

1. The sign-up race (client profile write vs trigger write, 04 §3.1).
2. The emulator trap (auth emulator without functions emulator = accounts with no profile, 04 §5).
3. The v1/v2 functions split. There is no non-blocking v2 equivalent of `auth.user().onCreate`; the 10 §4 note "(verify)" resolves to "it does not exist without upgrading to Identity Platform blocking functions."

Replace it with an idempotent **`bootstrapProfile` callable** the client invokes once after every sign-in when `SessionModel` sees no profile document. It creates `profiles/{uid}` and `privateUsers/{uid}` if missing and returns the profile. Deterministic ordering, no race, works in the emulator regardless of which emulators are running, and the whole functions codebase becomes v2-only.

`SessionModel` flow becomes: auth resolves → profile snapshot returns null → call `bootstrapProfile` → snapshot fires with the created doc → `needsUsername` state. One extra callable round trip on first sign-in only.

### A3. Decide the comment count. The docs missed it. **ADOPT (aggregation)**

07 §1.4 puts a comment count in the bottom toolbar (`bubble.left` + count), and 08 §8 makes comments lazy-load only when the sheet opens. Those two decisions conflict: there is no `commentCount` field in schema v2, so there is nothing to display before the sheet loads.

Options:
- (a) `count()` aggregation on detail appear. One read, no trigger, no drift. Consistent with A1.
- (b) A `commentCount` field maintained by comment create/delete triggers.
- (c) No number until the sheet opens (just the icon).

Recommend **(a)**.

### A4. Specify the mechanism behind `openReportCount`, and make status changes a callable. **ADOPT**

10 §4 says `openReportCount` is "maintained on both create and resolution" but never says by what. On the web, report resolution and admin hide/restore are **direct client writes**, so nothing server-side could maintain a decrementing counter.

Fix by moving the two admin actions into callables:

- **`setSubmissionStatus(id, status, reason)`** — admin claim required. Replaces the direct `updateDoc` hide/restore path.
- **`resolveReport(submissionId, reporterUid, resolution)`** — admin claim required. Stamps the report and transactionally decrements `openReportCount` on the submission.

`onReportCreate` stays a trigger (report creation remains a direct client write, which preserves its offline queueing) and does `openReportCount += 1` plus the auto-hide check.

**Define the restore semantics while you are here:** with a decrementing count, "restore" means the next auto-hide only fires when *open* reports reach 3 again. State that explicitly in the rules doc so the ratchet bug (Q9) is closed by design, not by accident.

Side benefit: the `|| isAdmin()` branch on the submissions update rule disappears. With create already `if false` and content edits already going through `updateSubmission`, the submissions collection becomes **callable-write-only except delete**. The rules file shrinks and every remaining write path is App-Check-attested.

Keep as direct client writes (deliberately, for the offline queue): comments, favorites, report creation, profile displayName/bio, and submission delete (the fixed, paginated `onSubmissionDelete` trigger handles cleanup).

### A5. Drop `uid` from the public `usernames` registry. **ADOPT**

Availability checking only needs document existence. The claim transaction only needs existence. Account deletion finds the doc via `profiles/{uid}.username`, not the reverse. Keeping `uid` in a world-readable collection publishes the complete handle-to-UID mapping for no consumer. Store `usernameOriginal` and `createdAt` only.

### A6. Cut `lastSeenAt`. Fix or cut `lastLoginAt`. **ADOPT**

v2 adds `lastSeenAt` to the **public** profile "actually updated, unlike the web." Two problems: nothing in the app displays it, and a public last-seen timestamp is a presence leak users did not opt into. This repeats the web's `photoURL` mistake (a field written and never read) with worse privacy properties. Cut it. If you ever want it, it belongs in `privateUsers`.

`privateUsers.lastLoginAt`: either update it on every sign-in (one write) or drop it. Write-once-then-never is the web behavior and it is dead weight.

### A7. Blocks as an array, not a subcollection. **ADOPT**

10 §9.2 proposes `blocks/{uid}/blocked/{blockedUid}`. Since filtering is client-side anyway, the entire block list must load at session start. A subcollection means a query; an array field means it arrives free with a document you already read.

Put `blockedUids: [String]` on `privateUsers/{uid}`, rule-capped (`size() <= 500`). One field, zero queries, trivially observable via the existing private-doc read. A subcollection only wins past hundreds of blocks, which this app will not see.

Note one interaction the docs miss: client-side filtering **shrinks pages**. If a page of 12 contains 5 blocked authors, the list shows 7. The pagination loop should keep fetching until it has a full page or the cursor exhausts. Cheap to write, easy to forget.

### A8. Close the username gate hole in the rules. **ADOPT**

03 §4 documents that the web's rules allow commenting with `username: null`; only the client-side router gate prevents it. iOS keeps a client-side gate (the onboarding cover), so the hole survives unless the rules close it.

Since comments and reports already denormalize `authorUsername` and the rules already verify it against the profile, add one assertion: the profile's `username != null` on comment and report create. The gate becomes real.

### A9. Somali-aware search normalization. **ADOPT (small)**

While rewriting `buildSubmissionSearchFields` (single `searchIndex = title ?? text`, tokenized queries — both already planned, both endorsed), add normalization specific to this corpus:

- Fold typographic apostrophes to ASCII (`'` `'` `ʼ` → `'`). Somali orthography uses the apostrophe for the glottal stop (`ba'`, `la'aan`); users will type it three different ways.
- Case-fold before tokenizing (already done) and strip punctuation consistently on **both** the document and the query side, with one shared function, tested.

This is the cheapest search-quality win available and it is unique to this app's content.

### A10. Tombstone details. **ADOPT**

The tombstone decision is right. Pin down the mechanics: `authorUid` set to the literal sentinel `"deleted"`, `authorUsername` set to `null`, UI renders "Former member" (or Somali equivalent). Reserve the sentinel so no rule treats `"deleted"` as an ownable UID, and make sure `PublicProfile` routes guard against pushing a profile for it.

---

## Part B — Logic gaps the docs do not close

### B1. Pending-action replay must survive the username gate

08 §4 requires that after action-triggered sign-in "the pending action completes." But sign-in can land in `needsUsername`, which presents the full-screen onboarding cover *above everything*. The pending vote/save/comment must survive: tap → AuthSheet → sign in → onboarding cover → claim handle → **then** replay.

Implement as an explicit `PendingAction` enum held on `SessionModel`, replayed on the transition into `.active` (not on sheet dismiss). Same mechanism covers the `/contribute` deep link while signed out. Write it into the tech plan as a named component; it is the kind of thing that gets hacked in four different ways otherwise.

### B2. Launch-day content

Fresh schema, retired site, empty archive. An archive app with nothing in it is dead on first open, and none of the twelve docs says where launch content comes from. You need one of:

- A production import script (Admin SDK, reusing the M1 seeder against prod), plus a decision on who those submissions are attributed to (an official "Abwaan" account?).
- Or a pre-launch contribution period with early users.

Not a technical blocker, but it belongs on the roadmap as an M11-adjacent task with an owner (you).

### B3. Favorites orphan cleanup

The web silently drops favorites whose submissions were deleted and leaves the orphan docs forever. In v2, when hydration finds a missing submission, delete the favorite doc opportunistically. One line in the repository, permanent hygiene.

### B4. Vote hot spots — note, do not build

Every vote is a transaction on the submission doc. Firestore sustains roughly 1 write/sec per document before contention. Irrelevant at this scale; worth one sentence in RISKS so nobody "fixes" it preemptively with sharded counters.

---

## Part C — Client architecture

### C1. A normalized submission cache is the one structural addition I would insist on

The 10 §2 plan mirrors the seven Pinia stores as per-feature `@Observable` models. The web's known divergence bug class comes exactly from this: the same submission lives in the Archive list, the Search results, the Desk, and the Detail screen as **separate copies**, so a vote on Detail does not move the score on the Archive row behind it.

Fix at the root: one `@MainActor @Observable SubmissionStore` holding `[String: Submission]`, the single source of truth. Feature models hold **ordered ID arrays plus cursors**, not submission values. Rows read through the store. A vote mutates one dictionary entry and every list showing that submission updates for free.

This is less code, not more: optimistic vote/rollback is written once, in the store, instead of once per feature model. It is the single highest-leverage architecture change relative to the current plan.

### C2. `LoadState`: derive `.empty`, do not store it

`case empty` alongside `case loaded(Value)` invites the bug where a list transitions to loaded-but-empty without anyone remembering to map it. Make it four cases (`idle / loading / loaded / failed`) and compute emptiness from `loaded([])` at the view. One fewer illegal state.

### C3. String Catalog from M2, even shipping English-only

09 §9 flags UI localization as the real missed opportunity and then defers it. The expensive part of localization is not translation, it is retrofitting hardcoded strings. Discipline from the first screen (every user-facing string through the String Catalog) costs nothing now and makes a Somali UI a translation task later instead of a refactor. For an app whose whole reason to exist is Somali language preservation, an English-only interface should at least be a *reversible* decision.

### C4. iOS version note

Target **iOS 27.0 minimum** (raised from 26.0 on 2026-07-11). The Xcode project scaffolded on the iOS 27 SDK and the M0 spike built clean there, so there was no reason to hold the minimum at 26 — standardizing on 27 removes the doc-vs-project mismatch. Liquid Glass is still the premise and still does not backport. The docs' `(verify)` annotations were the right posture, and the M0 hardware spike has since confirmed the core Liquid Glass API set (see R4).

---

## Part D — Scope: two flips and two candidates

### D1. Sign in with Apple: flip from "no" to "add at M11". **ADOPT**

Q1's answer was "no, because no Developer account yet." But you cannot ship *at all* without enrolling, so by M11 the blocker is gone by definition. R9 prices a possible 4.8 rejection at "a week of calendar time"; SIWA is roughly a day once enrolled (an `OAuthProvider("apple.com")`, a capability, and the button whose slot 09 already reserves). Cheap insurance against the app's first review. Move it into M11 as a line item.

### D2. Share-as-image card. **CONSIDER for v1, recommend yes**

The plan replaces the web's clipboard hack with `ShareLink` and a URL. For a proverb-and-poetry archive, the organic growth loop is people posting *quote cards* to WhatsApp, X, and Instagram stories — a rendered image of the text, beautifully set in the serif, with the handle and app name. SwiftUI's `ImageRenderer` makes this a small component, not a feature: render the existing detail typography into an image and attach it to the same `ShareLink` alongside the URL.

This is the one addition where a modest effort changes the app's reach. Everything shared today is a link that dies if the domain lapses (R13); an image survives anywhere.

### D3. Daily-proverb widget. **CONSIDER for v1.5, not v1**

WidgetKit home-screen widget showing one published entry a day. On-brand, high retention value, reads-only backend cost. Post-ship.

### D4. Everything else stays out

Push, iPad, avatar upload, Algolia/Typesense, collections-of-favorites, Spotlight indexing: agreed out of v1, each a clean later addition. The docs' scope discipline is the best thing about them; D2 is the only place I would spend new scope before shipping.

---

## Part E — What stands as-is (endorsed, no changes)

So this doc reads as a diff, not a rubber stamp:

- Four-tab structure with `role: .search`; Contribute as a task, not a tab; Admin pushed from Settings. Correct on all three.
- Glass-for-chrome, opaque-for-reading. The single best design rule in the set. Hold the line.
- Action-triggered auth, never a launch wall. Correct, with B1's replay mechanism added.
- iOS 27 minimum, single-path chrome. Right trade for this app.
- Search Option 2 with the Typesense door open. Right sequencing.
- Tombstone account deletion, blocking in v1, App Check in v1. All correct and correctly prioritized (R1/R2 as ship gates).
- No push, no FCM. Correct; there is nothing to notify about.
- Repository protocol + fakes, rules tests before Swift. Keep exactly as written.
- `Timestamp` + `serverTimestamp()` everywhere, `isAdmin` as a custom claim, `authorUsername`-only denormalization, `attributed` on the wire. All four v2 changes are right; A1-A10 above build on them rather than replacing them.

---

## Part F — Roadmap impact

Almost everything above lands inside existing milestones:

| Item | Lands in |
|---|---|
| A1-A10 schema revisions | M1 (your schema sign-off — this doc is input to it) |
| B1 pending-action replay | M4 (name it in the milestone) |
| B3 orphan cleanup | M6 |
| C1 SubmissionStore | M2 (architecture is set here; retrofitting later is the expensive path) |
| C2, C3 | M2 |
| A4 callables (`setSubmissionStatus`, `resolveReport`) | M10 |
| A2 `bootstrapProfile` | M1 (function) + M4 (client) |
| D1 Sign in with Apple | M11 |
| D2 share card | M3 or M11 (the detail typography it renders exists at M3) |
| B2 launch content plan | Parallel to M11, owner: you |

No milestone is added; M1 and M2 get slightly heavier, which is the correct place for weight.

---

## Part G — Decisions: **ALL ACCEPTED 2026-07-10**

1. A1 counters-to-aggregation: ✅ yes.
2. A2 bootstrapProfile replacing the auth trigger: ✅ yes.
3. A4 admin actions as callables: ✅ yes.
4. A7 blocks as an array on privateUsers: ✅ yes.
5. D1 Sign in with Apple at M11: ✅ yes.
6. D2 share-as-image card in v1: ✅ yes.
7. B2 launch content: **still open.** Owner: Niman. Tracked in M11.

All revisions are folded into 06, 07, 08, 09, 10, 11, and 12 as of this date. Docs 01-05 are the Phase 0 audit of the retired web app and stay untouched by design. [10 §4](ios-rebuild-docs/10-TECH-PLAN.md) as revised is the signed schema for M1.
