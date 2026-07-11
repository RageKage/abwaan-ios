# 10 — Technical Plan

> Phase 2. Still no code. Anything marked **(verify)** must be checked against the SDK you install — I could not compile against it.
>
> **Revised 2026-07-10** per [13-REVIEW-AND-REVISIONS.md](ios-rebuild-docs/13-REVIEW-AND-REVISIONS.md): counters → aggregation queries, auth trigger → `bootstrapProfile`, admin actions → callables, blocking → array, plus the `SubmissionStore` cache. §4 is now the **signed schema** for M1.

## 0. Assumptions I am proceeding on

Recorded so you can correct them cheaply.

| Assumption | Source |
|---|---|
| All 26 items in [07 §3](ios-rebuild-docs/07-DESIGN-TRANSLATION.md) are accepted | You approved Phase 1 with no vetoes |
| Separate repo at `~/Desktop/Hub/Dev/abwaan-ios` | Your answer |
| Fresh Firestore schema; the site is retired | Your answer |
| Sign in with Apple **added at M11** (Developer account exists by then) | Review pass (13 §D1) — supersedes Q1 |
| Share-as-image quote card in v1 | Review pass (13 §D2) |
| Dot pattern: **cut** | Default; reversible |
| Ambient audio: **kept**, in `.tabViewBottomAccessory`, opt-in | Default; reversible |
| Admin powers: **hide/restore only**, matching the web UI | Default; the backend permits more (Q14) |
| iPad: **out of scope** for v1 | Default |
| Search: **Option 2** — scoped Firestore queries | See §7 |

---

## 1. Project setup

### Repository

```
~/Desktop/Hub/Dev/abwaan-ios/          ← new git repo, independent of abwaan-v2
├── Abwaan.xcodeproj
├── Abwaan/
│   ├── App/                  AbwaanApp.swift, RootView, AppEnvironment
│   ├── Features/
│   │   ├── Archive/          ArchiveList, SubmissionRow
│   │   ├── Detail/           SubmissionDetail, VoteControl, CommentsSheet
│   │   ├── Compose/          ContributeForm, EditForm, SubmissionDraft
│   │   ├── Desk/             DeskView
│   │   ├── Search/           SearchResults
│   │   ├── Settings/         SettingsView, AboutView, RoadmapView
│   │   ├── Auth/             AuthSheet, UsernameOnboarding, SignInPrompt
│   │   ├── Profile/          PublicProfile, AvatarView
│   │   └── Moderation/       ModerationQueue
│   ├── Data/
│   │   ├── Models/           Submission, Profile, Comment, Report, Vote
│   │   ├── Repositories/     SubmissionRepository, ProfileRepository, …
│   │   ├── Functions/        CallableClient
│   │   └── Firebase/         FirebaseBootstrap, EmulatorConfig
│   ├── DesignSystem/         Theme, GlassStyles, SFSymbol+Abwaan
│   ├── Shared/               LoadState, Paginated, ContentUnavailable helpers
│   └── Resources/            Assets.xcassets, ambient.m4a, PrivacyInfo.xcprivacy
├── AbwaanTests/
├── AbwaanUITests/
├── firebase/                 ← rules + indexes + functions now live HERE
│   ├── firestore.rules
│   ├── firestore.indexes.json
│   ├── firebase.json
│   └── functions/
└── .gitignore                ← Xcode: DerivedData, xcuserdata, *.xcuserstate
```

**The backend moves into the iOS repo.** With the website retired, nothing else owns `firestore.rules` or the Cloud Functions. They are now the iOS app's backend, and they belong in its repo where they version together with the client that depends on them. `abwaan-v2` becomes an archive.

### Creating the Xcode project

I cannot generate an `.xcodeproj` from the terminal in any form you'd want to inherit — it's a bundle Xcode's template system produces, and hand-writing `project.pbxproj` is a bad trade. **You run File → New → Project (iOS → App, SwiftUI, Swift, Testing System: Swift Testing), I work inside the result.** That's the first thing M0 asks of you.

### Deployment target

**iOS 27.0.** This is a real cost and I want it stated rather than buried.

Liquid Glass — `glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`, `Tab(role: .search)`, `.tabViewBottomAccessory`, `.tabBarMinimizeBehavior`, `.scrollEdgeEffectStyle` — is the premise of this rebuild. It does not backport. Supporting iOS 18 means either `if #available` forks on every chrome surface (two design systems, permanently) or no Liquid Glass (in which case, why rebuild).

Given that this is a passion archive rather than a growth product, and that its users skew toward people who will update, I'd take the clean single-path codebase. **But it is your call, and it is the highest-leverage decision in this document.** If you need broader reach, say so now — it changes 09 and it doubles the chrome work.

Swift 6 language mode, strict concurrency. See [11-RISKS.md](ios-rebuild-docs/11-RISKS.md) R3.

### Dependencies — SPM only, no CocoaPods

| Package | Products | Why |
|---|---|---|
| `firebase-ios-sdk` | `FirebaseAuth`, `FirebaseFirestore`, `FirebaseFunctions` | Pin to a major version. **Not** `FirebaseFirestoreSwift` — it was folded into `FirebaseFirestore` **(verify)** |
| `GoogleSignIn-iOS` | `GoogleSignIn`, `GoogleSignInSwift` | Firebase Auth's Google provider needs the native SDK; there is no `signInWithPopup` on iOS |

That's it. Two dependencies. Compare to the web's 21 direct dependencies, of which one (`aos`) was unused and two (`dompurify`, `vite-plugin-pwa`) weren't even declared.

`FirebaseFirestore` drags in gRPC and abseil. First clean build is slow and the binary is not small. Budgeted in [11-RISKS.md](ios-rebuild-docs/11-RISKS.md) R4.

---

## 2. Architecture

**SwiftUI-first. `@Observable`, not `ObservableObject`. No ViewModel per view.**

The web app has seven Pinia stores, and they map almost one-to-one onto `@Observable` model classes. Resist the urge to add a `SubmissionDetailViewModel` — SwiftUI views *are* the view model layer, and a struct with `@State` and a repository call is usually enough.

```
View  ──reads──▶  @Observable model  ──calls──▶  Repository  ──▶  Firestore / Callable
 │                       ▲                            │
 └──sends intent─────────┘                            └── Codable structs, Sendable
```

| Layer | Rule |
|---|---|
| **Models** (`Data/Models`) | `Codable`, `Sendable`, `Hashable` value types. No Firebase types leak past the repository. |
| **Repositories** (`Data/Repositories`) | `protocol` + a Firestore implementation + an in-memory fake for tests and previews. `async throws`. This is what makes previews and tests possible at all. |
| **Observable models** | `@MainActor @Observable final class`. One per feature area, mirroring the Pinia stores: `SessionModel`, `ArchiveModel`, `DeskModel`, `ModerationModel` — all reading through one shared `SubmissionStore`. |
| **`SubmissionStore`** (13 §C1) | The single source of truth for submission values: `@MainActor @Observable` holding `[String: Submission]`. Feature models hold **ordered ID arrays plus cursors**, never submission copies. A vote mutates one dictionary entry and every list showing that submission updates for free. Optimistic vote/rollback is written once, here, not once per feature model. This closes the web's list-vs-detail divergence bug class at the root. |
| **Injection** | `@Environment` with a `AppEnvironment` struct holding repositories. Swap for fakes in `#Preview`. |
| **Concurrency** | `@MainActor` on models. Repositories are `actor`s or plain `Sendable` structs. |

### Session state

The one piece of genuinely global state.

```swift
@MainActor @Observable final class SessionModel {
    enum State {
        case loading                                   // before first auth callback
        case signedOut
        case needsUsername(uid: String)                // hard gate
        case active(uid: String, profile: Profile, isAdmin: Bool)
    }
    private(set) var state: State = .loading
}
```

Driven by `Auth.addStateDidChangeListener` plus a profile `addSnapshotListener`. `RootView` switches on `state` to decide whether to present the onboarding cover.

**`waitForAuthReady()` has no analogue and needs none.** The web blocked every route transition on a promise because `beforeEach` had to make a synchronous redirect decision. SwiftUI renders `.loading` → `.signedOut` → `.active` as the state settles. No splash, no promise, no 400 ms floor.

---

## 3. Firebase setup

### Bootstrap order matters

Emulator configuration must happen **after** `FirebaseApp.configure()` and **before** any `Firestore`/`Auth`/`Functions` instance is used. Get this wrong and you get a live production write from a debug build. This is the single most dangerous line of code in the project.

```swift
@main struct AbwaanApp: App {
    init() {
        FirebaseApp.configure()
        #if DEBUG
        if ProcessInfo.processInfo.environment["USE_FIREBASE_EMULATOR"] == "1" {
            EmulatorConfig.connect()
        }
        #endif
    }
}
```

`EmulatorConfig.connect()`:

```swift
let host = ProcessInfo.processInfo.environment["EMULATOR_HOST"] ?? "127.0.0.1"

Auth.auth().useEmulator(withHost: host, port: 9099)
Functions.functions().useEmulator(withHost: host, port: 5001)

let settings = Firestore.firestore().settings
settings.host = "\(host):8080"
settings.isSSLEnabled = false
settings.cacheSettings = MemoryCacheSettings()   // emulator data is ephemeral
Firestore.firestore().settings = settings
```

### Schemes

| Scheme | Config | Firebase project | Emulator |
|---|---|---|---|
| `Abwaan (Debug)` | Debug | `abwaan-dev` | **Yes** — `USE_FIREBASE_EMULATOR=1` in the scheme's env vars |
| `Abwaan (Staging)` | Release | `abwaan-dev` | No — real dev project |
| `Abwaan (Release)` | Release | `abwaan-prod` | No |

Two `GoogleService-Info.plist` files, in `Config/Debug/` and `Config/Release/`, copied by a build phase based on `${CONFIGURATION}`. Never both in the target's Copy Resources phase — that's how you ship a debug plist to the App Store.

**`127.0.0.1` works on the Simulator and fails on a physical device.** On device, `EMULATOR_HOST` must be your Mac's LAN IP, and the emulator must bind `0.0.0.0`. The debug scheme reads it from an env var so you can flip it without editing code. This bites everyone once; budget for it in M0.

### `firebase.json` — fixing what the web repo got wrong

Two defects carry no reason to survive ([01 §6](ios-rebuild-docs/01-ARCHITECTURE.md), Q10):

- Add an explicit `functions` emulator on port 5001. The web repo omitted it and relied on the CLI default matching a hard-coded client constant.
- Delete the `database` (9000) and `storage` (9199) emulator blocks. Neither service is used.

### Cloud Storage

Not used, exactly as today. `photoURL` points at the provider's CDN (`lh3.googleusercontent.com` for Google users). `AsyncImage` loads it directly; no Storage, no upload, no `storage.rules` beyond deny-all.

**Consequence:** email/password users have no avatar and never will, because there's nowhere to put one. They get the letter-initial placeholder. That is what the site does today (it renders initials for *everyone*, having never read `photoURL` at all). If you want avatar upload, it is a new feature and belongs in a later milestone.

---

## 4. Proposed schema v2

Since the schema is free. **You said you'd revise this yourself — treat it as a starting position, not a spec.**

### Changes from the web schema, and why

| # | Change | Reason |
|---|---|---|
| 1 | `Timestamp` + `FieldValue.serverTimestamp()` everywhere | The web stores epoch-ms `number` written by `Date.now()`. Comments and reports carry **client-clock** timestamps that the rules only check with `is number` ([03 §0](ios-rebuild-docs/03-DATA-MODEL.md)). A device with a wrong clock corrupts ordering. |
| 2 | `isAdmin` → **custom claim** on the ID token | The web's `isAdmin()` rules helper does a `get()` on the profile for *every* admin rule evaluation, burning a read and eating the 10-`get()` budget. A claim arrives free with the token. |
| 3 | Denormalize **`username` only**, not `displayName` | Here is the insight the web missed: `username` is **immutable by design** (rules pin it), so denormalizing it is permanently safe. `displayName` is **mutable**, so every submission and comment on the site carries a name that goes stale the moment the author edits their profile — and nothing backfills it. Store `authorUid` + `authorUsername`; resolve `displayName` from a cached profile read when you actually need it. Lists show `@username` anyway. |
| 4 | `openReportCount`, maintained on **both** create and resolution | The web's `reportCount` only ever increments (Q9). A submission auto-hidden at 3 reports, reviewed, dismissed, and restored still reads `3` — so the *next* report re-hides it instantly. |
| 5 | `origin: "attributed"` on the wire | The web says `shared` on the wire and `attributed` in the UI, translating at the boundary in four places. Pick the word users see. |
| 6 | `meaning` required-or-absent, consistently | `createSubmission` writes `meaning: ""`; the update rule demands `meaning.size() >= 1`. A submission created with an empty meaning could never pass the owner-update branch ([03 §4](ios-rebuild-docs/03-DATA-MODEL.md)). |
| 7 | Vote docs keep `createdAt`/`updatedAt`; counters stay `FieldValue.increment` | This part the web got right. Don't touch it. |
| 8 | **Profile counters deleted** (13 §A1) | `submissionCount` / `publishedCount` back no query; they were display-only. `count()` aggregation queries replace them (1 read per 1000 matched — free at this scale). Kills the counter triggers, the Q6 drift class, and the hidden-count privacy leak. |
| 9 | **Auth trigger deleted → `bootstrapProfile` callable** (13 §A2) | Idempotent; client calls it after sign-in when no profile exists. Removes the sign-up race, the emulator no-functions trap, and the v1/v2 split — there is no non-blocking v2 auth `onCreate`. Also updates `privateUsers.lastLoginAt` on every call, making that field honest for the first time. |
| 10 | **No `commentCount` field** (13 §A3) | The detail toolbar count comes from a `count()` aggregation on appear. No trigger, no drift. |
| 11 | **Admin actions become callables** (13 §A4) | `setSubmissionStatus` and `resolveReport`, admin claim required. `resolveReport` transactionally decrements `openReportCount`. Restore semantics: auto-hide only re-fires when *open* reports reach 3 again — Q9's ratchet closed by design. Consequence: submissions are **callable-write-only except delete**; the `\|\| isAdmin()` update branch disappears from the rules. |
| 12 | **`uid` dropped from public `usernames` docs** (13 §A5) | Availability needs existence only; deletion finds the doc via `profiles/{uid}.username`. Stops publishing the handle→UID map. |
| 13 | **`lastSeenAt` cut** (13 §A6) | Unused, and a public presence leak. Do not repeat the `photoURL` mistake. |
| 14 | **`blockedUids: [String]` on `privateUsers`** (13 §A7) | Rule-capped at 500. Arrives free with a doc the session already reads; no subcollection query. |
| 15 | **Rules enforce the username gate** (13 §A8) | Comment and report create assert the author profile's `username != null`. The web's gate was client-only; this one is real. |

### Collections

```
profiles/{uid}
    displayName    String
    username       String?      immutable once set
    bio            String
    photoURL       String?      provider CDN URL; now actually rendered
    createdAt      Timestamp
    -- no counters. Display counts are count() aggregation queries (13 §A1).
    -- no lastSeenAt (13 §A6).

privateUsers/{uid}
    email          String
    providerId     String?
    lastLoginAt    Timestamp    ← updated by bootstrapProfile on every sign-in
    blockedUids    [String]     ← rule-capped ≤ 500 (13 §A7)

privateUsers/{uid}/favorites/{submissionId}
    savedAt        Timestamp

usernames/{usernameLower}
    usernameOriginal, createdAt          ← no uid (13 §A5)

submissions/{id}
    authorUid      String
    authorUsername String?      ← immutable, safe to denormalize
    type           "Proverb" | "Poetry"
    language       "so" | "en"
    origin         "original" | "attributed" | "unknown"
    status         "published" | "hidden"
    statusChangedAt/By/Reason
    title          String?      required iff Poetry
    text           String       1…4000
    meaning        String?      ≤2000
    translation    String?      ≤2000
    source         { name, url?, notes? }?
    createdAt      Timestamp    serverTimestamp
    updatedAt      Timestamp?
    voteUp/voteDown/voteScore   Int
    searchIndex    String
    searchKeywords [String]     ≤60
    openReportCount Int         ← decrements

submissions/{id}/votes/{uid}          value, createdAt, updatedAt
submissions/{id}/comments/{autoId}    authorUid, authorUsername, body, createdAt
submissions/{id}/reports/{reporterUid} …12 fields, status, reviewedAt/By

rateLimits/{uid}_{action}             count, windowStart      [no client access]
```

### Rules

Rewritten, not ported. Two structural improvements:

- `isAdmin()` becomes `request.auth.token.admin == true` — no `get()`, no read cost.
- `serverTimestamp()` enforced: `request.resource.data.createdAt == request.time`.
- Comment and report **create** additionally assert the author profile's `username != null` (13 §A8). Costs one `get()`, closes the web's client-only onboarding gate for good.
- `submissions` update: `if false` for clients. All mutations flow through callables (content edits via `updateSubmission`, status via `setSubmissionStatus`, votes via `voteSubmission`). Delete stays direct (author or admin).

Everything else — the read gate on `status == 'published' || isOwner || isAdmin`, the exact-key-set check on reports, the one-vote-per-user doc ID, the `!exists()` guard on reports — was **correct on the web and should be copied deliberately**. That rules file is the best-engineered artifact in `abwaan-v2`.

### Cloud Functions

**Callables (all v2, all App-Check-attested):**

| Callable | Status |
|---|---|
| `claimUsername`, `createSubmission`, `updateSubmission`, `voteSubmission` | Ported. Fix `updateSubmission` (Q4: `resolvedTitle` read before `patch.title` is assigned → stale `searchIndex`. Port the function, not the bug). |
| **`bootstrapProfile`** | New (13 §A2). Idempotent: creates `profiles/{uid}` + `privateUsers/{uid}` if missing, updates `lastLoginAt`, returns the profile. Replaces the auth trigger. |
| **`setSubmissionStatus`** | New (13 §A4). Admin claim. Replaces the direct hide/restore `updateDoc`. |
| **`resolveReport`** | New (13 §A4). Admin claim. Stamps the report and transactionally decrements `openReportCount`. |
| **`deleteAccount`** | New. Guideline 5.1.1(v), tombstone semantics. See §9. |
| **`setAdminClaim`** | New. Admin-SDK-only script. The web had *no way at all* to grant admin. |

**Triggers (v2 only — the functions codebase has no v1 anywhere):**

| Trigger | Duty |
|---|---|
| `onReportCreate` (`onDocumentCreated`) | `openReportCount += 1`; auto-hide at ≥ 3 **open** reports. |
| `onSubmissionDelete` (`onDocumentDeleted`) | Bulk-delete `votes`/`comments`/`reports` subcollections, **paginated** (R16). No counter work — the counters no longer exist. |

Gone: `onAuthUserCreate` (→ `bootstrapProfile`), `onSubmissionCreate` (existed only to increment a counter that no longer exists).

**Write-surface map** — decided deliberately for offline behaviour (13 §A4):
- **Direct client writes** (Firestore SDK queues them offline): comments create/delete, favorites, report create, profile `displayName`/`bio`, `blockedUids`, submission delete.
- **Callables** (fail offline, actions disabled via `NWPathMonitor`): everything else above.

---

## 5. Data flow, loading, errors, empty states

### One state enum, everywhere

```swift
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(Error)
}
```

`.empty` is **derived at the view** from `loaded([])`, never stored (13 §C2). Storing it invites the state where a list is loaded-but-empty and nobody mapped it; four cases means one fewer illegal state.

| State | UI |
|---|---|
| `.loading` (first page) | `.redacted(reason: .placeholder)` over 6 real rows |
| `.loading` (next page) | `ProgressView` in the last row |
| `.loaded` | `List` |
| `.empty` | `ContentUnavailableView` — three variants (searching / filtering / neither), exactly as the web |
| `.failed` | `ContentUnavailableView` + Retry |

The web threw an error toast from `app.config.errorHandler` for *any* uncaught component error, which is a global panic button, not error handling. Errors here are values, surfaced where they happened.

### Pagination

The web holds `QueryDocumentSnapshot` cursors in `shallowRef` so Vue doesn't proxy them. Swift has no such problem: hold the `DocumentSnapshot` in the `@Observable` model, feed it to `.start(afterDocument:)`.

```swift
struct Page<T: Sendable>: Sendable {
    let items: [T]
    let cursor: DocumentSnapshot?
    var hasMore: Bool { cursor != nil }
}
```

Infinite scroll: `.task` on the last row. No "Load Next Batch" button.

### Optimistic voting

Port the web's logic, which is correct ([submissions.store.ts:224-281](client/src/features/submissions/submissions.store.ts:224)). Mutate local counters, call `voteSubmission`, reverse on throw. The one change: failure feedback is `.sensoryFeedback(.error, trigger:)` plus the counter snapping back, not a toast.

Tapping the same arrow twice sends `value: 0`, deleting the vote doc. Keep that.

---

## 6. Offline

Firestore's persistent cache is **on by default** on iOS. That's better than the web, which explicitly disables persistence in dev ([client.ts:22-24](client/src/data/firebase/client.ts:22)).

The sharp edge: **reads and direct writes queue; callables do not.**

| Operation | Path | Offline |
|---|---|---|
| Browse, search, read detail | Firestore query | ✅ Serves from cache |
| Read comments | Firestore query | ✅ Cache |
| Add comment | `addDocument` | ✅ **Queues**, syncs on reconnect |
| Save / unsave favorite | `setData` / `delete` | ✅ Queues |
| Report | `setData` | ✅ Queues |
| **Vote** | `voteSubmission` callable | ❌ **Fails immediately** |
| **Create submission** | `createSubmission` callable | ❌ Fails |
| **Edit submission** | `updateSubmission` callable | ❌ Fails |
| **Claim username** | `claimUsername` callable | ❌ Fails |

`httpsCallable` has no offline queue and never will — it's an RPC. So the optimistic vote will apply, throw, and roll back. That's correct behaviour but it needs a legible error, not a silent revert.

**Do not build an offline write queue for callables.** Detect connectivity with `NWPathMonitor`, disable the four callable-backed actions, and say why. The web's `navigator.onLine` check ([dbStatus.ts](client/src/shared/utils/dbStatus.ts)) was labelled "Heartbeat" and "SYSTEM ONLINE" but never touched the database; `NWPathMonitor` is the honest version of the same idea, used honestly.

---

## 7. Search

Three options were on the table ([07 §1.3](ios-rebuild-docs/07-DESIGN-TRANSLATION.md)). **Recommending Option 2**, with the door open to Option 3.

**Option 2 — scoped Firestore queries.** Keep `searchIndex` + `searchKeywords`, but pass `type` and `language` as real query predicates so the scope bar tells the truth. Requires new composite indexes:

```
status ASC, type ASC, searchIndex ASC
status ASC, type ASC, searchKeywords CONTAINS
status ASC, language ASC, searchIndex ASC
status ASC, type ASC, language ASC, searchKeywords CONTAINS
```

Two fixes to the derivation while we're rewriting it:

1. **`searchIndex` must mean one thing.** On the web it's the *title* for Poetry and the *text* for Proverbs ([functions/src/index.ts:146-148](functions/src/index.ts:146)), so prefix search behaves differently per type. Make it `title ?? text`, always, or index both.
2. **Tokenize the query, not just the document.** The web never splits the search term, so `array-contains` can only ever match a single-word query. Split the query and use `arrayContainsAny` (≤ 30 values **(verify)**), or accept prefix-only for multi-word.
3. **Somali-aware normalization** (13 §A9). Fold typographic apostrophes to ASCII (`'` `'` `ʼ` → `'`) — Somali orthography uses the apostrophe for the glottal stop (`ba'`, `la'aan`) and users will type it three ways. Case-fold and strip punctuation with **one shared function** applied to both the document at index time and the query at search time, and test that function. This is the cheapest search-quality win available and it is unique to this corpus.

Option 2 keeps the dependency count at two and the cost at zero. It will still be a mediocre search — Firestore is not a search engine. **Option 3** (Typesense or Algolia via an extension) is the real answer, costs money and a dependency, and is a good M-late milestone if search quality matters. Not v1.

---

## 8. Things with no iOS equivalent

| Web | Replacement |
|---|---|
| `vue-sonner` toasts | **Nothing.** UI state change + `.sensoryFeedback`. See [07 §1.11](ios-rebuild-docs/07-DESIGN-TRANSLATION.md). |
| `signInWithPopup` | `GoogleSignIn` SDK native flow → `GoogleAuthProvider.credential(...)` → `Auth.signIn(with:)`. Needs the reversed client ID as a URL scheme in `Info.plist`. |
| `navigator.clipboard` + `execCommand` + `window.prompt` fallback | `ShareLink`. Three tiers of fallback become one system sheet. |
| `window.location.reload()` | Nothing. Retry the failed request. |
| `navigator.onLine` | `NWPathMonitor` |
| Web Audio `BiquadFilter` graph | Pre-filtered `.m4a` asset + `AVAudioSession(.ambient, options: .mixWithOthers)`. Don't rebuild the DSP. |
| `navigator.connection.effectiveType` gating | Nothing. Bundled asset. |
| Lenis smooth scroll | Native scrolling |
| `@vueuse/motion` | Nothing (cut) |
| Service worker / PWA manifest | It's an app |
| `dompurify` / `sanitizeText` | Nothing. `Text` renders no markup. **The entire XSS surface disappears.** |
| `vue-router` + guards | `NavigationPath` + `Route` enum + Universal Links |
| 404 page | Nothing. No address bar. |
| `__APP_VERSION__` define | `Bundle.main.infoDictionary["CFBundleShortVersionString"]` |
| `/build.json` fetch | Compile-time constant |
| `v-html` | `Text` |

---

## 9. Two App Store requirements the web app does not satisfy

These are **not** scope drift. They are submission gates, and neither has any counterpart in `abwaan-v2`. I raise them now because they change the milestone plan.

### 9.1 In-app account deletion — Guideline 5.1.1(v)

An app that supports account creation **must** support in-app account deletion. Not "email us." Not "deactivate."

The web app has **no account deletion whatsoever** — I checked for `deleteUser` and found zero occurrences ([04 §2](ios-rebuild-docs/04-AUTH-AND-USERS.md)). The rules explicitly say `allow delete: if false` on both `profiles` and `privateUsers`.

This must be built:

- A `Delete Account` row in Settings, destructive, double-confirmed.
- Re-authentication first (`reauthenticateWithCredential`) — Firebase requires a recent login for `delete()`.
- An `onProfileDelete` / callable that removes `profiles/{uid}`, `privateUsers/{uid}` and its `favorites`, releases `usernames/{lower}`, and decides what happens to the user's **submissions and comments**.

That last clause is a product decision I cannot make for you: **does deleting an account delete the poetry?** For an archive whose stated purpose is preservation, tombstoning (reassign to a deleted-user sentinel, strip the `authorUid`) may be more appropriate than cascade-deleting cultural material. Whichever way, the *user's personal data* must go. **I need an answer before the milestone that implements it.**

### 9.2 User-generated content — Guideline 1.2

Apps with UGC must provide *all* of:

| Requirement | Web app | Status |
|---|---|---|
| A method for filtering objectionable material | Auto-hide at 3 reports | ✅ Exists |
| A mechanism to report offensive content | Report modal, 5 reasons | ✅ Exists |
| The ability to **block abusive users** | — | ❌ **Missing entirely** |
| Published contact information | `mailto:` in the footer | ⚠️ Footer is cut; needs a Settings row |
| Acting on reports within 24 hours | Manual admin queue | ⚠️ Process, not code |

**Blocking is net-new.** There is no block feature anywhere in the codebase — I grepped. Design (revised, 13 §A7): a `blockedUids: [String]` array on `privateUsers/{uid}`, rule-capped at 500 — it arrives free with a document the session already reads, no subcollection query. A "Block this user" action in the submission and comment overflow menus, plus client-side filtering of blocked users' submissions and comments. Server-side filtering isn't feasible in Firestore without denormalizing block lists into every query, so client-side filtering is the standard compromise here.

**Pagination interaction** (13 §B1 adjacent): client-side filtering *shrinks pages* — a page of 12 with 5 blocked authors renders 7 rows. The pagination loop must keep fetching until it fills a page or the cursor exhausts. Cheap to write, easy to forget.

Also needed: an EULA or a link to terms, and a stated moderation commitment.

**Both of these are the difference between "the app works" and "the app ships."** They belong in the roadmap as first-class milestones, not as polish.

---

## 10. Push notifications

**None. Do not add APNs, do not add FCM, do not request the entitlement.**

The web app has zero notification-shaped features. No follows, no mentions, no reply alerts, no digest. There is nothing to notify anyone about. Adding push would mean inventing a feature, which your scope rules forbid, and it would add a permission prompt, a capability, a privacy-manifest entry, and a review surface for no user benefit.

If comment-reply notifications are wanted later, that is a feature request with a data model attached (you'd need a `notifications` collection and a trigger), not a port.

---

## 11. Testing

The web app has **no test framework, no test files, and no CI** ([01 §10](ios-rebuild-docs/01-ARCHITECTURE.md)). Don't inherit that.

The repository protocol boundary from §2 is what makes this cheap:

| Target | Scope |
|---|---|
| `AbwaanTests` (Swift Testing) | Model `Codable` round-trips; `SubmissionDraft` validation; vote-delta arithmetic; `Page` cursor logic; `SessionModel` state transitions — all against in-memory fake repositories, no Firebase |
| Emulator integration | Rules tests via `@firebase/rules-unit-testing` in `firebase/`, run against the emulator in CI. **The rules are the only real authority in this system**; they deserve tests more than the Swift does. |
| `AbwaanUITests` | One smoke test per tab. Not more. |

Client-side validation must mirror the callables' server-side validation exactly. The web's two copies **disagree** — the client accepts any 2–8 character `language` while the server demands exactly `so` or `en` ([02 §C1](ios-rebuild-docs/02-FEATURES.md)). Define the constraints once in Swift, mirror them in TypeScript, and test both.

---

## 12. Privacy and compliance

- **`PrivacyInfo.xcprivacy` is required.** Declare data collection: email, name, user content, identifiers. Firebase ships its own privacy manifest **(verify current coverage)**.
- **Encryption export compliance**: `ITSAppUsesNonExemptEncryption = false` in `Info.plist` (HTTPS only).
- **App Privacy nutrition label** on App Store Connect, and it must match the manifest.
- **No App Check today**, on either platform. Adding it on iOS (DeviceCheck / App Attest) is genuinely worth it — the four callables are currently reachable by anyone holding the public API key, throttled only by per-UID `rateLimits` docs. Cheap on iOS, and it protects the same backend the retired site left exposed. Recommended, not required.
- Age rating: UGC with a reporting mechanism generally lands at 12+. Confirm during submission.

---

## 13. Decisions needed before Phase 3 — **ALL RESOLVED 2026-07-10**

1. **iOS 27.0 minimum** — ✅ confirmed (raised from 26.0; project + M0 spike are on 27).
2. **Account deletion** — ✅ tombstone (strip `authorUid`/`authorUsername`, keep the corpus).
3. **Blocking in v1** — ✅ yes, as the `blockedUids` array (§9.2).
4. **App Check** — ✅ in for v1.
5. **Schema v2** — ✅ revised via the review pass; §4 above now reflects the signed version ([13 §A1–A10](ios-rebuild-docs/13-REVIEW-AND-REVISIONS.md)). One open item remains: **launch-day content source** (13 §B2, owner: Niman).
</content>
