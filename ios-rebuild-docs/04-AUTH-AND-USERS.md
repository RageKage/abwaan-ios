# 04 — Auth and Users

## 1. Login methods that exist

Exactly two. Both live in [client/src/features/auth/auth.store.ts](client/src/features/auth/auth.store.ts).

| Method | API used | Entry point |
|---|---|---|
| Email + password | `createUserWithEmailAndPassword` / `signInWithEmailAndPassword` | [LoginPage.vue](client/src/features/auth/LoginPage.vue) |
| Google | `GoogleAuthProvider` + `signInWithPopup` | [LoginPage.vue:57-71](client/src/features/auth/LoginPage.vue:57) |

## 2. Login methods that do **not** exist

I grepped the whole client for each of these and found zero occurrences. None of the following are implemented anywhere:

| Absent | Firebase API that would appear | Confirmed absent |
|---|---|---|
| Password reset | `sendPasswordResetEmail` | ✓ |
| Email verification | `sendEmailVerification`, `emailVerified` | ✓ |
| Sign in with Apple | `OAuthProvider('apple.com')` | ✓ |
| Phone auth | `signInWithPhoneNumber` | ✓ |
| Anonymous auth | `signInAnonymously` | ✓ |
| Account deletion | `deleteUser` | ✓ |
| Re-authentication | `reauthenticateWithCredential` | ✓ |
| MFA | `multiFactor` | ✓ |
| Redirect-based OAuth | `signInWithRedirect` | ✓ |

There is no "Forgot password?" link on the login page. A user who forgets their password has no in-app recovery path today.

**This matters for the App Store.** Because a third-party social login (Google) is offered, App Store Review Guideline 4.8 requires an equivalent privacy-preserving login option — in practice, Sign in with Apple. It does not exist in the web app, so it is net-new work for iOS and cannot be "ported". Carried into [10-TECH-PLAN.md](ios-rebuild-docs/10-TECH-PLAN.md) and [11-RISKS.md](ios-rebuild-docs/11-RISKS.md) in Phase 2, and raised as a scope question now — see [06-OPEN-QUESTIONS.md](ios-rebuild-docs/06-OPEN-QUESTIONS.md) Q1.

## 3. Full flows

### 3.1 Sign-up (email + password)

```
LoginPage.handleSubmit()  [isRegister = true]
  └─ authStore.register(email, password, displayName)
       ├─ createUserWithEmailAndPassword(auth, email, password)
       │    └─(server, async)─ onAuthUserCreate trigger fires
       │         ├─ profiles/{uid}     ← { displayName, username: null, bio: "",
       │         │                        photoURL, createdAt, lastLoginAt,
       │         │                        submissionCount: 0, isAdmin: false }
       │         └─ privateUsers/{uid} ← { email, providerId, lastLoginAt }
       ├─ if displayName: updateAuthProfile(user, { displayName })
       └─ if displayName: updateProfileDoc(uid, { displayName })   ← client write to profiles/{uid}
  ├─ profileStore.start(uid)          ← attaches onSnapshot
  └─ router.push('/onboarding/username')
```

Two ordering hazards, both real and both visible in the code:

- The client's `updateProfileDoc` write ([auth.store.ts:59](client/src/features/auth/auth.store.ts:59)) races the trigger's `profileRef.set(...)`. Both use `merge: true`, so the outcome is order-dependent but not destructive. The trigger writes `displayName: user.displayName ?? ""`, and `updateAuthProfile` runs immediately before, so the trigger usually observes the name anyway.
- The client's write must satisfy the *create* rule if the trigger has not landed yet, which forbids setting `username` or `isAdmin: true`. It sets neither. It passes.

Notably `register()` does **not** await `waitForProfile()` before navigating, unlike the Google path.

### 3.2 Sign-in (email + password)

```
authStore.login(email, password)
  └─ signInWithEmailAndPassword
       └─ onAuthStateChanged fires → user.value set → profileStore.start(uid)
router.push(route.query.redirect ?? '/')
```

The router guard then intercepts: if `profile.username === null`, it rewrites the destination to `/onboarding/username`.

### 3.3 Sign-in (Google)

```
authStore.loginWithGoogle()
  └─ signInWithPopup(auth, new GoogleAuthProvider())
profileStore.start(credential.user.uid)
await profileStore.waitForProfile()
if (!profile.username) → /onboarding/username
else                   → route.query.redirect ?? '/'
```

Popup, not redirect. On a first-ever Google sign-in the profile document may not exist yet (the trigger is still running); `waitForProfile()` resolves on the first `onSnapshot` delivery, which for a nonexistent doc calls back with `null` ([profiles.repo.ts:26-32](client/src/data/firestore/profiles.repo.ts:26)). `!profile?.username` is then true and the user lands on onboarding, which is the desired outcome.

### 3.4 Username onboarding (mandatory, one-time)

Every authenticated user is trapped on `/onboarding/username` until they claim a handle. There is no skip.

```
UsernameOnboardingPage.handleSubmit()
  └─ claimUsername(trimmed)            → callable
       ├─ checkRateLimit(uid, 'claimUsername', 5, 3600)
       ├─ normalizeUsername → /^[a-z0-9_]{3,20}$/ on the lowercased form
       └─ transaction:
            ├─ if usernames/{lower} exists → HttpsError('already-exists')
            ├─ usernames/{lower} ← { uid, usernameOriginal, createdAt }
            └─ profiles/{uid}    ← { username: usernameOriginal }   [merge]
  └─ router.push('/')
```

A `watch` on `profileStore.profile?.username` with `immediate: true` redirects to `/` the moment the snapshot reports a username, so the page also self-dismisses if the claim landed via another tab ([UsernameOnboardingPage.vue:20-28](client/src/features/onboarding/UsernameOnboardingPage.vue:20)).

The UI states plainly: "This handle is permanent." The rules back that up — `profiles` update requires `request.resource.data.username == resource.data.username` ([firestore.rules:105](firestore.rules:105)).

### 3.5 Sign-out

```
TheNavigation.handleUserAction('logout')
  └─ authStore.logout() → signOut(auth)
       └─ onAuthStateChanged(null) → user.value = null → profileStore.stop()
  └─ router.push('/login')
```

`profileStore.stop()` detaches the snapshot listener and clears profile, submissions, cursor, busy, error, and the readiness promise ([profile.store.ts:43-56](client/src/features/profile/profile.store.ts:43)).

### 3.6 Session persistence

`setPersistence(auth, browserLocalPersistence)` is awaited inside `initAuthListener()` **before** `onAuthStateChanged` is registered ([auth.store.ts:86-107](client/src/features/auth/auth.store.ts:86)). `initAuthListener` is invoked as a side effect of the store's setup function, guarded by a `didInit` flag, and is fire-and-forget (`void initAuthListener()`).

Session survives reload and browser restart. There is no idle timeout, no token-refresh handling beyond the SDK's own, and no explicit `onIdTokenChanged` listener.

### 3.7 Auth readiness contract

```ts
let resolveAuthReady: (() => void) | null = null
const authReady = new Promise<void>((resolve) => { resolveAuthReady = resolve })
```
([auth.store.ts:18-21](client/src/features/auth/auth.store.ts:18))

Module-scoped, resolved exactly once by the **first** `onAuthStateChanged` callback — signed in or not. Two consumers:

- The router guard awaits it before every navigation ([app/router/index.ts:94](client/src/app/router/index.ts:94)).
- `App.vue` awaits it to dismiss the splash screen, with a 400 ms floor and a 5000 ms ceiling ([App.vue:50-56](client/src/App.vue:50)).

The equivalent for profiles, `waitForProfile()`, returns a promise that is **reset on every `start(uid)`** and resolved by the first snapshot ([profile.store.ts:20-41](client/src/features/profile/profile.store.ts:20)). When signed out it is `Promise.resolve()`.

## 4. Roles and permissions

There is exactly one role bit: `profiles/{uid}.isAdmin: boolean`.

### How it is granted

**It cannot be granted from within this codebase.** No callable, no script, no UI writes `isAdmin: true`. The rules forbid clients from doing so on both create and update ([firestore.rules:100-107](firestore.rules:100)), and no Cloud Function sets it. It must be flipped manually in the Firebase console or via a separate Admin SDK invocation. There are no Firebase **custom claims** anywhere in the codebase — `isAdmin` is a plain Firestore field, not a token claim.

### How it is enforced

| Layer | Mechanism | Strength |
|---|---|---|
| Router | `meta.requiresAdmin` + `!profileStore.profile?.isAdmin` → redirect `/` ([app/router/index.ts:114-116](client/src/app/router/index.ts:114)) | Cosmetic. Client-side only. |
| Navigation | Admin link injected into the dropdown only when `isAdmin` ([useNavigation.ts:23-25](client/src/shared/navigation/useNavigation.ts:23)) | Cosmetic. |
| Component | `v-if="isAdmin"` on the moderation panel ([SubmissionDetailPage.vue:988](client/src/features/submissions/SubmissionDetailPage.vue:988)) | Cosmetic. |
| Firestore rules | `isAdmin()` helper does `get(/profiles/$(uid)).data.isAdmin == true` ([firestore.rules:21-25](firestore.rules:21)) | **Authoritative.** |
| Cloud Function | `updateSubmission` re-reads the profile and checks `profile?.isAdmin === true` ([functions/src/index.ts:616-624](functions/src/index.ts:616)) | **Authoritative.** |

Because `isAdmin()` performs a `get()` on every evaluation, it consumes a document read per rule check and contributes to the rules' 10-`get()` budget per request. Worth noting for iOS: the same rules apply, unchanged.

### Effective permission matrix

| Action | Guest | User | Author of the doc | Admin |
|---|---|---|---|---|
| Read published submission | ✓ | ✓ | ✓ | ✓ |
| Read hidden submission | ✗ | ✗ | ✓ | ✓ |
| Read any profile | ✓ | ✓ | ✓ | ✓ |
| Read `usernames` registry | ✓ | ✓ | ✓ | ✓ |
| Create submission | ✗ | ✓ (callable) | — | ✓ |
| Edit submission | ✗ | ✗ | ✓ (callable) | ✓ (callable; **no UI**) |
| Delete submission | ✗ | ✗ | ✓ (direct) | ✓ (rules allow; **no UI**) |
| Hide / restore submission | ✗ | ✗ | ✗ | ✓ |
| Vote | ✗ | ✓ (callable) | ✓ | ✓ |
| Read own vote | ✗ | ✓ | ✓ | ✓ |
| Read someone else's vote | ✗ | ✗ | ✗ | ✗ |
| Comment | ✗ | ✓ (direct) | ✓ | ✓ |
| Edit comment | ✗ | ✗ | ✗ | ✗ (`allow update: if false`) |
| Delete comment | ✗ | ✗ | ✓ (own comment) | ✓ (any) |
| Report submission | ✗ | ✓ once per submission | ✓ | ✓ |
| Read a report | ✗ | ✗ | ✗ (unless reporter) | ✓ |
| Resolve / dismiss report | ✗ | ✗ | ✗ | ✓ |
| Favorite | ✗ | ✓ | ✓ | ✓ |
| Claim username | ✗ | ✓ once | — | ✓ once |

"No UI" rows are cases where the security layer permits the action but no component renders a control for it. Both are admin capabilities on other people's submissions.

An author can read and edit their own **hidden** submission — the read rule includes `isOwner(resource.data.uid)`, and the Desk fetches with `status: 'all'`.

## 5. Emulator behaviour in local dev

### Wiring

[client/src/data/firebase/client.ts:44-52](client/src/data/firebase/client.ts:44):

```ts
if (import.meta.env.DEV && !globalFlags['__firebase_emulators_connected__']) {
  connectFirestoreEmulator(db, '127.0.0.1', 8080)
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true })
  connectFunctionsEmulator(functions, '127.0.0.1', 5001)
  globalFlags['__firebase_emulators_connected__'] = true
}
```

The switch is `import.meta.env.DEV` — Vite's dev-mode flag. There is **no** `VITE_USE_EMULATOR` env var; you cannot point a dev server at production, nor a production build at the emulator, without editing this file. The `globalThis` flag makes the call idempotent across HMR reloads, since the Firebase SDK throws if you connect twice.

`disableWarnings: true` suppresses the Auth emulator's console banner.

### Ports

| Service | Client expects | `firebase.json` declares |
|---|---|---|
| Auth | 9099 | 9099 ✓ |
| Firestore | 8080 | 8080 ✓ |
| Functions | 5001 | **absent** — falls back to the CLI default, which is 5001 |
| RTDB | — | 9000 (unused) |
| Storage | — | 9199 (unused) |
| Emulator UI | — | enabled, default port 4000 |

`singleProjectMode: true` ([firebase.json:27](firebase.json:27)).

### What the Auth emulator gives you

- Accounts are in-memory and vanish when the emulator stops, unless started with `--import` / `--export-on-exit`. No such flags are wired into any npm script.
- Email/password sign-up works with no real email delivery.
- **Google sign-in works** through the emulator's account-chooser popup — it never contacts Google. So the Google path is testable locally.
- `onAuthUserCreate` is a **1st-gen Auth blocking-adjacent background trigger**. The Auth emulator does fire it, but only when the Functions emulator is also running. `firebase.json` has no `functions` emulator block, so a developer running `firebase emulators:start` without `--only ...,functions` gets accounts with **no profile document**, and the router then traps them on `/onboarding/username` with a null profile.

The documented run sequence in [AUDIT_REPORT.md:5-10](AUDIT_REPORT.md:5) is `firebase emulators:start --only auth,firestore,functions`, which does include functions. It also references `docs/Runbook.md`, a file that does not exist in this checkout.

### What is not emulated

Nothing else is used, so nothing else matters: no Storage, no RTDB, no FCM, no App Check, no reCAPTCHA. Note that App Check is **not configured**, which means the callables are open to any client holding the public web API key, rate-limited only by the per-UID `rateLimits` documents.

## 6. Security observations relevant to the rewrite

Recorded as facts, not proposals. Nothing here is being fixed.

1. **The onboarding gate is client-side only.** Nothing in the rules requires a claimed username to write a comment or a report. A client that skips the Vue router can comment with `username: null`. See §3 of [03-DATA-MODEL.md](ios-rebuild-docs/03-DATA-MODEL.md).
2. **`isAdmin` lives in Firestore, not in custom claims.** Every admin rule check costs a `get()`. An iOS client cannot read the admin bit from the ID token; it must read the profile document, exactly as the web client does.
3. **No App Check.** Callables are reachable by any holder of the web API key.
4. **`rateLimits` uses a fixed window**, so up to `2 × maxCalls` requests can land across a window boundary.
5. **Comments and reports are written directly from the client**, so their `createdAt` is device-clock-controlled and their content passes through rules validation only.
6. **`usernames` is world-readable**, so the full list of handles (and their owning UIDs) is enumerable by anyone.
</content>
