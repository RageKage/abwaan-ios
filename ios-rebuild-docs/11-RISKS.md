# 11 — Risks

> Phase 2. Ordered by expected pain, not by category. Each has a concrete mitigation, not a shrug.
>
> **Revised 2026-07-10**: R9 retired (Sign in with Apple ships at M11); the counter-drift and auth-trigger risk classes are retired by schema design — see the expanded "Explicitly not risks" list.
>
> **Likelihood** and **Impact** are my judgement, not measurements.

---

## Tier 1 — Will hurt, and will hurt before you ship

### R1. Guideline 1.2 — no way to block a user

**Likelihood: certain · Impact: rejection**

App Store Guideline 1.2 requires apps with user-generated content to provide the ability to **block abusive users**. Abwaan has poetry, comments, profiles, and reporting. It has no blocking. I grepped: there is no block feature anywhere in `abwaan-v2`.

The site got away with it because the App Store does not review websites.

**Mitigation.** Build it. `blocks/{uid}/blocked/{blockedUid}`, a "Block this user" action in the submission and comment overflow menus, and client-side filtering of blocked users' content. Firestore cannot filter this server-side without denormalizing block lists into every query, so client-side filtering is the accepted compromise across the ecosystem. Budget one milestone. This is not optional and it is not polish.

**Also required by 1.2 and currently absent:** published contact information (the web's `mailto:` lived in the footer, which we're cutting — it needs a Settings row), and a stated commitment to act on reports within 24 hours.

### R2. Guideline 5.1.1(v) — no account deletion

**Likelihood: certain · Impact: rejection**

Any app supporting account creation must support in-app account deletion. Zero occurrences of `deleteUser` in the web app. `firestore.rules` says `allow delete: if false` on both `profiles` and `privateUsers`.

**Mitigation.** Settings row → re-authenticate → callable that purges `privateUsers/{uid}` and its `favorites`, deletes `profiles/{uid}`, releases `usernames/{lower}`, then deletes the Auth user.

**The unresolved part is a product decision, not a technical one:** what happens to a deleted user's submissions and comments? For an archive whose stated purpose is *preservation of cultural material*, cascade-deleting a user's poetry on account deletion may be actively wrong. Tombstoning — strip `authorUid` and `authorUsername`, reassign to a deleted-user sentinel — preserves the corpus while removing the personal data, and is what the guideline actually asks for. **I need your answer before this milestone.**

### R3. Swift 6 strict concurrency vs. the Firebase SDK

**Likelihood: high · Impact: days of friction**

Firebase's iOS SDK is Objective-C underneath. `DocumentSnapshot`, `QuerySnapshot`, `ListenerRegistration`, and the `Firestore` singleton are not `Sendable`, and completion handlers arrive on arbitrary queues. Under Swift 6 language mode with strict concurrency, this produces a wall of diagnostics that are tedious rather than interesting.

The web app had none of this — JavaScript is single-threaded and Pinia stores are just objects.

**Mitigation.** `@preconcurrency import FirebaseFirestore`. Confine Firebase types to the repository layer and never let a `DocumentSnapshot` cross into an `@Observable` model — map to `Sendable` value types at the boundary. This is already the architecture in [10 §2](ios-rebuild-docs/10-TECH-PLAN.md); the concurrency requirement is the *reason* for it, not a consequence.

If it becomes a tarpit, ship v1 in Swift 5 language mode with `-strict-concurrency=targeted` and migrate later. Don't lose a week to this.

### R4. Liquid Glass is a new API surface, and I cannot compile against it

**Likelihood: high · Impact: rework**

Everything marked **(verify)** in [09](ios-rebuild-docs/09-DESIGN-SYSTEM.md) and [10](ios-rebuild-docs/10-TECH-PLAN.md) was, when written, from memory of the iOS SDK rather than a build. **Update 2026-07-11 — the M0 spike built and ran clean on the iOS 27 SDK, confirming the core set:** `Tab(role: .search)`, `.tabBarMinimizeBehavior(.onScrollDown)`, `.tabViewBottomAccessory`, `.scrollEdgeEffectStyle(_:for:)`, `GlassEffectContainer`, `.buttonStyle(.glass)` / `.glassProminent`, and `.glassEffectID(_:in:)`. Still unbuilt and therefore still `(verify)`: `glassEffectUnion(id:namespace:)` and `.containerConcentric`. New SwiftUI APIs also churn across point releases, so re-check on SDK bumps.

**Mitigation.** M0 includes a **spike**: a throwaway `TabView` with a bottom accessory, a glass toolbar, and a `GlassEffectContainer`, built and run on device before any feature work. If a symbol doesn't exist or behaves differently, we learn it in hour one, not week three. Everything in 07–09 that depends on a specific API is annotated; treat the annotations as a checklist.

Do not trust the Simulator for glass. Refraction, blur, and the accent's dark-mode rendering must be judged on hardware.

### R5. iOS 27 minimum cuts your audience

**Likelihood: certain · Impact: strategic**

Liquid Glass does not backport. Targeting it means users on iOS 18 and earlier cannot install the app at all.

This is the highest-leverage decision in the plan and it is not a technical one. Supporting iOS 18 means either `if #available` forks on every chrome surface — two design systems maintained forever — or abandoning Liquid Glass, which was the premise of the rebuild.

**Mitigation.** None, really. It's a trade. My read: this is a cultural archive, not a growth product, and a clean single-path codebase is worth more than the tail of users on old iOS. **But say now if you disagree** — it changes [09](ios-rebuild-docs/09-DESIGN-SYSTEM.md) and roughly doubles the chrome work.

---

## Tier 2 — Will cost you time

### R6. Emulator on a physical device

**Likelihood: certain (everyone hits this once) · Impact: an afternoon**

`127.0.0.1` resolves to the phone, not your Mac. Firestore's emulator connection also needs `isSSLEnabled = false`, which is easy to forget and produces an opaque TLS failure.

**Mitigation.** `EMULATOR_HOST` as a scheme environment variable, defaulting to `127.0.0.1` for the Simulator and set to your Mac's LAN IP for device runs. Start the emulator with `--host 0.0.0.0`. Documented in the M0 runbook. (Note: the *web* repo's own seed script has this class of bug — it defaults `FIRESTORE_EMULATOR_HOST` to port **4000**, the Emulator UI, while printing "8080".)

### R7. Shipping a debug build against production Firebase

**Likelihood: moderate · Impact: severe — corrupted production data**

The emulator connection must happen after `FirebaseApp.configure()` and before the first `Firestore`/`Auth`/`Functions` use. If the `#if DEBUG` guard or the env-var check is wrong, a debug build writes to prod. If both `GoogleService-Info.plist` files land in the Copy Resources phase, a release build might read the dev one.

**Mitigation.** One plist per configuration, copied by a build phase keyed on `${CONFIGURATION}` — never both in the target. A loud `print` of the resolved `projectID` and emulator status on launch in DEBUG. A `#if DEBUG` assertion that a release configuration never calls `EmulatorConfig.connect()`. This is the most dangerous file in the project; treat it accordingly.

### R8. Rewriting `firestore.rules` is where the real security lives

**Likelihood: moderate · Impact: data breach**

The client is not the authority. Moving `isAdmin` from a Firestore field to a custom claim ([10 §4](ios-rebuild-docs/10-TECH-PLAN.md)) touches every admin rule. Switching to `serverTimestamp()` changes the `createdAt` assertions. Renaming `shared` → `attributed` changes the report enum. Every one of those is a chance to widen a rule by accident.

The existing `firestore.rules` is, genuinely, the best-engineered artifact in `abwaan-v2` — the exact-key-set check on reports (`hasOnly` **and** `hasAll`), the one-report-per-user `!exists()` guard, the pinning of `username`/`isAdmin`/`submissionCount` on profile updates. **Copy the paranoia, not just the shape.**

**Mitigation.** Rules unit tests with `@firebase/rules-unit-testing`, run against the emulator in CI, written *before* the Swift that depends on them. The web project has zero tests of any kind; this is the one place I'd insist on changing that.

### R9. Google Sign-In without Sign in with Apple

**Likelihood: low–moderate · Impact: one rejection, one appeal**

Guideline 4.8 requires that an app offering a third-party login also offer another option meeting privacy criteria. Email/password plausibly qualifies — I retracted my earlier claim that Apple was mandatory ([06](ios-rebuild-docs/06-OPEN-QUESTIONS.md)). But reviewers vary, and 4.8's criteria (limit collection to name and email; allow an undisclosed email address) are arguably not met by a plain email login, since the email is by definition disclosed to you.

**Mitigation — RETIRED 2026-07-10 (13 §D1).** Sign in with Apple ships in **M11**, filling the reserved third slot. The original blocker (no Developer account) resolves by definition before submission, and the work is roughly a day: `OAuthProvider("apple.com")`, a capability, a button. A day of work traded against a week-long rejection round. This risk drops off the table at M11.

### R10. `FirebaseFirestore` is heavy

**Likelihood: certain · Impact: build times and app size**

The Firestore pod pulls gRPC, abseil, BoringSSL, and leveldb. First clean SPM resolve and build is slow. Binary size grows meaningfully.

**Mitigation.** Accept it — there is no lighter path to Firestore. Import only `FirebaseAuth`, `FirebaseFirestore`, `FirebaseFunctions`; skip Analytics, Crashlytics, Messaging, Performance. Pin the version. Consider the prebuilt binary distribution **(verify it still exists)**. Do not add App Check *and* Analytics *and* Crashlytics "while we're in here."

---

## Tier 3 — Latent, inherited, or cheap to get wrong

### R11. Search will be mediocre, and the scope bar will make that visible

**Likelihood: certain · Impact: user perception**

Firestore is not a search engine. [10 §7](ios-rebuild-docs/10-TECH-PLAN.md) recommends Option 2 (scoped queries), which fixes the *lying* scope bar but not the underlying weakness: prefix-only matching, no stemming, no fuzzy, no relevance ranking, and a 60-token keyword cap.

The web hid this because its filter chips silently did nothing during search. Native search scopes are visible and users will trust them, which raises the bar.

**Mitigation.** Ship Option 2. Instrument it. If search is a top complaint, Option 3 (Typesense/Algolia) is a self-contained later milestone. Don't gold-plate v1.

### R12. `AVAudioSession` misconfiguration

**Likelihood: moderate · Impact: bad reviews, possible rejection**

Ambient audio that ignores the silent switch, ducks a user's podcast, or keeps playing in the background is how an app earns one-star reviews. The web version *autoplays on mount* — on iOS that ranges from "silently fails" to "hostile."

**Mitigation.** `AVAudioSession(.ambient, options: .mixWithOthers)`. `.ambient` respects the ringer switch and never interrupts other audio, which is exactly right for a 3%-volume texture. Off by default; the user opts in. No background mode, no `MPNowPlayingInfoCenter`, no lock-screen presence. Ship the audio pre-filtered rather than rebuilding the Web Audio low-pass graph.

**Or cut it.** It remains the single most "web" thing in the app (Q8). I kept it because `.tabViewBottomAccessory` gives it a legitimate native home, not because it's essential.

### R13. Universal Links need a domain that may no longer exist

**Likelihood: moderate · Impact: `ShareLink` produces dead links**

`ShareLink` on a submission should emit `https://abwaan.<tld>/s/{id}` and that URL must open the app — which requires an `apple-app-site-association` file served from the domain with the `applinks:` entitlement.

**But you are retiring the website.** If the domain lapses, every previously shared link dies and Universal Links stop resolving.

**Mitigation.** Keep the domain and keep Firebase Hosting serving *only* `/.well-known/apple-app-site-association` plus a minimal "get the app" landing page for `/s/:id`. That's a static file and a stub — near-zero cost, and it means shared poems still open something for people without the app. **Do not let the domain expire.** Confirm you still control it.

### R14. Dark mode is unbuilt, unreviewed design work

**Likelihood: certain · Impact: a design pass you haven't budgeted**

The web app is `bg-white` end to end. Liquid Glass adapts to what's behind it, and what's behind it is the user's chosen appearance. There is no "skip dark mode" option here.

The accent `#eb932e` is tuned for white and will vibrate on black. Its light-mode contrast is already ~2.3:1 **(verify)**, failing AA for text — the site quietly works around this by using the 600 stop for links without ever saying so.

**Mitigation.** Asset Catalog accent with explicit light and dark variants, chosen on hardware. `#eb932e` (500) tints fills only; `#db751b` (600) or a semantic label color for text. Audit at Increase Contrast. Budget a real design pass, not an afternoon.

### R15. Inherited logic bugs, if ported carelessly

**Likelihood: moderate · Impact: subtle, long-lived**

Six defects I confirmed in the web app. A fresh schema removes the excuse for carrying any of them, but a line-by-line port would reintroduce all six:

| Bug | Location |
|---|---|
| Editing a poem's title writes a stale `searchIndex` (`resolvedTitle` read at line 731, assigned at 740) | [functions/src/index.ts:731](functions/src/index.ts:731) |
| `reportCount` only increments — a restored submission re-hides on the next report | [functions/src/index.ts:272-306](functions/src/index.ts:272) |
| Public profile shows loaded-row count, not real count | [PublicProfilePage.vue:96](client/src/features/profile/PublicProfilePage.vue:96) |
| Admin report query passes `limit = 0` (falsy) and loads every report | [reports.store.ts:16](client/src/features/admin/reports.store.ts:16) |
| `createSubmission` writes `meaning: ""`; the update rule requires `meaning.size() >= 1` | [firestore.rules:164](firestore.rules:164) |
| Client validation accepts any 2–8 char `language`; server demands `so`/`en` | [submission.validation.ts:78-82](client/src/features/submissions/submission.validation.ts:78) |

**Mitigation.** Each is already addressed in [10 §4](ios-rebuild-docs/10-TECH-PLAN.md) or [10 §11](ios-rebuild-docs/10-TECH-PLAN.md). Listed here so they can be checked off rather than rediscovered.

### R16. `onSubmissionDelete` does not paginate

**Likelihood: low · Impact: a stuck function**

The delete trigger reads every doc in `votes`, `comments`, and `reports` into memory before `bulkWriter` removes them ([functions/src/index.ts:257-263](functions/src/index.ts:257)). It uses `.select()` to project to keys only, which is right, but there's no pagination. A submission with tens of thousands of votes or comments would risk a memory or timeout ceiling.

**Mitigation.** Paginate the subcollection reads. Cheap to do while porting; impossible to hit today at this app's scale, which is exactly why it'll be forgotten.

### R17. No App Check on a backend that just lost its only client

**Likelihood: moderate · Impact: abuse**

The four callables are reachable by anyone holding the public web API key. The only throttle is a **fixed-window** rate limiter, which permits up to `2 × maxCalls` across a window boundary. `usernames/{name}` is world-readable, so the full handle → UID mapping is enumerable.

**Mitigation.** App Check with DeviceCheck / App Attest is genuinely cheap on iOS and there is no longer a web client to also support. Recommended for v1. Consider a sliding-window or token-bucket limiter while rewriting the functions.

---

## Explicitly *not* risks

Worth naming, because they'd otherwise get worried about:

- **Data migration.** There is none. Fresh schema, fresh project, retired site.
- **Web/iOS schema drift.** Impossible. There is no web client.
- **XSS / sanitization.** `Text` renders no markup. `dompurify` and `sanitize.ts` cease to exist as a category of problem.
- **The `dompurify` / `vite-plugin-pwa` missing dependencies (Q2).** Moot — that build is being retired.
- **Push notification infrastructure.** Not building it ([10 §10](ios-rebuild-docs/10-TECH-PLAN.md)).
- **Cloud Storage rules.** Still deny-all. Still unused.
- **Vote hot-document contention** (13 §B4). Every vote is a transaction on the submission doc; Firestore sustains roughly 1 write/sec per document before contention. Irrelevant at this corpus's scale. Named here so nobody "fixes" it preemptively with sharded counters.
- **Profile counter drift.** Retired by design — the counters no longer exist (13 §A1); display counts come from `count()` aggregation. Q6 cannot recur.
- **The auth-trigger race and the emulator no-functions trap.** Retired by design — the trigger no longer exists (13 §A2); `bootstrapProfile` is deterministic and client-ordered.

---

## Summary

| # | Risk | Likelihood | Impact |
|---|---|---|---|
| R1 | No user blocking (Guideline 1.2) | Certain | **Rejection** |
| R2 | No account deletion (Guideline 5.1.1(v)) | Certain | **Rejection** |
| R3 | Swift 6 concurrency vs. Firebase | High | Days |
| R4 | Liquid Glass APIs unverified | High | Rework |
| R5 | iOS 27 minimum cuts audience | Certain | Strategic |
| R6 | Emulator on device | Certain | Hours |
| R7 | Debug build → prod Firebase | Moderate | **Severe** |
| R8 | Rules rewrite widens a permission | Moderate | **Breach** |
| R9 | 4.8 without Sign in with Apple | Low–mod | Rejection round |
| R10 | Firestore SDK weight | Certain | Build time, size |
| R11 | Search quality | Certain | Perception |
| R12 | `AVAudioSession` | Moderate | Reviews |
| R13 | Universal Links need the domain alive | Moderate | Dead share links |
| R14 | Dark mode is unbuilt | Certain | Design pass |
| R15 | Inherited logic bugs | Moderate | Subtle |
| R16 | `onSubmissionDelete` unpaginated | Low | Stuck function |
| R17 | No App Check | Moderate | Abuse |

**R1 and R2 are the ones that stop you at the door.** Everything else is engineering.
</content>
