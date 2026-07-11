# 06 — Open Questions

**Revised 2026-07-10** with the review-pass decision block below.

Ranked by how much each one blocks Phase 1 (design) and Phase 2 (technical plan). Every item is a real thing I found in the code, not a hypothetical. Where I state a fact, it is cited. Where I need a decision from you, I say so explicitly and I have **not** guessed.

---

## RESOLVED — Phase 2 decisions taken 2026-07-10

| Topic | Decision |
|---|---|
| **Deployment target** | **iOS 27.0 minimum.** Single-path Liquid Glass, no backport forks. Accepts the audience cut (R5). Raised from 26.0 → 27.0 on 2026-07-11: the project shipped on the 27 SDK and the M0 spike built clean there. |
| **Account deletion** | **Tombstone the poetry.** On account deletion, strip `authorUid` / `authorUsername` and reassign submissions and comments to a deleted-user sentinel; purge all personal data (profile, private user, favorites, username reservation, Auth user). The corpus survives; the person does not. Satisfies Guideline 5.1.1(v). |
| **User blocking** | **In v1.** Required by Guideline 1.2. `blocks/{uid}/blocked/{blockedUid}` + block actions + client-side filtering. |
| **App Check** | **Yes, v1.** DeviceCheck / App Attest on the four callables. |
| **Schema v2** | **User will revise it personally.** I flag the exact moment it's needed — start of M1 (see [12-ROADMAP.md](ios-rebuild-docs/12-ROADMAP.md)). Until then the roadmap assumes the [10 §4](ios-rebuild-docs/10-TECH-PLAN.md) draft. |

## RESOLVED — Review-pass decisions taken 2026-07-10 (see [13-REVIEW-AND-REVISIONS.md](ios-rebuild-docs/13-REVIEW-AND-REVISIONS.md))

All accepted. Folded into 07-12; listed here so the decision record stays in one place.

| Topic | Decision |
|---|---|
| **Profile counters** | **Deleted.** `submissionCount` and `publishedCount` do not exist in schema v2. Display counts come from Firestore `count()` aggregation queries. Removes two triggers and the Q6 bug class. (13 §A1) |
| **Auth trigger** | **Deleted.** Replaced by an idempotent `bootstrapProfile` callable invoked by the client after sign-in when no profile exists. Removes the sign-up race, the emulator trap, and the v1/v2 functions split. (13 §A2) |
| **Comment count** | `count()` aggregation on detail appear. No `commentCount` field, no trigger. (13 §A3) |
| **Admin actions** | Hide/restore and report resolution become callables (`setSubmissionStatus`, `resolveReport`). `resolveReport` transactionally decrements `openReportCount`. Submissions become callable-write-only except delete. (13 §A4) |
| **`usernames` registry** | `uid` field dropped from the public docs. Availability needs existence only. (13 §A5) |
| **`lastSeenAt` / `lastLoginAt`** | `lastSeenAt` cut (unused, presence leak). `lastLoginAt` updated on every sign-in inside `bootstrapProfile`, or it does not exist. (13 §A6) |
| **Blocking storage** | `blockedUids: [String]` array on `privateUsers/{uid}`, rule-capped at 500. Not a subcollection. (13 §A7) |
| **Username gate in rules** | Comment and report create rules assert the author profile's `username != null`. The gate is now server-enforced. (13 §A8) |
| **Search normalization** | Apostrophe folding + shared normalize function for documents and queries. (13 §A9) |
| **Client cache** | Normalized `SubmissionStore` keyed by ID; feature models hold ID arrays. (13 §C1) |
| **String Catalog** | All UI strings through a String Catalog from M2, English-only at launch. (13 §C3) |
| **Sign in with Apple** | **Flipped: added at M11.** The Developer account exists by then; the reserved third slot gets filled. Supersedes Q1's "no". (13 §D1) |
| **Share-as-image card** | **In v1.** `ImageRenderer` quote card attached to `ShareLink` alongside the URL. Lands in M3. (13 §D2) |
| **Launch content (open)** | Day-one corpus source still undecided. Owner: Niman. Tracked against M11. (13 §B2) |

## RESOLVED — Phase 0/1 decisions taken 2026-07-10

| # | Decision |
|---|---|
| **Q1** | **No Sign in with Apple.** No Apple Developer account yet, and it cannot be configured or tested without one. Google + email/password ship as-is. See the correction below. |
| **Q2** | Moot. The web app is being retired; it is no longer a reference implementation that must build. |
| **Q3** | Moot. Starting from scratch; the dead Settings claim-form is simply not ported. |
| **Q4** | **Still relevant only as a lesson, not a constraint.** Fresh schema and fresh data mean no stale `searchIndex` values to inherit. The *cause* — deriving search fields from a variable read before it is assigned — is a trap to avoid, not a bug to work around. |
| **Q5** | **Resolved by the schema being free.** Search will respect type/language scopes on iOS. See [07-DESIGN-TRANSLATION.md](ios-rebuild-docs/07-DESIGN-TRANSLATION.md) §Search. |
| **Q6** | Contribution count = **total authored, including hidden**, shown only to the author. Public profiles show published count. Modelled properly rather than counting a loaded page. |
| **Q11** | Moot. New seeder in the new repo. |
| **Repo** | **Separate, sibling folder: `~/Desktop/Hub/Dev/abwaan-ios`.** Not a subdirectory of this one. |
| **Schema** | **Free.** The site is being taken offline. New Firestore schema, new logic. You will revise the model yourself for efficiency and future-proofing. Nothing in `abwaan-v2` is a binding constraint — it is a *specification of behaviour*, not of storage. |

### Correction to my Phase 0 claim about Guideline 4.8

In [04-AUTH-AND-USERS.md](ios-rebuild-docs/04-AUTH-AND-USERS.md) §2 I wrote that offering Google "requires" Sign in with Apple. That was too strong and I am retracting it.

Guideline 4.8 requires that an app using a third-party or social login also offer **another** login option that limits data collection to name and email, permits an undisclosed email address, and does not collect interactions for advertising without consent. Sign in with Apple satisfies this. So, plausibly, does the existing email + password path. The app is therefore not automatically non-compliant.

I am not certain, and review outcomes vary between submissions. The design keeps a third slot in the auth screen so Apple can be added without a redesign if review asks for it.

### Consequence of "schema is free"

The following web-era artifacts exist **only** because of Firestore's constraints as the site's author encountered them. With a clean slate none of them is obligatory, and I will not carry them forward by default:

| Web-era artifact | Why it existed | Status for iOS |
|---|---|---|
| Epoch-millisecond `number` timestamps | `Date.now()` everywhere | Replace with Firestore `Timestamp` |
| `displayName` / `username` copied onto every submission and comment | Avoids a profile read per row | Revisit; stale names are a live bug on the site today |
| `isAdmin` as a Firestore field | Costs a `get()` on every rules evaluation | Custom claim on the ID token |
| `searchIndex` + 60-token `searchKeywords` + dual parallel query | Firestore has no full-text search | Decide deliberately — see [07](ios-rebuild-docs/07-DESIGN-TRANSLATION.md) §Search |
| `reportCount` that never decrements | No decrement path was written | Model reports so the count is derivable |
| Client-written `createdAt` on comments/reports | Written directly from the browser | `serverTimestamp()` |

These are **proposals for Phase 2**, recorded here so they are not silently assumed during Phase 1. Design docs 07–09 do not depend on which way you go, except where noted.

---

## Blocking — I need an answer before Phase 1 can be finished

### Q1. Sign in with Apple — in or out?

**Fact.** The web app offers Google sign-in ([auth.store.ts:70-76](client/src/features/auth/auth.store.ts:70)) and no Apple option anywhere.

**Why it blocks.** App Store Review Guideline 4.8 requires an equivalent privacy-preserving login option when a third-party social login is offered. In practice that means Sign in with Apple. This is the one place where "functionally equivalent to the site" and "shippable on the App Store" genuinely conflict, and I will not resolve it by assumption.

It also has a data-model consequence. `onAuthUserCreate` records `providerId` from `providerData[0]` and derives `displayName` from the provider ([functions/src/index.ts:184-204](functions/src/index.ts:184)). Apple returns the user's name **only on the very first authorization** and supports a private relay email. A new `apple.com` provider therefore changes what lands in `profiles` and `privateUsers`, for both platforms, since they share one Firebase project.

**Options as I see them:**
- **(a)** Add Sign in with Apple to iOS only. Minimal, satisfies 4.8. The web app stays as-is; some users end up with an Apple identity the site cannot offer them.
- **(b)** Add it to both platforms. Consistent, but that is a change to the website, which your rules forbid without explicit instruction.
- **(c)** Drop Google from iOS entirely and ship email + password only. Sidesteps 4.8. Costs the smoothest sign-up path.

**I recommend (a)**, but this is your call.

### Q2. Two undeclared dependencies — is `main` currently broken?

**Fact.** Two packages are imported at module scope but appear in **neither** `client/package.json` nor `client/package-lock.json`:

| Package | Imported at |
|---|---|
| `dompurify` | [sanitize.ts:1](client/src/shared/utils/sanitize.ts:1) |
| `vite-plugin-pwa` | [vite.config.ts:8](client/vite.config.ts:8) |

I verified this by grepping both the manifest and the lockfile; the hit count is zero for each. `client/node_modules` is not present in this checkout, so I could **not** run `npm install && npx vite build` to observe the failure directly. I am reporting what the files say, not a build result.

The `dompurify` case is doubly odd: the only two functions that would use it, `sanitizeHtml` and `stripHtml`, have zero call sites. `sanitizeText` — the one that *is* used, on every rendered string — does not touch DOMPurify at all ([sanitize.ts:25-29](client/src/shared/utils/sanitize.ts:25)).

**Why it blocks.** `CLAUDE.md` instructs that both builds must pass before any item is marked complete. If a clean clone cannot build, that gate is unenforceable, and I cannot verify anything I later claim about the web app's behaviour. It also changes the Phase 2 milestone plan: M0 assumes a working reference environment to diff against.

**Question:** does `npm install && npx vite build` currently succeed on your machine? If yes, something is resolving these that I cannot see (a global install, a stale `node_modules`), and I would like to know what. If no, do you want this fixed as a precondition — which would mean touching the web app — or should I plan around a reference environment that does not build?

### Q3. Is the Settings page's "Claim Handle" form reachable?

**Fact.** [ProfilePage.vue:181-214](client/src/features/profile/ProfilePage.vue:181) renders a username claim form under `v-else` when `profile.username` is falsy. But the router guard redirects *every* authenticated user whose `profile.username === null` to `/onboarding/username`, from every route except `/login*` and onboarding itself ([app/router/index.ts:107-112](client/src/app/router/index.ts:107)).

So the only user who can render `/settings` already has a username, and takes the `v-if` branch. The form looks dead.

**Question:** is this intentional dead code (a leftover from before the onboarding gate), or is there a path I have missed? It determines whether the iOS Settings screen needs a claim affordance at all.

### Q4. `updateSubmission` writes a stale `searchIndex` when a poem's title is edited

**Fact.** In [functions/src/index.ts](functions/src/index.ts):

- Line 731: `resolvedTitle` is computed as `patch.title !== undefined ? patch.title : (existing.title ?? "")`.
- At that moment `patch.title` has not been assigned yet — the assignment from `raw.title` happens later, at line 740.
- Therefore `resolvedTitle` **always** equals the *existing* title.
- Line 765 correctly persists the *new* title into `patch.title`.
- But line 780 rebuilds the search fields with `title: resolvedType === "Poetry" ? resolvedTitle : ""` — the **old** title.

Net effect: editing a poem's title updates `title` but leaves `searchIndex` pointing at the previous title. Since `searchIndex` is the prefix-search key for Poetry ([functions/src/index.ts:146-148](functions/src/index.ts:146)), renamed poems remain findable only under their old name. `searchKeywords` is affected the same way.

I have **not** fixed this — the repo is read-only for this task.

**Question:** confirm this is a genuine bug and not something I have misread. If it is, does the iOS app need to tolerate the resulting stale index (some documents in production will have `searchIndex` disagreeing with `title`), or will it be repaired server-side first? This affects how much I can trust `searchIndex` when designing the iOS search screen.

---

## Important — shapes the design, but Phase 1 can proceed

### Q5. Search silently ignores the active filters

**Fact.** `searchSubmissions` takes only `status`; it never receives `type` or `language` ([submissions.repo.ts:187-203](client/src/data/firestore/submissions.repo.ts:187)). And the filter watcher on the Collections page is wrapped in `if (!hasSearch.value)` ([CollectionsPage.vue:197-201](client/src/features/collections/CollectionsPage.vue:197)).

So a user who selects **Poetry + Somali + Top Rated** and then searches gets results drawn from the entire published archive, with the filter chips still visibly active. The sort is also lost — search results come back in whatever order the two underlying queries produce.

**Question.** On iOS, native search UI (`.searchable` with scopes) makes filter-plus-search feel like it *must* work. Do I:
- **(a)** reproduce the web behaviour exactly (filters ignored during search),
- **(b)** disable/grey the filter controls while a search is active, making the limitation honest, or
- **(c)** treat this as a bug to fix, which means new composite indexes and a change to the shared `searchSubmissions` contract?

(c) is scope drift and I will not do it unless you say so. I lean **(b)** as the most honest non-drifting option.

### Q6. What is the intended "contribution count"?

**Fact.** Three screens show a contribution count from two different sources:

| Screen | Source | Line |
|---|---|---|
| `/desk` | `profile.submissionCount` | [DeskPage.vue:30-32](client/src/features/desk/DeskPage.vue:30) |
| `/settings` | `profile.submissionCount` | [ProfilePage.vue:26-30](client/src/features/profile/ProfilePage.vue:26) |
| `/p/:uid` | `submissions.length` — the *loaded* page count | [PublicProfilePage.vue:96](client/src/features/profile/PublicProfilePage.vue:96) |

On a public profile the number therefore starts at 12 and grows each time you tap "Load more".

Compounding it: `submissionCount` counts **all** submissions including hidden ones (`onSubmissionCreate` fires regardless of status), while the public profile lists only `published`. So even the "correct" figure over-reports for any author with hidden work.

**Question:** which is the intended semantic — total authored, or total publicly visible? I need one answer to design the profile header.

### Q7. Two screens, two names, swapped

**Fact.** `/desk` (the user's personal workspace) has the on-screen heading **"The Study."** ([DeskPage.vue:106](client/src/features/desk/DeskPage.vue:106)), while `/admin` (the moderation console) has the heading **"The Desk."** ([AdminPage.vue:182](client/src/features/admin/AdminPage.vue:182)). The route names are the inverse of the headings. An in-file comment at [DeskPage.vue:9](client/src/features/desk/DeskPage.vue:9) says the naming was updated to match "The Study" aesthetic.

**Question:** what do these two screens get called on iOS? Tab bar labels have to be short and unambiguous, and I would rather not carry a collision forward. Suggested: personal workspace → **"Desk"**, admin → **"Moderation"**. Confirm or override.

### Q8. Does the ambient audio player survive the port?

**Fact.** A globally mounted floating pill plays a filtered, 3%-volume ambient loop, attempts autoplay on mount, skips loading on 2G/3G connections, and pauses on tab-hide ([AudioPlayer.vue](client/src/shared/components/AudioPlayer.vue), mounted at [App.vue:144](client/src/App.vue:144)).

**Why it needs a decision.** On iOS this stops being a floating web widget and becomes an `AVAudioSession` question: does it duck other audio, does it obey the ringer switch, does it keep playing in the background, does it appear on the lock screen? A persistent floating control also fights the Liquid Glass tab bar for the same screen real estate.

**Question:** keep it, cut it, or move it to a Settings toggle? I will not decide this for you. It is the single most "web" thing in the app.

### Q9. `reportCount` never decreases — is that intended?

**Fact.** `onReportCreate` increments `reportCount` and auto-hides at ≥ 3 ([functions/src/index.ts:272-306](functions/src/index.ts:272)). Nothing anywhere decrements it. Dismissing or resolving a report only stamps that report's own `status` / `reviewedAt` / `reviewedBy` ([reports.repo.ts:67-79](client/src/data/firestore/reports.repo.ts:67)).

Consequence: a submission that accrued 3 reports, was auto-hidden, was reviewed, all reports dismissed, and then restored by an admin, still carries `reportCount: 3`. **The very next report re-hides it immediately.** The admin UI hides this by displaying a live count of *open* reports from a collection-group query rather than the stored `reportCount` ([AdminPage.vue:103](client/src/features/admin/AdminPage.vue:103)).

**Question:** intended ratchet, or latent bug? It does not change the iOS UI much, but it changes what I tell you the "N reports" badge means.

---

## Lower priority — noted, not blocking

### Q10. `firebase.json` declares no `functions` emulator

The client hard-codes `connectFunctionsEmulator(functions, '127.0.0.1', 5001)` ([client.ts:50](client/src/data/firebase/client.ts:50)), but [firebase.json:11-28](firebase.json:11) has no `functions` block. It works because 5001 is the CLI default. Meanwhile `database` (9000) and `storage` (9199) *are* declared and neither service is used by any code.

For Phase 2 I will propose an explicit `functions` emulator entry in the iOS dev docs rather than relying on the default. Flagging so you know it is deliberate, not an omission on my part.

### Q11. The seed script points at the wrong port and duplicates search logic

[seed-submissions.cjs:40-43](functions/scripts/seed-submissions.cjs:40) defaults `FIRESTORE_EMULATOR_HOST` to `127.0.0.1:4000` while printing `"Defaulting to 127.0.0.1:8080."`. Port 4000 is the Emulator UI; Firestore is on 8080.

The same file re-implements `buildSubmissionSearchFields` ([line 99](functions/scripts/seed-submissions.cjs:99)), and `TEST_SUBMISSIONS.json` bakes in a third copy of the derived values. `CLAUDE.md` asserts this logic exists in exactly one place. It exists in three. (The fixture's `"status": "pending"` values are harmless — the script hard-codes `status: 'published'` at [line 249](functions/scripts/seed-submissions.cjs:249).)

I will need a working seeder to test the iOS app against the emulator. **Question:** may I create a *new* seeding helper under `/ios-rebuild-docs/` or a new directory, without touching `functions/scripts/`?

### Q12. No App Check, and `usernames` is world-readable

`usernames/{name}` is `allow read: if true` ([firestore.rules:122-125](firestore.rules:122)), so the complete handle→UID mapping is publicly enumerable. There is no App Check anywhere, so the four callables are reachable by anyone holding the public web API key, throttled only by per-UID `rateLimits` documents.

Neither changes the iOS design. Both are worth writing into [11-RISKS.md](ios-rebuild-docs/11-RISKS.md) in Phase 2. Adding App Check would be a change to the shared backend and therefore scope drift — flagging, not proposing.

### Q13. Dead code I intend to simply not port

Confirmed zero call sites. I plan to leave all of it out of the iOS app without further discussion unless you object:

`SearchBar.vue`, `sanitizeHtml()`, `stripHtml()`, `debugLog()`, `showAlert()`, the `aos` dependency, the commented-out newsletter form in `Footer.vue` and its orphan `email` ref, the unbound `isFilterBarVisible` scroll logic in `CollectionsPage.vue`, `public/manifest.json` (superseded by the PWA plugin's generated manifest), and the RTDB + Storage emulator declarations.

Also in this bucket, though not strictly dead:
- `profiles.photoURL` is written once by the auth trigger and **never read by any component** — every avatar in the app is a generated letter initial. iOS should either use it or drop it; today the web app does neither.
- `profiles.lastLoginAt` is written once at account creation and never updated on subsequent logins.
- `useDatabaseStatus()` is named and labelled ("Heartbeat", "SYSTEM ONLINE") as though it probes the database. It only reads `navigator.onLine` ([dbStatus.ts:13](client/src/shared/utils/dbStatus.ts:13)).

### Q14. Admin capabilities with no UI

The rules and the `updateSubmission` callable both permit an admin to **edit** and **delete** any submission ([firestore.rules:166-167](firestore.rules:166), [functions/src/index.ts:616-624](functions/src/index.ts:616)). But the corresponding buttons render under `v-if="isAuthor"` ([SubmissionDetailPage.vue:966](client/src/features/submissions/SubmissionDetailPage.vue:966), [:1009](client/src/features/submissions/SubmissionDetailPage.vue:1009)), so no admin can reach either action on someone else's post. Admins can only hide/restore.

**Question:** on iOS, does the admin get edit/delete on others' content (matching the backend's actual permissions), or only hide/restore (matching the web UI)? Strict functional equivalence says the latter.

---

## Things I explicitly could **not** determine from the code

Stated plainly rather than guessed:

1. **Whether any user currently has `isAdmin: true`.** Nothing in the repo sets it; it must have been set through the Firebase console or an out-of-band Admin SDK call. I cannot see production data.
2. **The real values of `VITE_FIREBASE_API_KEY`, `VITE_FIREBASE_AUTH_DOMAIN`, `VITE_FIREBASE_PROJECT_ID`.** Only `.env.example` is committed. `.firebaserc` names the project `project-abwaan-dev-v2`, which reads like a dev project — **is there a separate production Firebase project?** This materially affects the Phase 2 "debug → emulator, release → prod" scheme.
3. **Whether Google sign-in is configured with an iOS OAuth client** in the Firebase console, and whether the app's bundle ID / reversed client ID exist yet.
4. **Production data shape.** The `submissions` read rule has an `!('status' in resource.data)` clause ([firestore.rules:130](firestore.rules:130)) and `normalizeSubmission` defaults nearly every field ([submissions.repo.ts:27-56](client/src/data/firestore/submissions.repo.ts:27)). Both imply legacy documents predating the current schema exist. I cannot see how many, or which fields they are missing.
5. **Whether `docs/Runbook.md` exists.** [AUDIT_REPORT.md:10](AUDIT_REPORT.md:10) cites `docs/Runbook.md:14-47` for the run instructions, and its own repo tree lists a `docs/` directory. Neither is present in this checkout.
6. **Whether the current web app is deployed and live**, and at what domain. `firebase.json` configures Hosting, but nothing records a deployed URL.
7. **Any push-notification intent.** There is no FCM, no notification code, and no notification-shaped feature (no follows, no mentions, no reply alerts). Phase 2's push plan will therefore be "none proposed" unless you tell me otherwise.
</content>
