# 05 — Screens and Flows

Route table source: [client/src/app/router/index.ts](client/src/app/router/index.ts). All twelve routes are lazy-loaded.

## 1. Route table

| # | Path | Name | Component | Guard |
|---|---|---|---|---|
| 1 | `/` | `home` | [HomePage.vue](client/src/features/home/HomePage.vue) | — |
| 2 | `/login` | `login` | [LoginPage.vue](client/src/features/auth/LoginPage.vue) | `guestOnly` |
| 3 | `/collections` | `collections` | [CollectionsPage.vue](client/src/features/collections/CollectionsPage.vue) | — |
| 4 | `/s/:id` | `submission-detail` | [SubmissionDetailPage.vue](client/src/features/submissions/SubmissionDetailPage.vue) | — |
| 5 | `/p/:uid` | `public-profile` | [PublicProfilePage.vue](client/src/features/profile/PublicProfilePage.vue) | — |
| 6 | `/contribute` | `submission-create` | [SubmissionCreatePage.vue](client/src/features/submissions/SubmissionCreatePage.vue) | `requiresAuth` |
| 7 | `/onboarding/username` | `onboarding-username` | [UsernameOnboardingPage.vue](client/src/features/onboarding/UsernameOnboardingPage.vue) | `requiresAuth` |
| 8 | `/desk` | `desk` | [DeskPage.vue](client/src/features/desk/DeskPage.vue) | `requiresAuth` |
| 9 | `/settings` | `settings` | [ProfilePage.vue](client/src/features/profile/ProfilePage.vue) | `requiresAuth` |
| 10 | `/admin` | `admin` | [AdminPage.vue](client/src/features/admin/AdminPage.vue) | `requiresAuth` + `requiresAdmin` |
| 11 | `/about` | `about` | [AboutPage.vue](client/src/features/home/AboutPage.vue) | — |
| 12 | `/roadmap` | `roadmap` | [RoadmapPage.vue](client/src/features/home/RoadmapPage.vue) | — |
| — | `/:pathMatch(.*)*` | `not-found` | [NotFoundPage.vue](client/src/features/home/NotFoundPage.vue) | — |

Chrome visibility ([App.vue:16-19](client/src/App.vue:16)):

| Route | Nav | Footer |
|---|---|---|
| `/login` | hidden | hidden |
| `/onboarding/username` | hidden | hidden |
| everything else | shown | shown |

The `AudioPlayer` pill, `GlobalDialog`, `Toaster`, offline banner, and splash screen are mounted globally on every route.

---

## 2. Screen-by-screen

### 2.1 `/` — Home

**Purpose:** Landing / brand statement.

**Data loaded on mount:** `submissionsStore.loadLatest(undefined, false)` → `submissions` where `status == 'published'`, `orderBy createdAt desc`, `limit 12`. Only the first **3** are rendered.

**Also:** picks one of 8 hard-coded archival images at random and renders it with an attribution caption.

**Actions:** none, beyond navigation.

**Navigates to:** `/collections` ("Access Full Archive"), `/contribute` (empty-state CTA), `/s/:id` and `/p/:uid` via each card.

**States:** loading skeleton → grid | error `EmptyState` (retry) | empty `EmptyState` (Contribute).

---

### 2.2 `/login` — Login / Register

**Purpose:** Both sign-in and sign-up, toggled by one boolean.

**Mode selection:** `?mode=register` or `?mode=login` sets the initial mode via an `immediate` watcher ([LoginPage.vue:26-37](client/src/features/auth/LoginPage.vue:26)); a footer button toggles it thereafter. Copy changes accordingly ("Member Access" / "Member Registration", "Enter Archive" / "Create ID").

**Fields:** Identity (register only), Credentials (email), Security Key (password). Plus a "Continue with Google" button.

**Data loaded:** none.

**Actions:** register, login, Google sign-in.

**Navigates to:** `/onboarding/username` after register, or after Google sign-in when no username exists; otherwise `?redirect=` or `/`.

**States:** `authStore.busy` disables both buttons and shows a spinner; `authStore.error` renders as `/// Error: …` beneath.

**Guard:** `guestOnly` — a signed-in user hitting `/login` is bounced to `/`.

---

### 2.3 `/onboarding/username` — Claim handle

**Purpose:** Mandatory, one-time username claim. Full-bleed, no nav, no footer.

**Data loaded:** reads `profileStore.profile` (already streaming). Greets the user by `profile.displayName || auth.displayName || auth.email || 'Member'`.

**Actions:** submit a username → `claimUsername` callable.

**Navigates to:** `/` on success, and also automatically the instant the profile snapshot reports a non-null username.

**States:** local `busy`, local `error`; a "Syncing Profile Data…" hint while `profileStore.busy && !profile`.

**This is a hard gate.** Any authenticated user whose `profile.username` is `null` is redirected here from every route except `/login*` and this page itself.

---

### 2.4 `/collections` — The Archive

**Purpose:** Primary browse + search surface.

**Data loaded on mount:** `loadLatest()` → published submissions, 12/page.

**Controls:**
- Type tabs: All Records / Proverbs / Poetry
- Search input (submits on **Enter**; a "Clear" button appears once non-empty)
- Language dropdown: All Langs / Somali / English
- Sort dropdown: Newest / Top Rated

**Actions:** filter, sort, search, clear search, reset filters, load next batch.

**Navigates to:** `/s/:id` (card body), `/p/:uid` (card author chip), `/contribute` (empty-state CTA).

**States:** `loading` → 6 skeleton cards | `error` → `EmptyState` with retry, plus "Clear search" when searching | `empty` → `EmptyState` whose title/description/CTA vary across three cases (searching, filtering, neither) | `grid`.

**Behavioural notes:**
- Filters and search are mutually exclusive. Changing a filter while a search term is active does nothing, because the watcher is `if (!hasSearch.value)`. And `searchSubmissions` never receives `type` or `language`. Searching therefore always searches the entire published corpus.
- A search-results banner shows "Showing N results" and, when more pages exist, "More results available".
- The scroll listener that computes `isFilterBarVisible` drives no template binding; the bar never hides.

---

### 2.5 `/s/:id` — Submission detail

The densest screen in the app. Three stacked regions: header/breadcrumb, a 8/4 content+sidebar grid, and a full-width comments section.

**Data loaded on mount and on `:id` change:**
1. `getSubmissionWithUserVote(id, uid)` — the submission plus the viewer's own vote, in parallel.
2. `commentsStore.load(id)` — 12 comments, `createdAt desc`.
3. `favoritesStore.ensureFavoriteStatus(id)` — only when signed in.

**Content rendering is type-dependent:**

| | Proverb | Poetry |
|---|---|---|
| Headline | `text` | `title` (or "Untitled Piece") |
| Verse block | — | `text`, `whitespace-pre-line`, quoted, left-rule |

Optional blocks: `meaning` → "/// INTERPRETATION"; `translation` → "/// ENGLISH TRANSLATION"; `source` → "Historical Reference" (only when `origin !== 'original'`), showing name, notes, and an outbound link.

**Sidebar, top to bottom:**
- *Archived By* — initial avatar + display name + `@username`, linking to `/p/:uid`.
- *Community Validation* — up/down arrows flanking `voteScore`. Disabled for guests; clicking as a guest routes to `/login`.
- *Three-up action row* — Share ID (clipboard), Save (favorite toggle), Report (opens modal).
- *Author Tools* (`v-if="isAuthor"`) — "Edit Submission" / "Exit Edit Mode".
- *Moderation* (`v-if="isAdmin"`) — status readout + "Hide Submission" / "Restore Submission".
- *Danger zone* (`v-if="isAuthor"`) — "Permanently Delete".

**Edit mode** swaps the article for an inline form with the same fields as `/contribute`. Save is enabled only when the draft is valid **and** differs from the loaded submission. Cancel restores the draft from the submission.

**Report modal** — reason `<select>` (5 options) + optional details (≤ 2000, live counter). Escape closes; focus moves to the select on open and back to the trigger on close. Backdrop click closes.

**Comments section** — left rail shows "Discussion" and a loaded-count; right side has `CommentForm` (or a "Log in to add your voice" panel for guests) above `CommentList`. The list scrolls internally, capped at 520 px, with `data-lenis-prevent`. Each row shows author, date, `[Delete]` (own comment, or admin), and the body.

**States:** loading spinner ("Retrieving Record…") | `loadError` → `EmptyState` "Record Unavailable" | not-found → inline 404 block | loaded.

---

### 2.6 `/contribute` — Create a submission

**Guard:** `requiresAuth`.

**Purpose:** Author a new proverb or poem.

**Structure:** a hero, then four numbered sections, then a full-width dark submit bar.

| § | Heading | Fields |
|---|---|---|
| 01 | Classification | Category (Proverb / Poetry), Language (Somali / English) |
| 02 | The Manuscript | Title *(Poetry only)*, Text ("Verses" or "Proverb Text") |
| 03 | Context | Hidden Meaning / Context, English Translation |
| 04 | Provenance | Origin Type; Source name / URL / notes *(only when origin = Attributed)* |

**Data loaded:** none.

**Actions:** submit → `createSubmission` callable.

**Validation UX:** the submit button label reads "Complete all fields" until the draft validates, then "Confirm & Publish". Errors render as `/// Error: …` under each field, only after the first submit attempt, and the page smooth-scrolls to the first error in a fixed precedence order.

**Navigates to:** `/s/{newId}` on success, with a success toast.

---

### 2.7 `/desk` — The Desk (personal workspace)

**Guard:** `requiresAuth`. Heading reads "The Study."

**Structure:** hero + a "Quick Metrics" panel (Works = `profile.submissionCount`, Collection = loaded favorites count), then two tabs.

| Tab | Label | Source | Notes |
|---|---|---|---|
| `contributions` | Works | `listSubmissionsByAuthor(uid, 12, cursor, 'all')` | `status: 'all'` — the author sees their own hidden posts |
| `saved` | Collection | `listFavoriteSubmissions({ uid, limit: 12 })` | favorites → batched submission hydration |

Each tab loads lazily on first activation and is then cached in a `loadedTabs` map; "Try Again" forces a reload.

**Actions:** switch tab, load more, retry.

**Navigates to:** `/s/:id`, `/p/:uid`, `/contribute` (empty state), `/collections` (empty state).

**States:** per-tab loading spinner | error `EmptyState` | empty `EmptyState` | grid + `LoadMore`.

---

### 2.8 `/settings` — Archive Identity

**Guard:** `requiresAuth`.

**Data loaded:** `profileStore.profile` (already streaming). Header shows join date and total contributions.

| § | Heading | Content |
|---|---|---|
| 01 | Personal Details | `displayName` and `bio`, with a "Save Changes" button |
| 02 | Official Handle | If a username exists: a green "Status: Active / @handle" card. Otherwise: an inline claim form. |

**Actions:** save profile (`setDoc` merge); claim username (callable).

**States:** full-page spinner while `busy && !profile`; inline error text.

**Note:** the claim form in §02 renders only when `profile.username` is falsy — but the router guard redirects exactly those users to `/onboarding/username` before this page can render. The branch appears unreachable. See [06-OPEN-QUESTIONS.md](ios-rebuild-docs/06-OPEN-QUESTIONS.md) Q3.

---

### 2.9 `/p/:uid` — Public contributor profile

**Purpose:** Another member's public dossier.

**Data loaded:** `getProfile(uid)` and `listSubmissionsByAuthor(uid, 12)` (published only) in parallel.

**Renders:** large initial avatar, display name, `@username` chip, bio (or an italic placeholder), a "Total Contributions" figure, then a grid of that user's published works with `LoadMore`.

**Actions:** load more; open any card.

**States:** spinner ("Locating Contributor…") | error or missing profile → `EmptyState` "Member Not Found" | empty works → `EmptyState` "The Archive is Silent" | grid.

**Note:** "Total Contributions" renders `submissions.length` (currently loaded), not `profile.submissionCount`, so the number grows as you paginate.

---

### 2.10 `/admin` — Admin console

**Guard:** `requiresAuth` + `requiresAdmin`. Heading reads "The Desk."

Two tabs, each with its own status filter chips.

**Submissions tab** — filter `hidden` (default) or `published`.
- Loads `loadLatest(undefined, false, 'createdAt', undefined, activeStatus)`.
- Then `countOpenReportsBySubmissionIds(ids)` — skipped entirely when the filter is `published`.
- Each card: index/type, date, title-or-text, author, and either a red "N Active Reports" badge or a green "Reports Resolved" badge.
- Actions per card: **Inspect** (→ `/s/:id`) and **Approve** / **Hide**.

**Reports tab** — filter `open` / `reviewed` / `dismissed`.
- Loads all matching reports (unbounded; `limit` is passed as `0`), grouped by submission, sorted by most-recent report.
- Each group: report count, date, submission title (linking to `/s/:id`), and a `<details>` disclosure listing each individual report with its reason, details, and date.
- Actions per report, **only while the `open` filter is active**: **Dismiss** or **Resolve**.

**States:** "LOADING DATA…" | error `EmptyState` | empty `EmptyState` ("Queue is clear" / "No reports to review") | grid.

**Not wired:** resolving a report does not alter the submission's `status` or its `reportCount`.

---

### 2.11 `/about`, `/roadmap`, 404

- **`/about`** — static editorial: hero, "The Trigger", "The Decay", mission, closing CTAs to `/contribute` and `/collections`.
- **`/roadmap`** — phase cards with tap-to-expand items; fetches `/build.json` (`cache: 'no-store'`) for a build timestamp, renders `__APP_VERSION__`, and swallows fetch failures silently.
- **404** — archive-themed, with "Return Home" and "Browse Archive".

---

## 3. Key user journeys

### J1 — New user signs up and publishes their first entry

1. Guest lands on `/`, sees three recent entries, taps **Join Archive** → `/login?mode=register`.
2. Enters Identity, email, password → `authStore.register()`.
3. `onAuthUserCreate` creates `profiles/{uid}` (`username: null`) and `privateUsers/{uid}`.
4. Client pushes `/onboarding/username`.
5. User types a handle → `claimUsername` → transaction writes `usernames/{lower}` + `profiles/{uid}.username`.
6. The profile `onSnapshot` fires; the page's watcher redirects to `/`.
7. User taps **Contribute** → `/contribute`.
8. Fills the four sections. The submit bar stays "Complete all fields" until valid.
9. **Confirm & Publish** → `createSubmission` (rate limit 10/hr) → validation → search fields → doc write with `status: 'published'`.
10. `onSubmissionCreate` increments `submissionCount`.
11. Toast, then redirect to `/s/{newId}`.

The entry is live immediately. There is no review queue.

### J2 — Returning user finds an entry and saves it

1. `/login` → email + password. Guard resolves `waitForAuthReady()`, then `waitForProfile()`, sees a username, allows the route.
2. `/collections`. Chooses **Poetry**, sorts by **Top Rated**. Each change re-queries (composite index #8).
3. Types a term, presses Enter. Two parallel queries fire (prefix on `searchIndex`, `array-contains` on `searchKeywords`), merged and deduplicated. *Note: the Poetry + Top Rated filters are silently dropped for the search.*
4. Opens a card → `/s/:id`. Submission + own vote load together; comments and favorite status follow.
5. Taps **▲**. UI increments immediately; `voteSubmission` runs a transaction with `FieldValue.increment`. On failure, everything reverses and a "Vote failed" toast appears.
6. Taps **Save** → `privateUsers/{uid}/favorites/{submissionId}` created.
7. Later, `/desk` → **Collection** tab → favorites listed, hydrated in batches of 10.

### J3 — Guest tries to interact

1. Guest opens `/s/:id` — full read access to a published entry, including all comments.
2. Vote arrows are `:disabled`; clicking anyway calls `handleVote`, which routes to `/login`.
3. **Save** → `handleToggleFavorite` sees `isGuest` → `/login`.
4. **Report** → `openReportModal` sees `isGuest` → `/login`.
5. The comment form is replaced by an "Access Required / Authenticate" panel.
6. **Share** works — it needs no auth.
7. Navigating to `/contribute` trips `requiresAuth` → `/login?redirect=/contribute`. After sign-in the user lands back on `/contribute`.

### J4 — Author edits, then deletes their own work

1. `/desk` → **Works** (includes their hidden entries) → open one.
2. Sidebar shows *Author Tools* → **Edit Submission**.
3. Draft is populated from the submission (`origin: 'shared'` → displayed as `attributed`).
4. Save stays disabled until the draft both validates and differs.
5. **Save Changes** → `updateSubmission` callable → owner check → sanitized patch → search fields rebuilt when title/text/meaning/type changed → `updatedAt` + `updatedBy` stamped.
6. Later: **Permanently Delete** → `confirmAction` dialog → client `deleteDoc`.
7. `onSubmissionDelete` decrements `submissionCount` and bulk-deletes `votes`, `comments`, `reports`.
8. Redirect to `/collections`.

### J5 — Community reports content into auto-hiding

1. User A opens a submission, taps **Report**, picks "Abusive or hateful content", adds details, submits.
2. `setDoc` to `submissions/{id}/reports/{A}` — the UID doc ID plus the rules' `!exists()` check make a second report by A impossible. The repo also pre-checks and throws "You already reported this entry."
3. `onReportCreate` runs a transaction: `reportCount: 1`.
4. Users B and C do the same. On C's report, `reportCount` reaches **3** and the submission flips to `status: 'hidden'`, `statusChangedBy: 'system'`, `statusReason: 'auto-report-threshold'`.
5. It disappears from every public listing. Its author can still see it on `/desk`.

### J6 — Admin triages the queue

1. Admin opens the user dropdown; the **Admin** item appears only because `profile.isAdmin === true`.
2. `/admin` loads. Guard checks the same flag. The Submissions tab defaults to the `hidden` filter.
3. Each hidden card shows its open-report count from a `collectionGroup('reports')` query.
4. **Inspect** → `/s/:id`, where the admin sees the *Moderation* panel and can restore or re-hide.
5. Back on `/admin`, the **Reports** tab groups open reports by submission.
6. **Resolve** stamps `status: 'reviewed'`, `reviewedAt`, `reviewedBy`. **Dismiss** stamps `status: 'dismissed'`.
7. The submission's `status` and `reportCount` are untouched. Restoring the submission is a separate, manual step.

### J7 — Cold start with an existing session

1. App boots. `main.ts` mounts; `App.vue` shows the splash.
2. Importing the auth store fires `initAuthListener()`, which awaits `setPersistence(browserLocalPersistence)` then attaches `onAuthStateChanged`.
3. The SDK rehydrates the session from IndexedDB; the callback fires with a user and resolves `authReady`.
4. `profileStore.start(uid)` attaches the profile `onSnapshot`.
5. `App.vue` releases the splash once `authReady` and a 400 ms floor have both elapsed (ceiling 5000 ms).
6. The router guard, already awaiting `authReady`, proceeds; it then awaits `waitForProfile()` and checks for a username.
7. In production, Firestore serves the first paint from `persistentLocalCache`. In dev there is no local cache at all.

### J8 — Offline

1. `window` fires `offline`. `App.vue` shows a dismissible "Connection Lost" card with a "Retry Connection" button that hard-reloads the page.
2. The footer's status pill flips to "SYSTEM OFFLINE" — driven purely by `navigator.onLine`, never by a real Firestore probe.
3. In production, cached reads still resolve from `persistentLocalCache`. Writes queue in the SDK. Callables (`createSubmission`, `voteSubmission`, `claimUsername`, `updateSubmission`) **fail immediately** — `httpsCallable` has no offline queue. The optimistic vote will therefore apply, fail, and roll back with a toast.
4. On `online`, the banner hides and the dismissal state resets.
</content>
