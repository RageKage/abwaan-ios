# CLAUDE.md — Abwaan iOS

You are working on **Abwaan**, a native iOS app: an archive of Somali proverbs (Maahmaah)
and poetry (Gabay). This file is the operating contract. Read it fully before doing anything.
The `ios-rebuild-docs/` folder is the full plan; this file tells you how to use it.

---

## The one rule that overrides everything

**We build one milestone at a time, and I give the go-ahead before each one.**

Do not read ahead and start M3 work while we are on M2. Do not "helpfully" scaffold the next
milestone. When a milestone's exit condition is met, stop and tell me it's done — I decide when
the next one starts. If you think the milestone boundary is wrong, say so and wait; don't cross it.

The milestones are defined in `ios-rebuild-docs/12-ROADMAP.md` (M0–M11). That file's exit
condition — "Done when" — is the definition of finished. If I can't watch it happen on device
or in the emulator UI, it isn't done.

---

## How I work — non-negotiable process

- **Small batches. 3–5 files per prompt, maximum.** A large all-at-once change produces worse
  results and is hard to review. If a task needs more than ~5 files, propose the split and let me
  pick where to cut. This is learned discipline, not a preference — a big batch has already burned
  me once on another project.
- **I handle all git.** You never run `git add`, `commit`, `push`, `branch`, `checkout`, or
  anything that mutates history. Write the code; I commit between batches. If a change wants a
  commit, say "good commit point here" and stop.
- **Ask before drafting when scope is ambiguous.** One focused question beats a wrong 400-line
  guess. I dislike padded output and scattered parallel threads — do one category at a time.
- **Tell me the truth.** If a doc is wrong, an API doesn't exist, or an approach won't work, say
  so plainly. Don't soften it and don't pretend a `(verify)` item is confirmed when you haven't run it.

---

## What's frozen, and what's reference

| Doc | Status | Use it for |
|---|---|---|
| `10-TECH-PLAN.md` §4 | **FROZEN SCHEMA.** Signed. | The exact data model. Do not redesign it. If it needs a change, that's a conversation, not an edit. |
| `13-REVIEW-AND-REVISIONS.md` | **Decision record.** | Why the schema/architecture is what it is. Every A/B/C/D item here is an accepted decision, not a proposal. |
| `12-ROADMAP.md` | **The plan of record.** | Milestone order, includes, and exit conditions. |
| `06-OPEN-QUESTIONS.md` | Decisions taken | What's resolved and what (one item: launch content) is still open. |
| `07`, `08`, `09` | Design intent | UI translation, navigation shape, design system. Follow these for anything user-facing. |
| `11-RISKS.md` | Known traps | Read the relevant risk before the milestone it warns about (esp. R7 debug→prod, R8 rules). |
| `01`–`05` | **Historical only.** | Phase 0 audit of the *retired web app*. Behaviour spec, not storage spec. Never port its code, its epoch-ms timestamps, or its bugs. When it conflicts with `10 §4`, `10 §4` wins. |

If two docs disagree: **10 §4 for schema, 12 for sequence, 13 for rationale.** Everything else yields to those three.

---

## Architecture — the shape you must hold

Full detail in `10-TECH-PLAN.md §2`. The load-bearing parts:

- **SwiftUI-first. `@Observable`, not `ObservableObject`. No ViewModel-per-view.**
- **One `SubmissionStore`** (`@MainActor @Observable`, `[String: Submission]`) is the single source
  of truth for submission values. Feature models (`ArchiveModel`, `DeskModel`, …) hold **ordered ID
  arrays + cursors**, never copies of submissions. Rows read through the store. This is deliberate —
  it kills the web's list-vs-detail divergence bug at the root. Do not reintroduce per-feature copies.
- **Repository protocol + Firestore impl + in-memory fake.** No Firebase type crosses out of the
  repository layer. Map `DocumentSnapshot` → `Sendable` value type at the boundary. This is what
  makes previews and tests possible, and it's the answer to Swift 6 concurrency (R3).
- **`LoadState` has four cases** — `idle / loading / loaded(Value) / failed`. `.empty` is derived at
  the view from `loaded([])`, never stored.
- **Callables vs direct writes is decided, not open** (`10 §4`, write-surface map). Comments,
  favorites, report-create, profile name/bio, `blockedUids`, and submission-delete are direct
  client writes (they queue offline). Everything else is a callable (fails offline, gets disabled
  via `NWPathMonitor`). Don't move an action across that line without asking.

---

## Backend lives in this repo

`firebase/` holds `firestore.rules`, `firestore.indexes.json`, `firebase.json`, and `functions/`.
The website is retired; this app owns the backend now.

- **Rules are the only real security.** The client is not the authority. When you touch a rule,
  a rules unit test (`@firebase/rules-unit-testing`) proves it — including the negative case. Copy
  the web rules' paranoia (exact-key-set checks, `!exists()` guards, pinned immutable fields); see R8.
- Functions are **v2 only.** No v1 anywhere. There is no auth `onCreate` — profile creation is the
  `bootstrapProfile` callable (13 §A2).
- **The most dangerous file in the project** is the Firebase bootstrap (`10 §3`). Emulator config
  must run after `FirebaseApp.configure()` and before the first Firestore/Auth/Functions use, behind
  `#if DEBUG` + an env check. Get it wrong and a debug build writes to prod (R7). Treat it accordingly.

---

## Environment

- **iOS 27.0 minimum.** Liquid Glass is the premise; it does not backport. No `if #available` forks.
- **Debug scheme talks to the emulator** (`USE_FIREBASE_EMULATOR=1`). Never point a debug build at prod.
- On a physical device, `127.0.0.1` is the phone, not the Mac — `EMULATOR_HOST` = the Mac's LAN IP,
  emulator bound to `0.0.0.0`, `isSSLEnabled = false` (R6). This bites once; it's documented.
- SPM only. Two runtime deps: `firebase-ios-sdk` (Auth, Firestore, Functions — nothing else) and
  `GoogleSignIn-iOS`. Don't add packages "while we're in here."
- Swift 6 language mode, strict concurrency. If it becomes a tarpit, we drop to targeted — ask first.

---

## Design guardrails (anything user-facing)

- **Glass is for chrome, opaque is for reading.** Tab bars, toolbars, sheets, the audio accessory:
  glass. Any surface showing a poem, proverb, meaning, translation, or comment body: opaque
  `Color(.systemBackground)`. This is the one aesthetic line that never bends. (`07 §0`, `09 §6`)
- **New York serif for content**, SF Pro for chrome. Dynamic Type everywhere — no fixed point sizes.
- **Dark mode from the first screen**, not bolted on. Accent `#eb932e` for fills only; `#db751b`
  (or a semantic label color) for text. Accent needs a dark-mode asset variant.
- **Every user-facing string goes through the String Catalog** from day one — even though we ship
  English-only. This keeps a Somali UI a translation task later, not a refactor. (`13 §C3`)
- Prefer system behaviour over reimplementing it. The whole point of the rebuild is *less* code by
  not rebuilding the platform. If you're about to hand-roll something SwiftUI already does, stop.

---

## Bugs from the web app — do not port these

A line-by-line port reintroduces all of them. Each is already fixed in the plan (`11 R15`, `13`):

- Stale `searchIndex` on poem-title edit (`resolvedTitle` read before assignment).
- `reportCount` that only increments — use `openReportCount` that decrements on resolution.
- Public-profile count that shows loaded rows, not real count — use `count()` aggregation.
- Admin report query passing `limit = 0` and loading everything — paginate.
- `createSubmission` writing `meaning: ""` against a rule demanding `size() >= 1`.
- Client accepting any `language`; server demanding `so`/`en`. Validation mirrors the callable **exactly.**

---

## When you start a milestone

1. Re-read that milestone in `12-ROADMAP.md` — Goal, Includes, Done-when, Depends-on, Your-input.
2. Read the docs it cites and the matching risk in `11`.
3. If anything I owe you (a decision, a file, the Xcode shell) is missing, ask for it first.
4. Propose the file batch (≤5) before writing. I confirm, you build, I commit, we go again.
5. When Done-when is demonstrably met, stop and tell me. Don't start the next one.

---

## Note on M0

M0 (Xcode project shell, schemes, plists, the Liquid Glass hardware spike) is mostly **my** work —
you can't produce an `.xcodeproj` I'd want to inherit. Once the shell exists and the emulator runs,
we begin real work at **M1: schema, rules, models, seeder**. That's the first milestone where you
write code. The schema is already frozen (`10 §4`), so M1 is unblocked the moment the project exists.
