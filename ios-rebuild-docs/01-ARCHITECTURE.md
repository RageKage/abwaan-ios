# 01 — Architecture

> Phase 0 audit. Every claim below is cited to a file path. Read-only pass; no existing code was modified.

## 1. Tech stack

### Client (`client/`)

| Concern | Choice | Evidence |
|---|---|---|
| Framework | Vue 3.5 (`<script setup>`, composition API) | [package.json](client/package.json:28) |
| Build tool | Vite 7 | [package.json](client/package.json:48) |
| Language | TypeScript ~5.9, `vue-tsc` for type-check | [package.json](client/package.json:47) |
| Styling | Tailwind CSS 4 via `@tailwindcss/vite` plugin + legacy `@config` directive | [style.css:1](client/src/assets/style.css:1), [vite.config.ts:15](client/vite.config.ts:15) |
| State | Pinia 3, composition-style stores | [main.ts:18](client/src/main.ts:18) |
| Routing | vue-router 4, HTML5 history | [app/router/index.ts:80](client/src/app/router/index.ts:80) |
| Toasts | `vue-sonner` | [App.vue:142](client/src/App.vue:142) |
| Animation | `@vueuse/motion` (`v-motion` directive) | [main.ts:20](client/src/main.ts:20) |
| Smooth scroll | `lenis` | [App.vue:35](client/src/App.vue:35) |
| Icons | `@heroicons/vue` — used on exactly one page | [AdminPage.vue:10](client/src/features/admin/AdminPage.vue:10) |
| PWA | `vite-plugin-pwa` (`registerType: 'autoUpdate'`, Workbox runtime caching) | [vite.config.ts:16-81](client/vite.config.ts:16) |
| Sanitization | `dompurify` | [sanitize.ts:1](client/src/shared/utils/sanitize.ts:1) |
| Fonts | Manrope / Cormorant Garamond / Kalam, loaded from Google Fonts CDN | [index.html:9-12](client/index.html:9) |

**Two imported packages are not declared in `client/package.json` and are absent from `client/package-lock.json`:**

| Package | Imported at | In `package.json`? | In lockfile? |
|---|---|---|---|
| `dompurify` | [sanitize.ts:1](client/src/shared/utils/sanitize.ts:1) | No | No |
| `vite-plugin-pwa` | [vite.config.ts:8](client/vite.config.ts:8) | No | No |

`client/node_modules` is not present in this checkout, so I could not execute a build to confirm the resulting failure mode. Both are hard `import` statements at module scope, so a fresh `npm install && vite build` would fail to resolve them. Flagged in [06-OPEN-QUESTIONS.md](ios-rebuild-docs/06-OPEN-QUESTIONS.md).

One declared dependency, `aos`, has **zero** import sites anywhere under `client/src/`.

### Backend (`functions/`)

| Concern | Choice | Evidence |
|---|---|---|
| Runtime | Node 20 | [functions/package.json:14](functions/package.json:14) |
| SDK | `firebase-functions` ^7, `firebase-admin` ^13 | [functions/package.json:18-19](functions/package.json:18) |
| API generation | **Mixed.** Triggers use v1 (`firebase-functions/v1`), callables use v2 (`firebase-functions/v2/https`) | [functions/src/index.ts:4-5](functions/src/index.ts:4) |
| Build | `tsc` → `lib/`, entry `lib/index.js` | [functions/package.json:15-16](functions/package.json:15) |
| Lint gate | `npm run lint` + `npm run build` run as Firebase `predeploy` | [firebase.json:41-44](firebase.json:41) |

All backend code lives in a single file: [functions/src/index.ts](functions/src/index.ts) (798 lines).

## 2. Folder structure

```
client/
  src/
    main.ts                  App bootstrap: Pinia, router, MotionPlugin, global error handler
    App.vue                  Root shell: splash gate, Lenis, online/offline banner, Toaster, dialog, audio
    app/router/index.ts      Route table (12 routes) + single global beforeEach guard
    assets/                  style.css (Tailwind entry), images, logo, audio, archived SVGs
    data/
      firebase/client.ts     Firebase app init; exports db/auth/functions; emulator wiring
      firestore/*.repo.ts    Repository layer — thin wrappers over the Firestore SDK
      functions/*.ts         Callable wrappers over httpsCallable
      models/*.ts            TypeScript interfaces for the wire format
    features/                One folder per feature area; page components + Pinia store colocated
      admin/ auth/ collections/ desk/ favorites/ home/ onboarding/ profile/ submissions/
    shared/
      components/            SubmissionCard, EmptyState, LoadMore, BaseDropdown, GlobalDialog,
                             AppLoader, AudioPlayer, icons/
      navigation/            TheNavigation → DesktopNav | MobileNav, Footer, SiteLogo, useNavigation.ts
      utils/                 alerts, sanitize, submissions, dbStatus, debug, useDialog
  public/                    favicon, manifest.json, build.json (generated)
  scripts/write-build-date.js  Writes public/build.json on predev/prebuild

functions/
  src/index.ts               Every trigger + callable
  scripts/seed-submissions.cjs  Admin-SDK seeding script (--uid, --file, --project)

firestore.rules              Security rules
firestore.indexes.json       12 submissions composite + 2 reports collection-group indexes
storage.rules                Deny-all
firebase.json                Emulator ports, hosting, functions codebase
.firebaserc                  Default project: project-abwaan-dev-v2
TEST_SUBMISSIONS.json        12-record seed fixture
```

Note: project `CLAUDE.md` documents the router at `client/src/router/index.ts`. It actually lives at [client/src/app/router/index.ts](client/src/app/router/index.ts).

## 3. How the app boots

1. [index.html](client/index.html) loads `/src/main.ts` as a module and provides `<div id="app">`.
2. [main.ts](client/src/main.ts) creates the app, installs Pinia → router → MotionPlugin, sets `app.config.errorHandler` to log and surface a toast, then mounts.
3. [App.vue](client/src/App.vue) mounts and, in `onMounted`:
   - initialises Lenis smooth scroll (`autoRaf: true`),
   - registers `online`/`offline` listeners,
   - **gates the splash screen on auth readiness**: races `Promise.all([waitForAuthReady(), 400 ms floor])` against a 5000 ms ceiling, then clears `isLoading` ([App.vue:46-58](client/src/App.vue:46)).
4. Importing [auth.store.ts](client/src/features/auth/auth.store.ts) has a side effect: `void initAuthListener()` runs at store-definition time ([auth.store.ts:109](client/src/features/auth/auth.store.ts:109)). That call awaits `setPersistence(auth, browserLocalPersistence)` and then registers `onAuthStateChanged`, which resolves the module-scoped `authReady` promise on first fire.

`App.vue` conditionally hides chrome: nav is hidden on `/login` and `/onboarding/username`; the footer is hidden on both as well ([App.vue:16-19](client/src/App.vue:16)).

## 4. How routing works

Twelve routes, every one lazy-loaded via dynamic `import()` ([app/router/index.ts:5-77](client/src/app/router/index.ts:5)). `scrollBehavior` restores saved position or scrolls to top.

A single `beforeEach` guard ([app/router/index.ts:91-119](client/src/app/router/index.ts:91)) runs this sequence:

1. `await authStore.waitForAuthReady()` — blocks until Firebase Auth has reported once.
2. `meta.requiresAuth` && not signed in → redirect `/login?redirect=<fullPath>`.
3. `meta.guestOnly` && signed in → redirect `/`.
4. If signed in and the target is neither the onboarding route nor `/login*`: `await profileStore.waitForProfile()`, then **if the profile is missing or `username === null`, redirect to `/onboarding/username`.** This is a hard gate — an authenticated user without a claimed username cannot reach any other page.
5. `meta.requiresAdmin` && `!profile.isAdmin` → redirect `/`.

Route meta in use: `requiresAuth`, `guestOnly`, `requiresAdmin`.

## 5. How state is managed

Seven Pinia composition-style stores. Data flow:

```
Page component → Pinia store → data/firestore/*.repo.ts → Firestore SDK
                            └→ data/functions/*.ts      → httpsCallable → Cloud Function
```

| Store | File | Responsibility |
|---|---|---|
| `auth` | [auth.store.ts](client/src/features/auth/auth.store.ts) | Firebase user, register/login/Google/logout, `waitForAuthReady()` |
| `profile` | [profile.store.ts](client/src/features/profile/profile.store.ts) | Own profile via `onSnapshot`, own submissions, `waitForProfile()` |
| `submissions` | [submissions.store.ts](client/src/features/submissions/submissions.store.ts) | List/search/detail/create/update/status/vote/delete |
| `comments` | [comments.store.ts](client/src/features/submissions/comments.store.ts) | Comment list + add + remove |
| `favorites` | [favorites.store.ts](client/src/features/favorites/favorites.store.ts) | Saved submissions, per-item `togglingIds` |
| `reports` | [reports.store.ts](client/src/features/admin/reports.store.ts) | Admin report queue |
| `publicProfile` | [publicProfile.store.ts](client/src/features/profile/publicProfile.store.ts) | Another user's profile + their submissions |

Patterns worth carrying to iOS:

- **Promise-based readiness.** `authReady` is a module-scoped promise resolved by the first `onAuthStateChanged` callback ([auth.store.ts:18-21](client/src/features/auth/auth.store.ts:18)). `waitForProfile()` returns a promise reset on each `start(uid)` and resolved by the first `onSnapshot` delivery ([profile.store.ts:20-41](client/src/features/profile/profile.store.ts:20)).
- **Exactly one realtime listener** in the whole app: the signed-in user's own profile document ([profiles.repo.ts:24](client/src/data/firestore/profiles.repo.ts:24)). Everything else is one-shot `getDoc`/`getDocs`.
- **Optimistic vote with rollback** ([submissions.store.ts:224-281](client/src/features/submissions/submissions.store.ts:224)).
- **Cursor pagination** using `QueryDocumentSnapshot` + `startAfter`, held in `shallowRef` so Vue does not deeply proxy the snapshot.
- **Dual-query search** with independent exhaustion flags per query ([submissions.repo.ts:187-269](client/src/data/firestore/submissions.repo.ts:187)).

## 6. Firebase initialization — prod vs emulator

All in [client/src/data/firebase/client.ts](client/src/data/firebase/client.ts).

**Config** reads only three env vars:

```ts
apiKey:     import.meta.env.VITE_FIREBASE_API_KEY
authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN
projectId:  import.meta.env.VITE_FIREBASE_PROJECT_ID
```

[client/.env.example](client/.env.example) additionally lists `VITE_FIREBASE_STORAGE_BUCKET`, `VITE_FIREBASE_MESSAGING_SENDER_ID`, `VITE_FIREBASE_APP_ID`, and `VITE_API_URL`. None of the four are read anywhere in `client/src/`.

**Firestore construction branches on `import.meta.env.DEV`** ([client.ts:20-38](client/src/data/firebase/client.ts:20)):

- Dev → plain `getFirestore()`. No local cache; the comment states emulators are in-memory so persistence is unnecessary.
- Prod → `initializeFirestore(app, { localCache: persistentLocalCache({ tabManager: persistentMultipleTabManager() }) })`, wrapped in try/catch that falls back to `getFirestore()` if Firestore was already initialised.

**Emulator wiring** is DEV-only and idempotent via a `globalThis` flag ([client.ts:44-52](client/src/data/firebase/client.ts:44)):

| Service | Host:port hard-coded in client | Declared in `firebase.json`? |
|---|---|---|
| Firestore | `127.0.0.1:8080` | Yes — `8080` |
| Auth | `http://127.0.0.1:9099` | Yes — `9099` |
| Functions | `127.0.0.1:5001` | **No `functions` emulator block exists** |

[firebase.json:11-28](firebase.json:11) declares emulators for `auth`, `firestore`, `database` (9000), `storage` (9199), and `ui`, with `singleProjectMode: true`. There is no `functions` entry, so the Functions emulator falls back to its default port, which happens to be 5001 — the client's hard-coded value. It works, but the port is undeclared. Neither `database` (RTDB) nor `storage` is used by any client code.

Hosting serves `client/dist` with an SPA catch-all rewrite to `/index.html`, and sends `Cache-Control: no-cache` for `/build.json` ([firebase.json:47-71](firebase.json:47)).

Default project: `project-abwaan-dev-v2` ([.firebaserc:3](.firebaserc:3)). Firestore database `(default)`, location `us-west2` ([firebase.json:2-7](firebase.json:2)).

## 7. Backend surface

### Callables (v2 `onCall`)

| Name | Rate limit | Purpose |
|---|---|---|
| `claimUsername` | 5 / 3600 s | Atomically reserve `usernames/{lower}` and stamp `profiles/{uid}.username` |
| `createSubmission` | 10 / 3600 s | Full server-side validation, builds search fields, writes the doc |
| `updateSubmission` | 30 / 3600 s | Owner-or-admin edit, re-derives search fields |
| `voteSubmission` | 60 / 60 s | Transactional vote with `FieldValue.increment` counters |

Rate limiting is a Firestore transaction against `rateLimits/{uid}_{action}` holding `{ count, windowStart }`; exceeding the window throws `resource-exhausted` ([functions/src/index.ts:14-42](functions/src/index.ts:14)).

### Triggers (v1)

| Name | Type | Effect |
|---|---|---|
| `onAuthUserCreate` | `auth.user().onCreate` | Creates `profiles/{uid}` (username `null`, `isAdmin: false`) and `privateUsers/{uid}` |
| `onSubmissionCreate` | `submissions/{id}` onCreate | `submissionCount += 1` on author profile |
| `onSubmissionDelete` | `submissions/{id}` onDelete | `submissionCount -= 1`; `bulkWriter`-deletes `votes`, `comments`, `reports` subcollections |
| `onReportCreate` | `submissions/{id}/reports/{uid}` onCreate | Increments `reportCount`; at ≥ 3 reports auto-sets `status: 'hidden'`, `statusChangedBy: 'system'`, `statusReason: 'auto-report-threshold'` |

`buildSubmissionSearchFields` exists only in [functions/src/index.ts:128-178](functions/src/index.ts:128) — the client never derives search fields. This is the single source of truth.

There are **no scheduled functions**, no HTTP (non-callable) endpoints, and no Pub/Sub triggers.

## 8. Third-party services beyond Firebase

| Service | Usage | Evidence |
|---|---|---|
| Google Fonts CDN | Stylesheet `<link>` + Workbox `CacheFirst` runtime caching | [index.html:9](client/index.html:9), [vite.config.ts:52-75](client/vite.config.ts:52) |
| Google Sign-In | Via Firebase Auth `GoogleAuthProvider` + `signInWithPopup` — not a separate SDK | [auth.store.ts:70-76](client/src/features/auth/auth.store.ts:70) |

Nothing else. No analytics, no crash reporting, no Sentry, no Stripe, no push/FCM, no Cloud Storage.

Note: [vite.config.ts:38](client/vite.config.ts:38) configures Workbox `CacheFirst` for `firebasestorage.googleapis.com`, but no code uploads to or reads from Storage, and [storage.rules](storage.rules:9) is `allow read, write: if false`. Speculative config.

## 9. Build & version metadata

- `predev` / `prebuild` run [scripts/write-build-date.js](client/scripts/write-build-date.js), producing `client/public/build.json`.
- `__APP_VERSION__` is a Vite `define` sourced from `client/package.json.version` ([vite.config.ts:83-87](client/vite.config.ts:83)); declared in [client/src/env.d.ts](client/src/env.d.ts). Rendered in the footer and mobile nav.
- `/build.json` is fetched at runtime only by [RoadmapPage.vue:20](client/src/features/home/RoadmapPage.vue:20).
- Manual chunking splits `vue-vendor`, `firebase`, and `ui-libs` ([vite.config.ts:96-100](client/vite.config.ts:96)).

## 10. Testing

No test framework, no test files, no CI config anywhere in the repository.
</content>
</invoke>
