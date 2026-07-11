# 12 — Build Roadmap

> Phase 3. Milestone-based. Every milestone ends in something you can **run on a device against the emulator and see working** — no milestone is "wiring you can't demo."
>
> **Revised 2026-07-10** per [13-REVIEW-AND-REVISIONS.md](ios-rebuild-docs/13-REVIEW-AND-REVISIONS.md). No milestone added; M1 and M2 got slightly heavier (the right place for weight), Sign in with Apple and the share card joined M11 and M3, and the schema revisions in [10 §4](ios-rebuild-docs/10-TECH-PLAN.md) are now the signed baseline.
>
> **This is the last planning document.** Per the ground rules: no Swift gets written until you approve this roadmap, and then we do it **one milestone at a time**, each with its own go-ahead.

## How to read this

Each milestone has:
- **Goal** — one sentence.
- **Includes** — what gets built.
- **Done when** — the demoable, testable exit condition. If you can't watch it happen, it's not done.
- **Depends on** — hard prerequisites.
- **Your input** — anything I need from you *before* or *during* it.

Milestones are ordered so each one stands on the last and produces a running app. You could stop after almost any of them and have something real.

Rough sequence: **M0 → M1 → M2 → M3 → M4 → M5 → M6 → M7 → M8 → M9 → M10 → M11**. The two App Store gates (blocking, account deletion) are M8 and M9 — early enough to not be a scramble, late enough that the app exists to attach them to.

---

## M0 — Foundation and the Liquid Glass spike

**Goal.** An empty app launches on your device with a glass tab bar, connected to the emulator, and I've proven the Liquid Glass APIs actually exist.

**Includes.**
- You create the Xcode project (File → New → App, SwiftUI, Swift Testing). I take it from there.
- Repo scaffold at `~/Desktop/Hub/Dev/abwaan-ios` per [10 §1](ios-rebuild-docs/10-TECH-PLAN.md), git init, Xcode `.gitignore`.
- SPM: `firebase-ios-sdk`, `GoogleSignIn-iOS`, pinned.
- The `firebase/` backend directory: move `firestore.rules`, `firestore.indexes.json`, and the functions from `abwaan-v2`; add the missing `functions` emulator block; drop the unused `database`/`storage` emulator blocks.
- Three schemes (Debug/emulator, Staging, Release) + two `GoogleService-Info.plist` files + the configuration-keyed copy build phase. The dangerous plumbing from [10 §3](ios-rebuild-docs/10-TECH-PLAN.md), done once, carefully.
- **The spike (R4).** A throwaway `TabView` with four tabs, `.tabBarMinimizeBehavior(.onScrollDown)`, a `.tabViewBottomAccessory`, a glass toolbar button, and a `GlassEffectContainer` — built and run **on hardware**. Every API marked **(verify)** in 09/10 gets confirmed or corrected here, in hour one.

**Done when.** The app launches on your physical phone, shows a four-tab glass bar that minimizes on scroll, and a debug launch prints `projectID` + "EMULATOR: connected". A `print` from a trivial Firestore read against the emulator appears in the console. The spike either validated the glass APIs or produced a corrected list.

**Depends on.** You having a current Xcode with the iOS 27 SDK; a Firebase dev project (`abwaan-dev`) existing; the emulator running locally.

**Your input.**
- Create the Xcode project shell.
- Confirm `abwaan-dev` exists (or make it) and hand me its `GoogleService-Info.plist`.
- **Do you still control the domain?** (R13 — needed later, but flag now.)

---

## M1 — Schema, models, rules, and a seeded emulator

**Goal.** The new data model exists in Firestore emulator form, the rules enforce it, and Swift value types round-trip against it. No UI yet.

**Includes.**
- **Schema v2 is signed** — the revised [10 §4](ios-rebuild-docs/10-TECH-PLAN.md) (13 §A1-A10): no profile counters, no `lastSeenAt`, no `uid` in `usernames`, `blockedUids` array on `privateUsers`, `openReportCount` with a real decrement path.
- **`bootstrapProfile` callable** replaces the auth trigger (13 §A2). The functions codebase is v2-only from day one.
- `firestore.rules` rewritten for v2: `isAdmin` → custom claim, `serverTimestamp()` assertions, `attributed` enum, the `meaning` fix, **the username-gate assertion on comment/report create (13 §A8)**, and submissions callable-write-only except delete (13 §A4) — copying the web rules' paranoia ([11 R8](ios-rebuild-docs/11-RISKS.md)).
- `firestore.indexes.json` for v2, including the scoped-search indexes ([10 §7](ios-rebuild-docs/10-TECH-PLAN.md)).
- `Codable`/`Sendable` Swift models: `Submission`, `Profile`, `Comment`, `Report`, `Vote`, `Favorite`.
- Repository protocols + Firestore implementations + in-memory fakes.
- A **new seeder** (the web one has the port-4000 bug and duplicates search logic — [11 R6](ios-rebuild-docs/11-RISKS.md)) that loads sample proverbs and poems into the emulator.
- Rules unit tests (`@firebase/rules-unit-testing`) in CI. The web app had zero tests; this is where that changes.
- Swift Testing: model round-trips and validation, against fakes.

**Done when.** `firebase emulators:start` + seeder gives a populated Firestore; the Emulator UI shows correctly-shaped documents; rules tests pass (including negative cases — a non-admin cannot hide a submission, a user cannot claim a taken username); Swift tests decode every seeded document without loss.

**Depends on.** M0.

**Your input.** ~~Revise the schema~~ — **done 2026-07-10**; [10 §4](ios-rebuild-docs/10-TECH-PLAN.md) as revised is the frozen model. M1 is now unblocked on you entirely (beyond the M0 asks).

---

## M2 — Archive: read-only browsing

**Goal.** Launch into a real, scrolling, filterable list of poetry pulled from the emulator. Guest mode. This is the first milestone that *looks like the app*.

**Includes.**
- **`SubmissionStore`** — the normalized `[String: Submission]` cache; lists hold ID arrays (13 §C1). Built here because the architecture is set here; retrofitting later is the expensive path.
- Archive tab: `List` of `SubmissionRow`, opaque rows, serif headlines ([09 §1](ios-rebuild-docs/09-DESIGN-SYSTEM.md)), rows reading through the store.
- Cursor pagination, infinite scroll via `.task` on the last row.
- Filter `Menu` (type, language, sort) in the glass toolbar.
- `LoadState` handling (four cases, `.empty` derived — 13 §C2): `.redacted` skeletons, `ContentUnavailableView` for empty/error.
- **String Catalog from the first screen** (13 §C3): every user-facing string, no exceptions, English-only content.
- Design system foundations: `Theme`, semantic colors, the Asset Catalog accent with **light + dark variants** ([09 §2](ios-rebuild-docs/09-DESIGN-SYSTEM.md)), New York serif for content.
- **Dark mode from the first screen**, not bolted on later (R14).

**Done when.** On device, you scroll a paginated archive of seeded submissions, change type/language/sort and watch the list re-query, see skeletons then content, and toggle system dark mode with everything remaining legible. All as a signed-out guest.

**Depends on.** M1.

**Your input.** Eyeball the serif rendering and the accent in both appearances, on hardware.

---

## M3 — Detail and reading

**Goal.** Tap a row, read the full piece, with the chrome-not-content glass discipline in place.

**Includes.**
- `SubmissionDetail`: type-dependent layout (Proverb headline vs. Poetry title + verse block), optional meaning / translation / source sections, all opaque.
- Author row → pushes `PublicProfile` (read-only for now).
- Bottom glass toolbar **shell** — vote/save/share/comments laid out, not yet wired (that's M5–M6). `ShareLink` works now.
- **Share-as-image quote card** (13 §D2): `ImageRenderer` renders the detail typography into an image attached to the `ShareLink` alongside the URL. Built here because the typography it renders is built here.
- Comment count via `count()` aggregation on appear (13 §A3) — the toolbar number is honest before the sheet ever opens.
- `PublicProfile`: header + that author's published works, with the **fixed** contribution count (R15).
- `NavigationPath` + `Route` enum; Universal Link plumbing so `/s/:id` resolves ([08 §5](ios-rebuild-docs/08-NAVIGATION-ARCHITECTURE.md)).

**Done when.** From the archive you push into a submission, read it, tap the author to see their profile, share a link via the system sheet, and navigate the whole stack with correct back behaviour — still fully signed out.

**Depends on.** M2.

---

## M4 — Auth and the username gate

**Goal.** Sign in, sign up, claim a handle. The three-state session machine works.

**Includes.**
- `SessionModel` state machine ([10 §2](ios-rebuild-docs/10-TECH-PLAN.md)): loading → signedOut → needsUsername → active.
- **`PendingAction`** on `SessionModel` (13 §B1): the guest-tapped action is stored before `AuthSheet` presents and replayed on the transition into `.active` — so it survives the onboarding cover, not just the sheet.
- `AuthSheet` (`.medium`): email/password, Google (native `GoogleSignIn` flow), the Apple slot (filled at M11).
- `UsernameOnboarding` as a non-dismissible `.fullScreenCover`, with **live availability checking** against the world-readable `usernames` collection.
- `claimUsername` callable wired.
- **`bootstrapProfile` wired client-side** (13 §A2): sign-in → no profile → callable → snapshot → `needsUsername`. No trigger, no race, works in the emulator regardless of which emulators run.
- Settings tab skeleton: profile display, Sign Out.

**Done when.** On device against the emulator: register with email → forced onto onboarding → claim a handle with real-time "taken/available" feedback → land in the app as an active user; sign out; sign back in and skip straight past onboarding; Google sign-in produces the same flow.

**Depends on.** M3 (needs the profile screen to land on), M1 (needs the trigger + rules).

**Your input.** A decision on avatars ([07 §1.7](ios-rebuild-docs/07-DESIGN-TRANSLATION.md)): render `photoURL`, or drop it? Default is render.

---

## M5 — Contribute and edit

**Goal.** Authenticated users create and edit submissions through the callables.

**Includes.**
- `ContributeForm` as `.fullScreenCover`: `Form` sections, conditional title (Poetry), conditional source (attributed), `Picker`s.
- `SubmissionDraft` validation mirroring the server callable **exactly** — no drift ([11 R15](ios-rebuild-docs/11-RISKS.md)).
- `createSubmission` + `updateSubmission` callables wired. **Port the fixed `updateSubmission`, not the stale-`searchIndex` bug** (R15).
- Edit mode as a full-screen cover from the detail overflow menu; save disabled until valid *and* changed.

**Done when.** On device: compose a proverb and a poem, watch validation gate the Post button, publish, land on the new detail screen, edit it, and see the change persist — all against the emulator, with the Desk count (a `count()` aggregation — no trigger, 13 §A1) reflecting the new entry.

**Depends on.** M4.

---

## M6 — Engagement: vote, favorite, comment

**Goal.** The bottom toolbar comes alive, and comments work in a sheet.

**Includes.**
- `VoteControl` wired to `voteSubmission`, optimistic with rollback + `.sensoryFeedback` ([10 §5](ios-rebuild-docs/10-TECH-PLAN.md)).
- Favorites: toolbar button + **swipe-to-save** on rows + swipe-to-unsave in Desk. `privateUsers/{uid}/favorites`. **Orphan hygiene** (13 §B3): when hydration finds a deleted submission, the favorite doc is deleted opportunistically — no permanent orphans.
- Comments in a `.sheet` with detents; lazy-loaded on open (a read-cost win over the web); glass composer; swipe-to-delete.
- Guest taps on any of these → `AuthSheet`, and **the pending action completes after sign-in** ([08 §4](ios-rebuild-docs/08-NAVIGATION-ARCHITECTURE.md)).

**Done when.** On device: upvote and watch the count move then persist; kill the network and watch a vote roll back with haptic feedback; save a poem by swiping; open comments, post one, swipe it away; as a guest, tap vote → sign in → the vote lands without losing your place.

**Depends on.** M5.

---

## M7 — Desk

**Goal.** The personal workspace tab: your works and your collection.

**Includes.**
- Desk tab: segmented Works / Collection.
- Works: own submissions incl. hidden (badged); Collection: favorites with swipe-to-unsave.
- Inline `SignInPrompt` when signed out (not a wall).
- `+` compose entry from the Desk toolbar.

**Done when.** On device: your published and hidden submissions appear under Works with hidden badges; saved items appear under Collection; unswipe removes one; signed-out shows the inline prompt, not a lockout.

**Depends on.** M6.

---

## M8 — Blocking *(App Store gate — Guideline 1.2)*

**Goal.** Users can block abusive users, and blocked content disappears. **This is a ship-blocker, built early on purpose.**

**Includes.**
- `blockedUids: [String]` on `privateUsers/{uid}`, rule-capped at 500 (13 §A7) — one field, zero extra queries, arrives with a doc the session already reads.
- "Block this user" in submission and comment overflow menus.
- Client-side filtering of blocked users' submissions and comments across archive, search, detail, and profile ([11 R1](ios-rebuild-docs/11-RISKS.md)), with the **pagination refill loop** (filtering shrinks pages; keep fetching until a page fills or the cursor exhausts — 13 §A7).
- A "Blocked users" management list in Settings (unblock).
- Published contact info as a Settings row (the web's footer `mailto:`, relocated).

**Done when.** On device: block a user, and their submissions vanish from the archive and their comments from every thread; unblock from Settings and they return; the contact row is present.

**Depends on.** M6 (comments/profiles must exist to block).

**Your input.** The contact email to publish.

---

## M9 — Account deletion *(App Store gate — Guideline 5.1.1(v))*

**Goal.** In-app account deletion that tombstones the poetry and purges the person.

**Includes.**
- `Delete Account` in Settings: destructive, double-confirmed, re-auth first (`reauthenticateWithCredential`).
- `onProfileDelete` / callable: purge `profiles`, `privateUsers` + favorites, release `usernames/{lower}`, delete the Auth user; **reassign** submissions and comments to a deleted-user sentinel with `authorUid`/`authorUsername` stripped ([06 resolved](ios-rebuild-docs/06-OPEN-QUESTIONS.md)).

**Done when.** On device against the emulator: delete your account; your profile, favorites, and handle are gone and the handle is immediately re-claimable; your poems remain in the archive attributed to a deleted-user sentinel; you're signed out.

**Depends on.** M4.

---

## M10 — Moderation and App Check

**Goal.** Admins moderate; the callables are attested.

**Includes.**
- `ModerationQueue` pushed from a role-gated Settings section (not a tab): Submissions (hide/restore) and Reports (dismiss/resolve), segmented, with swipe actions and **paginated** report loading (fixes the `limit = 0` bug — R15).
- Reporting: the report `.sheet` wired to the reports subcollection (direct write — it queues offline).
- **`setSubmissionStatus` + `resolveReport` callables** (13 §A4): hide/restore and resolution leave the client-write path; `resolveReport` transactionally decrements `openReportCount`. Restore semantics: auto-hide only re-fires at 3 *open* reports (Q9 closed by design).
- `onReportCreate` auto-hide trigger.
- `isAdmin` as a **custom claim**; `setAdminClaim` script.
- **App Check** (DeviceCheck / App Attest) on **all callables** — now eight of them ([11 R17](ios-rebuild-docs/11-RISKS.md)).
- Admin scope: hide/restore only, per your Phase-1 default (Q14).

**Done when.** On device with an admin account (claim set via the script): report a submission three times and watch it auto-hide; restore it from the queue; resolve a report and see the open count drop; confirm a non-admin sees no Moderation section; callables reject un-attested requests.

**Depends on.** M6 (reporting), M4 (roles).

---

## M11 — Search, ambient audio, and ship prep

**Goal.** The last real feature, the last bit of chrome, and everything App Store Connect asks for.

**Includes.**
- Search tab (`role: .search`): `.searchable`, scopes (All/Proverbs/Poetry) that **actually filter** (Option 2, R11), debounced, tokenized query, **apostrophe-normalized on both sides** (13 §A9).
- **Sign in with Apple** (13 §D1): the reserved slot gets filled. Roughly a day; retires R9.
- Ambient audio in `.tabViewBottomAccessory`: opt-in, `AVAudioSession(.ambient, .mixWithOthers)`, no autoplay, pre-filtered asset (R12).
- `NWPathMonitor` connectivity → disable callable-backed actions offline with a legible reason ([10 §6](ios-rebuild-docs/10-TECH-PLAN.md)).
- Settings finish: About + Roadmap content, version, EULA/terms link.
- `PrivacyInfo.xcprivacy`, App Privacy label, encryption-export flag ([10 §12](ios-rebuild-docs/10-TECH-PLAN.md)).
- App icon (Liquid Glass layered treatment — verify `Abwaan_4.svg` scales).
- Universal Links end-to-end: `apple-app-site-association` served from the retained domain (R13).

**Done when.** On device: search "caqli", switch to the Proverbs scope, and results narrow honestly; toggle ambient audio on and confirm it ducks to a podcast and obeys the ringer switch; go offline and watch vote/compose disable with an explanation while reading still works; a shared `/s/:id` link cold-launches into the right submission. TestFlight build uploads clean.

**Depends on.** Everything.

**Your input.** EULA/terms text or a link; confirm the domain is live for the association file; **the launch-content answer (13 §B2)** — a fresh schema means an empty archive on day one, and an archive app with nothing in it is dead on first open. Either a production import script (Admin SDK, reusing the M1 seeder against prod, attributed to an official account) or a pre-launch contribution period. This is the one open item left from the review pass, and it runs in parallel to M11 with you as owner.

---

## Dependency graph

```
M0 foundation + glass spike
      │
M1 schema* + rules + models + seeder        ← *you revise the schema here
      │
M2 archive (read, guest)
      │
M3 detail + profile + deep links
      │
M4 auth + username gate ───────────────┐
      │                                 │
M5 contribute + edit                    M9 account deletion (gate)
      │
M6 vote + favorite + comment ──────────┐
      │                                 │
M7 desk                                 M8 blocking (gate)
      │                                 │
M10 moderation + App Check ←────────────┘
      │
M11 search + audio + ship prep
```

M8 and M9 branch off as soon as their prerequisites exist, so the two App Store gates can be built in parallel with the main line rather than discovered at the end.

## What "done with the roadmap" means

After M11 you have a shippable TestFlight build: guest browsing, auth with a mandatory handle (email, Google, **and Apple**), contribute/edit, vote/favorite/comment, share-as-image quote cards, personal desk, user blocking, account deletion, admin moderation, App Check, honest scoped search, ambient audio, dark mode throughout, and the two App Store gates cleared.

Not in v1, by decision: iPad, push notifications, avatar upload, Option 3 search (Algolia/Typesense), translated UI (the String Catalog plumbing ships in v1; the Somali strings do not), the daily-proverb widget (13 §D3 — v1.5). Each is a clean later addition, none is a prerequisite.

---

## The checkpoint

This is the end of planning. Twelve documents, no code, the website untouched.

**Nothing gets built until you approve this roadmap.** When you do, we start at **M0**, and I'll bring you the result of each milestone before starting the next — one at a time, as agreed. The first thing M0 needs from you is the Xcode project shell and confirmation that `abwaan-dev` exists.
</content>
