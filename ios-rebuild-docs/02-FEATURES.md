# 02 — Features

> Every feature listed here was traced to code. Anything I could not confirm is in [06-OPEN-QUESTIONS.md](ios-rebuild-docs/06-OPEN-QUESTIONS.md), not here.

Domain vocabulary: a **submission** is either a `Proverb` (Maahmaah) or `Poetry` (Gabay). Language is `so` or `en`. Origin is `original`, `shared`, or `unknown`.

---

## A. Authentication & identity

### A1. Email + password registration
Creates the Firebase user, sets the Auth `displayName`, then merges `displayName` into the profile doc.

- **Files:** [auth.store.ts:54-62](client/src/features/auth/auth.store.ts:54), [LoginPage.vue:42-47](client/src/features/auth/LoginPage.vue:42)
- **Touches:** Firebase Auth; `profiles/{uid}` (via `updateProfileDoc`)
- **Edge cases:** After `register` the page calls `profileStore.start(uid)` then pushes `/onboarding/username` directly, without waiting for the profile snapshot. The `onAuthUserCreate` trigger creates the profile doc asynchronously, so a race exists between trigger completion and the onboarding page's profile read. The onboarding page tolerates a null profile ([UsernameOnboardingPage.vue:16-18](client/src/features/onboarding/UsernameOnboardingPage.vue:16)).

### A2. Email + password sign-in
- **Files:** [auth.store.ts:64-68](client/src/features/auth/auth.store.ts:64), [LoginPage.vue:49-51](client/src/features/auth/LoginPage.vue:49)
- **Edge cases:** Honours `?redirect=` from the guard, defaulting to `/`.

### A3. Google sign-in (popup)
- **Files:** [auth.store.ts:70-76](client/src/features/auth/auth.store.ts:70), [LoginPage.vue:57-71](client/src/features/auth/LoginPage.vue:57)
- **Edge cases:** Unlike the email path, this one awaits `waitForProfile()` and branches on whether a username exists before redirecting. Uses `signInWithPopup`, not redirect.

### A4. Sign-out
- **Files:** [auth.store.ts:78-82](client/src/features/auth/auth.store.ts:78); triggered from the user dropdown in [TheNavigation.vue:45-48](client/src/shared/navigation/TheNavigation.vue:45)
- Pushes `/login` afterwards.

### A5. Session persistence
`setPersistence(auth, browserLocalPersistence)` is awaited inside `initAuthListener` before `onAuthStateChanged` is attached ([auth.store.ts:93](client/src/features/auth/auth.store.ts:93)).

### A6. Username claiming (one-time, permanent)
Calls the `claimUsername` callable, which transactionally checks `usernames/{lower}` and writes both that registry doc and `profiles/{uid}.username`.

- **Files:** [usernames.ts](client/src/data/functions/usernames.ts), [functions/src/index.ts:309-336](functions/src/index.ts:309), [UsernameOnboardingPage.vue](client/src/features/onboarding/UsernameOnboardingPage.vue), [ProfilePage.vue:53-69](client/src/features/profile/ProfilePage.vue:53)
- **Touches:** `usernames/{lower}`, `profiles/{uid}`, `rateLimits/{uid}_claimUsername`
- **Rules:** `usernames` is `allow read: if true; allow write: if false` — only the Admin SDK writes it. `profiles` update rules pin `username` to its prior value, so it cannot be changed client-side once set ([firestore.rules:104-107](firestore.rules:104)).
- **Validation:** `^[a-z0-9_]{3,20}$`, case-insensitive; the lowercase form is the doc ID, the original casing is stored as `usernameOriginal` and as `profiles.username`.
- **Error mapping:** `already-exists` → "That username is taken."; `invalid-argument` → format message; `unauthenticated` → "Please log in again."
- **Edge case:** There are two entry points. The onboarding page is reachable; the Settings-page claim form appears unreachable in practice — see [06-OPEN-QUESTIONS.md](ios-rebuild-docs/06-OPEN-QUESTIONS.md) Q3.

**Not present anywhere in the codebase:** password reset, email verification, Apple sign-in, phone auth, anonymous auth, account deletion, MFA. See [04-AUTH-AND-USERS.md](ios-rebuild-docs/04-AUTH-AND-USERS.md).

---

## B. Browsing & discovery

### B1. Home feed
Hero, two category blurbs (Gabay / Maahmaahyo), and the **three most recent** submissions sliced client-side from a 12-item fetch.

- **Files:** [HomePage.vue](client/src/features/home/HomePage.vue) — the slice is at [line 150](client/src/features/home/HomePage.vue:150)
- **Touches:** `submissions` (status `published`, ordered `createdAt desc`, limit 12)
- **Also:** a random image is picked on mount from an 8-item hard-coded gallery of archival photography with attribution strings ([HomePage.vue:237-278](client/src/features/home/HomePage.vue:237)).
- **States:** loading skeleton, error `EmptyState` with retry, empty `EmptyState` with a "Contribute" CTA.

### B2. Archive listing with filters, sort, and search
The main browse surface.

- **Files:** [CollectionsPage.vue](client/src/features/collections/CollectionsPage.vue), [submissions.store.ts:36-130](client/src/features/submissions/submissions.store.ts:36), [submissions.repo.ts:63-101](client/src/data/firestore/submissions.repo.ts:63)
- **Controls:**
  - Type tabs: `All Records` / `Proverbs` / `Poetry`
  - Language dropdown: `All Langs` / `Somali` / `English`
  - Sort dropdown: `Newest` (`createdAt desc`) / `Top Rated` (`voteScore desc`)
  - Free-text search box, submitted on **Enter** (not debounced-as-you-type)
- **Pagination:** "Load Next Batch" button, 12 per page for listing, 20 for search.
- **Edge cases:**
  - Changing any filter re-runs the list query — but **only when no search term is active** ([CollectionsPage.vue:197-201](client/src/features/collections/CollectionsPage.vue:197)). Filters therefore do not apply to search results at all: `searchSubmissions` accepts only `status`, never `type` or `language`.
  - A scroll handler hides/shows the filter bar on scroll direction, with a 10 px jitter threshold ([CollectionsPage.vue:165-185](client/src/features/collections/CollectionsPage.vue:165)). `isFilterBarVisible` is computed but **not bound to anything in the template** — the bar never actually hides.
  - Empty/error copy is context-sensitive across three cases: searching, filtering, or neither.

### B3. Search (dual-query)
Two parallel Firestore queries, merged and deduplicated by document ID.

- **File:** [submissions.repo.ts:187-269](client/src/data/firestore/submissions.repo.ts:187)
- **Query 1 (prefix):** `status == published` + `searchIndex >= term` + `searchIndex <= term + ''` + `orderBy(searchIndex)`
- **Query 2 (keyword):** `status == published` + `searchKeywords array-contains term`
- Each query gets `ceil(limit/2)` results and its own cursor. `searchPrefixDone` / `searchKeywordDone` flags let an exhausted query be skipped on subsequent `loadMore` calls ([submissions.store.ts:101-102](client/src/features/submissions/submissions.store.ts:101)).
- **Edge cases:** `searchIndex` is the **poem title** for Poetry and the **proverb text** for Proverbs ([functions/src/index.ts:146-148](functions/src/index.ts:146)), so prefix search means different things per type. `array-contains` matches whole tokens only — the term is never tokenized before querying, so a multi-word query can only ever hit the prefix branch. `searchKeywords` is capped at 60 tokens, tokens are 2–24 chars, drawn from the first 600 chars of each field.

### B4. Submission detail
- **File:** [SubmissionDetailPage.vue](client/src/features/submissions/SubmissionDetailPage.vue) (1158 lines — the largest component)
- Loads submission + the viewer's own vote in parallel ([submissions.repo.ts:141-159](client/src/data/firestore/submissions.repo.ts:141)), then comments, then favorite status.
- Renders type-dependent layout: Proverb shows `text` as the headline; Poetry shows `title` as the headline and `text` as an indented verse block.
- Optional sections: Interpretation (`meaning`), English Translation (`translation`), Historical Reference (`source`, only when `origin !== 'original'`).
- Re-loads on `route.params.id` change.
- All user-supplied strings are rendered through `v-html="sanitizeText(...)"` — `sanitizeText` HTML-escapes via `textContent`/`innerHTML` round-trip, so it emits escaped text, not markup ([sanitize.ts:25-29](client/src/shared/utils/sanitize.ts:25)).

### B5. Public contributor profile
- **Files:** [PublicProfilePage.vue](client/src/features/profile/PublicProfilePage.vue), [publicProfile.store.ts](client/src/features/profile/publicProfile.store.ts)
- Shows initial-avatar, display name, `@username`, bio, contribution count, and a paginated grid of that user's **published** submissions.
- **Touches:** `profiles/{uid}` (public read), `submissions` where `uid == …` and `status == published`
- **Edge case:** the "Total Contributions" figure renders `submissions.length` — the number of *currently loaded* submissions, not `profile.submissionCount` ([PublicProfilePage.vue:96](client/src/features/profile/PublicProfilePage.vue:96)). It grows as you press "Load more". The Desk and Settings pages both use the real `submissionCount`.

---

## C. Contribution

### C1. Create a submission
- **Files:** [SubmissionCreatePage.vue](client/src/features/submissions/SubmissionCreatePage.vue), [submission.validation.ts](client/src/features/submissions/submission.validation.ts), [functions/src/index.ts:340-485](functions/src/index.ts:340)
- Four-section form: Classification (type, language) → Manuscript (title, text) → Context (meaning, translation) → Provenance (origin, source).
- Title input is **only rendered for Poetry** ([SubmissionCreatePage.vue:205](client/src/features/submissions/SubmissionCreatePage.vue:205)); source fields only for origin = Attributed.
- On invalid submit: `showErrors` flips on and the page smooth-scrolls to the first error in a fixed precedence order ([SubmissionCreatePage.vue:40-63](client/src/features/submissions/SubmissionCreatePage.vue:40)).
- On success: toast, then navigate to `/s/{newId}`.

**Vocabulary mismatch that is intentional, not a bug.** The UI layer calls the middle origin option `attributed`; the wire format calls it `shared`. Translation happens at the boundary in `normalizeOrigin` ([SubmissionCreatePage.vue:71-75](client/src/features/submissions/SubmissionCreatePage.vue:71)) and inverted by `toDraftOrigin` ([SubmissionDetailPage.vue:145-149](client/src/features/submissions/SubmissionDetailPage.vue:145)).

**Client and server validation do not agree.** Both matter, because the client blocks the request and the server is authoritative:

| Field | Client ([submission.validation.ts](client/src/features/submissions/submission.validation.ts)) | Server ([functions/src/index.ts](functions/src/index.ts)) |
|---|---|---|
| `type` | required, ∈ {Proverb, Poetry} | required, ∈ {Proverb, Poetry} |
| `title` | required + 3–120 chars **only if Poetry** | same |
| `text` | required, ≤ 4000 | required, ≤ 4000 |
| `meaning` | ≤ 2000, **optional** | ≤ 2000, **optional** |
| `translation` | ≤ 2000, optional | ≤ 2000, optional |
| `language` | optional; if present, 2–8 chars — accepts `"xx"`, `"klingon"` | **required**, must be exactly `so` or `en` |
| `origin` | optional; ∈ {original, attributed, unknown} | **required**, ∈ {original, shared, unknown} |
| `source.name` | required if origin = attributed | required if origin = shared |
| `source.url` | must parse as URL if present | same |

The client always sends a normalized `language`/`origin` because `normalizeLanguage` defaults to `so` and `normalizeOrigin` defaults to `unknown`, so the divergence is masked in practice. It matters for an iOS rewrite because the *server* contract is the real one.

### C2. Edit a submission (author or admin)
- **Files:** [SubmissionDetailPage.vue:359-396](client/src/features/submissions/SubmissionDetailPage.vue:359), [submissions.repo.ts:110-125](client/src/data/firestore/submissions.repo.ts:110), [functions/src/index.ts:601-797](functions/src/index.ts:601)
- Inline edit mode replaces the article body with the same form fields. `hasChanges` deep-compares against the loaded submission, and Save is disabled unless the draft is both valid and changed ([SubmissionDetailPage.vue:198-213](client/src/features/submissions/SubmissionDetailPage.vue:198)).
- Server re-authorizes (owner OR admin), rebuilds search fields when `title`/`text`/`meaning`/`type` changed, and stamps `updatedAt` / `updatedBy`.
- **Edge case:** switching type Poetry → Proverb nulls the title server-side ([functions/src/index.ts:766-771](functions/src/index.ts:766)).
- **Confirmed defect** in search-field rebuild on title edit — see [06-OPEN-QUESTIONS.md](ios-rebuild-docs/06-OPEN-QUESTIONS.md) Q4.
- The "Edit Submission" button is gated on `isAuthor` only, so an **admin editing someone else's post has no UI entry point**, even though the callable would allow it.

### C3. Delete a submission (author or admin)
- **Files:** [SubmissionDetailPage.vue:252-263](client/src/features/submissions/SubmissionDetailPage.vue:252), [submissions.repo.ts:271-274](client/src/data/firestore/submissions.repo.ts:271)
- Direct client `deleteDoc`, not a callable. Rules allow `isOwner(resource.data.uid) || isAdmin()` ([firestore.rules:167](firestore.rules:167)).
- Confirmation dialog first; on success, toast + navigate to `/collections`.
- The `onSubmissionDelete` trigger then decrements `submissionCount` and bulk-deletes the three subcollections.
- **UI gate:** the delete button renders only under `v-if="isAuthor"` ([SubmissionDetailPage.vue:1009](client/src/features/submissions/SubmissionDetailPage.vue:1009)), so admins have no delete affordance despite the rule permitting it.

---

## D. Engagement

### D1. Voting (up / down / toggle-off)
- **Files:** [votes.ts](client/src/data/functions/votes.ts), [submissions.store.ts:224-281](client/src/features/submissions/submissions.store.ts:224), [functions/src/index.ts:489-579](functions/src/index.ts:489)
- Clicking the same arrow twice sends `value: 0`, which deletes the vote doc.
- Client updates `voteUp` / `voteDown` / `voteScore` and `userVote` immediately, then calls the callable; on failure it toasts "Vote failed" and reverses every mutation.
- Server recomputes deltas from the prior vote doc and applies `FieldValue.increment` inside a transaction — never a read-then-write of the counter.
- **Touches:** `submissions/{id}` counters, `submissions/{id}/votes/{uid}`, `rateLimits/{uid}_voteSubmission`
- **Edge cases:** guests clicking a vote arrow are routed to `/login` ([SubmissionDetailPage.vue:215-223](client/src/features/submissions/SubmissionDetailPage.vue:215)); the buttons are also `:disabled` for guests. Vote rules grant read only to the vote's own owner ([firestore.rules:184-186](firestore.rules:184)) and no client write path at all.

### D2. Comments
- **Files:** [comments.repo.ts](client/src/data/firestore/comments.repo.ts), [comments.store.ts](client/src/features/submissions/comments.store.ts), [CommentForm.vue](client/src/features/submissions/CommentForm.vue), [CommentList.vue](client/src/features/submissions/CommentList.vue)
- Written **directly from the client** via `addDoc` — no callable. Body 1–2000 chars, enforced by both the form and the rules.
- Ordered `createdAt desc`, paginated 12 at a time, capped in a `max-h-[520px]` scroll area marked `data-lenis-prevent` so Lenis does not hijack the inner scroll.
- Delete allowed for the comment author or any admin ([SubmissionDetailPage.vue:424-426](client/src/features/submissions/SubmissionDetailPage.vue:424); rules at [firestore.rules:181](firestore.rules:181)).
- Rules require the writer to have a profile, and force `username`/`displayName` on the comment to match the profile (or the auth token's name/email) — denormalized author fields cannot be spoofed ([firestore.rules:171-179](firestore.rules:171)).
- **Edge case:** comments are `allow update: if false` — no editing, ever.
- **Edge case:** the "N Comments" counter reflects loaded items, not a total.
- Guests see a "Log in to add your voice" panel instead of the textarea.

### D3. Favorites / saved collection
- **Files:** [favorites.repo.ts](client/src/data/firestore/favorites.repo.ts), [favorites.store.ts](client/src/features/favorites/favorites.store.ts)
- Stored at `privateUsers/{uid}/favorites/{submissionId}` — the submission ID **is** the doc ID, which makes toggling idempotent and duplicate-proof.
- Listing does a favorites query, then batch-hydrates the submissions in chunks of 10 via `where(documentId(), 'in', batch)` — a deliberate N+1 workaround for Firestore's lack of joins ([favorites.repo.ts:71-81](client/src/data/firestore/favorites.repo.ts:71)).
- `togglingIds` is a per-item `Set`, so one pending toggle does not disable every other card.
- **Edge case:** if a favorited submission was deleted, hydration silently drops it from the list (`.filter(item => item !== null)`) but the orphan favorite doc remains.
- **Edge case:** the detail page's favorite button binds `:disabled="favoritesStore.busy"` ([SubmissionDetailPage.vue:918](client/src/features/submissions/SubmissionDetailPage.vue:918)), the old global flag, rather than the per-item `isToggling`.

### D4. Share
Copies `window.location.href` with a three-tier fallback: `navigator.clipboard` → hidden textarea + `document.execCommand('copy')` → `window.prompt` ([SubmissionDetailPage.vue:265-297](client/src/features/submissions/SubmissionDetailPage.vue:265)). No Web Share API.

### D5. Reporting content
- **Files:** [reports.repo.ts:18-55](client/src/data/firestore/reports.repo.ts:18), report modal at [SubmissionDetailPage.vue:1090-1156](client/src/features/submissions/SubmissionDetailPage.vue:1090)
- Written directly from the client to `submissions/{id}/reports/{reporterUid}`. Using the reporter's UID as the doc ID enforces **one report per user per submission** structurally; the rules additionally assert `!exists(...)` ([firestore.rules:210](firestore.rules:210)).
- Reasons: `spam`, `abuse`, `plagiarism`, `inaccurate`, `other`. Optional details, ≤ 2000 chars.
- The report doc denormalizes submission title/type/author and reporter username at write time.
- Modal handles Escape-to-close, focuses the reason `<select>` on open, and restores focus to the trigger on close ([SubmissionDetailPage.vue:467-476](client/src/features/submissions/SubmissionDetailPage.vue:467)).
- Guests are redirected to `/login`.
- **Auto-moderation:** `onReportCreate` increments `reportCount`; at **3 or more** reports a `published` submission is flipped to `hidden` by `system` ([functions/src/index.ts:272-306](functions/src/index.ts:272)).

---

## E. Personal workspace

### E1. The Desk (`/desk`)
Two tabs, each lazily loaded on first activation and cached via a `loadedTabs` map ([DeskPage.vue:21-61](client/src/features/desk/DeskPage.vue:21)).

- **Works** — the user's own submissions, fetched with `status: 'all'` so hidden posts remain visible to their author ([profile.store.ts:74-79](client/src/features/profile/profile.store.ts:74)).
- **Collection** — the user's favorites.
- Header shows `submissionCount` from the profile doc and the loaded favorites count.
- Note: this page is titled "The Study." in its own heading ([DeskPage.vue:106](client/src/features/desk/DeskPage.vue:106)) while the admin page is titled "The Desk." — see [06-OPEN-QUESTIONS.md](ios-rebuild-docs/06-OPEN-QUESTIONS.md) Q7.

### E2. Settings (`/settings`)
- **File:** [ProfilePage.vue](client/src/features/profile/ProfilePage.vue)
- Editable: `displayName`, `bio`. Written with `setDoc(..., { merge: true })`.
- Read-only: join date, total contributions, and the claimed `@username` shown as a green "Status: Active" badge.
- Rules pin `username`, `isAdmin`, and `submissionCount` to their existing values on any client profile update ([firestore.rules:104-107](firestore.rules:104)), so a user cannot self-promote or inflate their count.
- No avatar upload. `photoURL` is populated once by the auth trigger from the provider and never surfaced in any component — every avatar in the UI is a generated letter initial.

---

## F. Moderation (role-gated)

### F1. Admin console (`/admin`)
Gated by `meta.requiresAdmin` in the router **and** by `isAdmin()` in the rules.

- **Files:** [AdminPage.vue](client/src/features/admin/AdminPage.vue), [reports.store.ts](client/src/features/admin/reports.store.ts), [reports.repo.ts](client/src/data/firestore/reports.repo.ts)

**Submissions tab** — filter by `hidden` (default) or `published`; each card shows an open-report count badge and a Hide/Approve toggle. Report counts come from a `collectionGroup('reports')` query batched 10 IDs at a time ([reports.repo.ts:81-104](client/src/data/firestore/reports.repo.ts:81)) and are only computed when the filter is not `published` ([AdminPage.vue:94](client/src/features/admin/AdminPage.vue:94)).

**Reports tab** — filter by `open` / `reviewed` / `dismissed`; reports are grouped by submission and sorted by most-recent report. Each report can be **Dismissed** or **Resolved** (`reviewed`), which stamps `reviewedAt` + `reviewedBy`. Resolution controls only render while viewing the `open` filter ([AdminPage.vue:79](client/src/features/admin/AdminPage.vue:79)).

- `reportsStore.load` passes `limit = 0`, which is falsy, so the `limit()` constraint is skipped and **all** matching reports load unbounded ([reports.store.ts:16](client/src/features/admin/reports.store.ts:16), [reports.repo.ts:59-61](client/src/data/firestore/reports.repo.ts:59)).
- Resolving a report does **not** change the submission's `status` or decrement `reportCount`. Those are independent. A submission auto-hidden at 3 reports stays hidden until an admin explicitly restores it.

### F2. Inline moderation on the detail page
Admins see a "Moderation" panel with a Hide/Restore toggle and the current status ([SubmissionDetailPage.vue:988-1007](client/src/features/submissions/SubmissionDetailPage.vue:988)). Calls `updateSubmissionStatus`, a **direct client `updateDoc`** permitted by the `|| isAdmin()` branch of the submissions update rule ([submissions.repo.ts:127-139](client/src/data/firestore/submissions.repo.ts:127), [firestore.rules:166](firestore.rules:166)).

### F3. Visibility of hidden content
`status: 'hidden'` removes a submission from public listings. It remains readable by its author and by admins, enforced identically in the rules for the document and for its comments subcollection ([firestore.rules:129-132](firestore.rules:129), [firestore.rules:47-53](firestore.rules:47)).

---

## G. Roles, flags, and hidden surfaces

| Mechanism | How it works |
|---|---|
| **Admin role** | Boolean `profiles/{uid}.isAdmin`. There is **no UI or callable to grant it** — it must be set out-of-band (console / Admin SDK). Rules block clients from writing it. |
| **Feature flags** | None. No flag system exists. |
| **Hidden routes** | `/admin` is not linked from the footer or main nav; it appears in the user dropdown only when `isAdmin` is true ([useNavigation.ts:18-28](client/src/shared/navigation/useNavigation.ts:18)). |
| **Undocumented route** | `/roadmap` is a public marketing/status page linked from the footer. |

---

## H. Chrome, ambient, and platform features

### H1. Splash screen
Full-screen `AppLoader` until auth resolves, with a 400 ms minimum and 5000 ms maximum ([App.vue:46-58](client/src/App.vue:46)).

### H2. Offline banner
Listens to `window` `online`/`offline`, shows a dismissible "Connection Lost" card with a "Retry Connection" button that calls `window.location.reload()` ([App.vue:96-134](client/src/App.vue:96)). Dismissal resets when connectivity returns.

### H3. System status indicator
`useDatabaseStatus` reports `checking` / `online` / `offline` **purely from `navigator.onLine`** — it never pings Firestore, despite the name and the "Heartbeat" label ([dbStatus.ts](client/src/shared/utils/dbStatus.ts)). Rendered in the footer and mobile nav.

### H4. Ambient audio player
A floating "Ambient On/Off" pill, bottom-right, globally mounted ([AudioPlayer.vue](client/src/shared/components/AudioPlayer.vue), mounted at [App.vue:144](client/src/App.vue:144)).

- Web Audio graph: `MediaElementSource → BiquadFilter(lowpass 800 Hz, Q 0.7) → Gain → destination`.
- Target volume 0.03; 2 s exponential fade-in, 1.5 s fade-out.
- Attempts autoplay on mount; skips loading entirely on `slow-2g`/`2g`/`3g` per `navigator.connection.effectiveType`.
- Pauses on tab hide and resumes on return, unless the user paused manually.
- Audio asset: `client/src/assets/audio/archive-sound.mp3`, dynamically imported.

### H5. PWA / installability
`vite-plugin-pwa` with `registerType: 'autoUpdate'`, precaching js/css/html/ico/png/svg/jpg/woff2 and runtime-caching Google Fonts and Firebase Storage ([vite.config.ts:16-81](client/vite.config.ts:16)). A second, hand-written [public/manifest.json](client/public/manifest.json) also exists and is **not referenced from `index.html`**; the plugin generates its own manifest. Both declare `theme_color: #FF6B35`, which does not match any colour in the Tailwind palette.

### H6. Global dialog & toasts
`useDialog` is a module-scoped singleton holding a promise resolver, driven by `confirmAction(title, text)` and rendered once by `GlobalDialog` ([useDialog.ts](client/src/shared/utils/useDialog.ts), [GlobalDialog.vue](client/src/shared/components/GlobalDialog.vue)). Toasts via `vue-sonner`, `position="top-center" richColors`.

### H7. Global error handler
`app.config.errorHandler` logs and raises an error toast for any uncaught error in a Vue component ([main.ts:12-16](client/src/main.ts:12)).

### H8. Smooth scrolling
Lenis with `autoRaf: true`, destroyed on unmount. `data-lenis-prevent` opts the comment list out.

---

## I. Static content pages

| Page | Route | Notes |
|---|---|---|
| About / Mission | `/about` | Long-form editorial: "The Trigger", "The Decay", mission statement, CTAs to `/collections` and `/contribute` ([AboutPage.vue](client/src/features/home/AboutPage.vue)) |
| Roadmap | `/roadmap` | Phase cards with tap-to-expand items; fetches `/build.json` for a build timestamp and renders `__APP_VERSION__` ([RoadmapPage.vue](client/src/features/home/RoadmapPage.vue)) |
| 404 | `/:pathMatch(.*)*` | Archive-themed not-found page ([NotFoundPage.vue](client/src/features/home/NotFoundPage.vue)) |

---

## J. Dead or unreferenced code (confirmed by grep, zero call sites)

Listing these so they are **not** carried into the iOS app.

| Item | File | Status |
|---|---|---|
| `SearchBar.vue` | [collections/SearchBar.vue](client/src/features/collections/SearchBar.vue) | Debounced search input component; `CollectionsPage` uses a raw `<input>` instead. No importers. |
| `sanitizeHtml()` | [sanitize.ts:10](client/src/shared/utils/sanitize.ts:10) | No call sites. This is the only function that would use the missing `dompurify`, along with `stripHtml`. |
| `stripHtml()` | [sanitize.ts:38](client/src/shared/utils/sanitize.ts:38) | No call sites. |
| `debugLog()` | [debug.ts:3](client/src/shared/utils/debug.ts:3) | No call sites. |
| `showAlert()` | [alerts.ts:25](client/src/shared/utils/alerts.ts:25) | No call sites. |
| `aos` package | [client/package.json:23](client/package.json:23) | Declared dependency, zero imports. |
| Newsletter form | [Footer.vue:184-201](client/src/shared/navigation/Footer.vue:184) | Commented out; the backing `email` ref is still declared and unused. |
| `isFilterBarVisible` | [CollectionsPage.vue:22](client/src/features/collections/CollectionsPage.vue:22) | Computed by a live scroll listener, never bound in the template. |
| RTDB + Storage emulators | [firebase.json:18-23](firebase.json:18) | Configured; no code uses either service. |
| `public/manifest.json` | [client/public/manifest.json](client/public/manifest.json) | Not linked from `index.html`; superseded by the PWA plugin's generated manifest. |
</content>
