# 08 — Navigation Architecture

> Phase 1. Depends on the decisions in [07-DESIGN-TRANSLATION.md](ios-rebuild-docs/07-DESIGN-TRANSLATION.md). If you veto items there, this changes.
>
> **Revised 2026-07-10**: the `PendingAction` replay mechanism (§4) is now a named component that survives the username gate.

## 1. The shape of the app

Four tabs. One of them is a search role. No tab appears or disappears based on who you are.

```
TabView
├── Tab  "Archive"   books.vertical         → NavigationStack
├── Tab  "Desk"      tray.full              → NavigationStack        [auth-gated content]
├── Tab  "You"       person.crop.circle     → NavigationStack
└── Tab  role:.search, "Search"  magnifyingglass → NavigationStack
    .tabViewBottomAccessory { AmbientAudioControl }
    .tabBarMinimizeBehavior(.onScrollDown)
```

**Why four and not five.** Contribute is not a tab (it is a task, presented modally). Admin is not a tab (it is role-gated, and tab bars must be stable). Home is deleted. That leaves the three genuine *places* in this app — the public archive, your own stuff, and you — plus search, which the latest SDK gives a first-class tab role.

**Why Desk is a tab even though it requires auth.** It is a destination the user returns to, and signed-out users are the minority case. The tab is always present; its *content* is a sign-in prompt when signed out. Hiding the tab would be the mutation problem in reverse.

## 2. Tab-by-tab

### Tab 1 — Archive

```
NavigationStack(path: $archivePath)
└── ArchiveList                                    [root]
    ├── toolbar: [Filter Menu] [+ Compose]
    ├── swipeActions: Save / Unsave
    └── navigationDestination
        ├── .submission(id)  → SubmissionDetail
        └── .profile(uid)    → PublicProfile
```

`ArchiveList` is a `List` of published submissions, default sort `createdAt desc`, infinite scroll. The filter `Menu` holds type, language, and sort. `+` presents `ContributeSheet` as a `.fullScreenCover`.

### Tab 2 — Desk

```
NavigationStack(path: $deskPath)
└── DeskView                                       [root]
    ├── if signedOut → SignInPrompt (inline, not a sheet)
    └── if signedIn
        ├── Picker(.segmented): Works | Collection
        ├── Works       → own submissions, status: all, hidden badge
        ├── Collection  → favorites, swipe-to-unsave
        ├── toolbar: [+ Compose]
        └── navigationDestination → .submission(id) | .profile(uid)
```

### Tab 3 — You

```
NavigationStack(path: $youPath)
└── SettingsView                                   [root, a Form]
    ├── if signedOut → "Sign In" row → presents AuthSheet
    ├── Profile     → Display Name, Bio, @username (read-only)
    ├── Moderation  → [visible iff isAdmin] → push ModerationQueue
    ├── About       → push AboutView
    │                → push RoadmapView
    └── Sign Out    (.destructive, confirmationDialog)
```

### Tab 4 — Search

```
NavigationStack(path: $searchPath)
└── SearchResults                                  [root]
    ├── .searchable(text:), .searchScopes(All | Proverbs | Poetry)
    ├── .searchToolbarBehavior(.minimize)
    └── navigationDestination → .submission(id) | .profile(uid)
```

## 3. Modal versus push

The rule I applied: **push when it's a place you came from somewhere to see; present when it's a task you'll finish and leave.**

| Screen | Presentation | Detents | Dismissible |
|---|---|---|---|
| Submission Detail | **push** | — | back |
| Public Profile | **push** | — | back |
| Moderation Queue | **push** | — | back |
| About / Roadmap | **push** | — | back |
| Contribute | `.fullScreenCover` | — | Cancel, with unsaved-changes confirm |
| Edit Submission | `.fullScreenCover` | — | Cancel, with unsaved-changes confirm |
| Comments | `.sheet` | `[.medium, .large]` | swipe |
| Sign In / Register | `.sheet` | `[.medium]` | swipe |
| Report | `.sheet` | `[.medium]` | swipe |
| **Username Onboarding** | `.fullScreenCover` | — | **`.interactiveDismissDisabled()`** |
| Delete confirm | `.confirmationDialog` | — | — |
| Hide / Restore confirm | `.confirmationDialog` | — | — |
| Share | `ShareLink` (system) | — | — |

Contribute and Edit are full-screen covers rather than sheets because they are long multi-section forms with a keyboard, and a `.large` sheet with a drag-to-dismiss gesture invites accidental data loss.

## 4. The auth gate

**The app never opens on a login wall.** Guests read everything published, including comments — that is the site's behaviour ([firestore.rules:99](firestore.rules:99), [:129](firestore.rules:129)) and it is correct.

There are three auth states, and only the third is a gate.

```
┌─ signedOut ──────────────────────────────────────────────┐
│  Archive: full read access                               │
│  Search:  full read access                               │
│  Detail:  read; vote/save/report/comment → AuthSheet     │
│  Desk:    inline SignInPrompt                            │
│  You:     "Sign In" row                                  │
└──────────────────────────────────────────────────────────┘
                          │ signs in
                          ▼
┌─ signedIn, username == nil ──────────────────────────────┐
│  UsernameOnboarding, .fullScreenCover                    │
│  .interactiveDismissDisabled()                           │
│  Only escape: claim a handle, or sign out                │
└──────────────────────────────────────────────────────────┘
                          │ claims handle
                          ▼
┌─ signedIn, username != nil ──────────────────────────────┐
│  Everything. Moderation section iff isAdmin.             │
└──────────────────────────────────────────────────────────┘
```

**Action-triggered auth, not route-triggered.** On the web, tapping "Save" as a guest calls `router.push('/login')` — you lose the submission you were reading. Here, it presents a `.medium` sheet over the detail screen. Sign in, the sheet dismisses, **the pending action completes**, and you are still exactly where you were. That last clause is the whole point; it should be an explicit requirement in the tech plan.

**The pending action must survive the username gate** (13 §B1). Sign-in can land in `needsUsername`, which presents the onboarding cover above everything. The sequence is: tap vote → AuthSheet → sign in → onboarding cover → claim handle → **then** the vote lands. So the mechanism is an explicit `PendingAction` enum held on `SessionModel`, replayed on the transition into `.active` — never on sheet dismiss. The same mechanism serves the `/contribute` deep link while signed out. This is a named component in the tech plan, not four ad-hoc closures.

The onboarding cover is presented from the root, above the `TabView`, not from within a tab — otherwise it would be dismissible by switching tabs.

## 5. Deep links

The site's URL scheme maps cleanly. Universal Links, `applinks:` associated domain, plus a `abwaan://` custom scheme for internal use.

| Web URL | iOS route | Auth | Notes |
|---|---|---|---|
| `/` | Archive root | — | |
| `/collections` | Archive root | — | Same destination |
| `/s/:id` | Archive → Detail(id) | — | **The one that matters.** `ShareLink` emits this. |
| `/p/:uid` | Archive → Profile(uid) | — | |
| `/contribute` | Archive → Contribute cover | ✓ | Signed out → AuthSheet first, then present |
| `/desk` | Desk tab | ✓ | |
| `/settings` | You tab | ✓ | |
| `/admin` | You → Moderation | ✓ + admin | Non-admin → You root, silently |
| `/about` | You → About | — | |
| `/roadmap` | You → About → Roadmap | — | |
| `/onboarding/username` | — | — | **Not deep-linkable.** State-driven only. |
| `/login` | — | — | **Not deep-linkable.** Presented, never routed to. |
| unknown | Archive root | — | No 404 screen; there are no URLs to mistype |

**A shared link must open the submission.** `abwaan.app/s/abc123` → cold launch → Archive tab selected → `archivePath = [.submission("abc123")]`. If the submission is hidden or deleted, show `ContentUnavailableView`, not an empty push.

**Deleted:** the 404 screen ([NotFoundPage.vue](client/src/features/home/NotFoundPage.vue)). An app has no address bar. A bad deep link resolves to the Archive root; a missing *document* is an empty state on the screen that tried to load it. Those are different problems and the web conflated them.

## 6. Navigation state

Each tab owns its own `NavigationPath`. Switching tabs preserves each stack. This is standard and it is what users expect — the web app, being a browser, could not do it.

```swift
enum Route: Hashable {
    case submission(String)
    case profile(String)
    case moderation
    case about
    case roadmap
}
```

One `Route` enum, one `navigationDestination(for: Route.self)` per stack. Detail and Profile are reachable from three stacks (Archive, Desk, Search), so the enum is shared and each stack declares the same destinations.

**Tapping a tab's icon while already at its root scrolls to top.** Tapping while pushed pops to root. Both are free from `TabView` + `NavigationStack` and both are expected.

## 7. Full screen tree

```
AbwaanApp
└── RootView
    ├── TabView  ─────────────────────────────────────────────  glass, minimizes on scroll
    │   │
    │   ├── [Archive]  NavigationStack
    │   │   └── ArchiveList ······················· List, opaque rows
    │   │       ├── toolbar ▸ Filter Menu ········· glass
    │   │       ├── toolbar ▸ + Compose ··········· glass
    │   │       ├── swipe ▸ Save / Unsave
    │   │       ├── → SubmissionDetail(id)
    │   │       │     ├── bottomBar ▸ ▲ score ▼ · bookmark · share · comments   ← glass
    │   │       │     ├── nav ▸ ellipsis Menu ····· glass
    │   │       │     │     ├── Report ··········· → sheet [.medium]
    │   │       │     │     ├── Edit ············· → fullScreenCover   [author]
    │   │       │     │     ├── Hide / Restore ··· → confirmationDialog [admin]
    │   │       │     │     └── Delete ··········· → confirmationDialog [author]
    │   │       │     ├── comments ·············· → sheet [.medium, .large]
    │   │       │     │     ├── composer ········· glass, above keyboard
    │   │       │     │     └── swipe ▸ Delete
    │   │       │     └── → PublicProfile(uid)
    │   │       └── → PublicProfile(uid)
    │   │
    │   ├── [Desk]  NavigationStack
    │   │   └── DeskView
    │   │       ├── signedOut → SignInPrompt → AuthSheet
    │   │       ├── Picker ▸ Works | Collection
    │   │       ├── Works ▸ own submissions (incl. hidden, badged)
    │   │       ├── Collection ▸ favorites, swipe ▸ Unsave
    │   │       ├── toolbar ▸ + Compose
    │   │       └── → SubmissionDetail | PublicProfile
    │   │
    │   ├── [You]  NavigationStack
    │   │   └── SettingsView  (Form)
    │   │       ├── signedOut → Sign In row → AuthSheet
    │   │       ├── Profile ▸ Display Name · Bio · @username
    │   │       ├── Moderation ▸ [iff isAdmin]
    │   │       │     └── → ModerationQueue
    │   │       │           ├── Picker ▸ Submissions | Reports
    │   │       │           ├── toolbar ▸ Status Menu
    │   │       │           ├── Submissions ▸ swipe ▸ Hide / Restore
    │   │       │           ├── Reports ▸ DisclosureGroup, swipe ▸ Dismiss / Resolve
    │   │       │           └── → SubmissionDetail
    │   │       ├── About
    │   │       │     ├── → AboutView
    │   │       │     └── → RoadmapView
    │   │       └── Sign Out ▸ confirmationDialog
    │   │
    │   ├── [Search]  NavigationStack  ·············· role: .search
    │   │   └── SearchResults
    │   │       ├── .searchable · .searchScopes(All | Proverbs | Poetry)
    │   │       └── → SubmissionDetail | PublicProfile
    │   │
    │   └── bottomAccessory ▸ AmbientAudioControl ··· glass, opt-in, off by default
    │
    ├── fullScreenCover ▸ ContributeForm ············ from Archive / Desk toolbars
    │
    └── fullScreenCover ▸ UsernameOnboarding ········ presented above TabView
          .interactiveDismissDisabled()               state-driven, not routed
```

## 8. What each screen loads

Carried from [05-SCREENS-AND-FLOWS.md](ios-rebuild-docs/05-SCREENS-AND-FLOWS.md), restated as iOS lifecycle.

| Screen | On appear | Notes |
|---|---|---|
| ArchiveList | page 1 (published, sorted) | `.task`, cancelled on disappear |
| SearchResults | nothing until a query | debounced |
| SubmissionDetail | submission + own vote, in parallel | favorite status if signed in |
| Comments sheet | page 1 of comments | only when the sheet opens — the web loads them eagerly with the detail page |
| Desk › Works | page 1, `status: all` | |
| Desk › Collection | favorites + hydration | |
| PublicProfile | profile + published works, parallel | |
| SettingsView | nothing — profile is already streaming | |
| ModerationQueue | page 1, paginated (site does not paginate) | |

**Comments now load lazily.** The web fetches 12 comments on every detail view whether or not the user scrolls to them ([SubmissionDetailPage.vue:246](client/src/features/submissions/SubmissionDetailPage.vue:246)). Moving them into a sheet means we fetch on open. That is a real read-cost reduction and it falls out of the design for free.

## 9. Consequences worth naming

- **`waitForAuthReady()` has no iOS equivalent, and needs none.** The web blocked every route transition on a promise because the router had to make a synchronous redirect decision. SwiftUI renders a signed-out Archive immediately and updates when auth resolves. No splash, no gate, no promise.
- **The `guestOnly` route meta disappears.** Login is a sheet; a signed-in user cannot navigate to it.
- **The `requiresAuth` route meta disappears.** Replaced by action-triggered auth and inline prompts.
- **The `requiresAdmin` route meta becomes a Settings section visibility check** plus, more importantly, server-side rules. The site's guard was cosmetic; so is this one. Authority lives in the rules and the callables ([04-AUTH-AND-USERS.md](ios-rebuild-docs/04-AUTH-AND-USERS.md) §4).
- **`isAdmin` is read before the Moderation row can render.** If it moves to a custom claim (proposed in Q-resolution), it arrives with the ID token and there is no extra read at all.
</content>
