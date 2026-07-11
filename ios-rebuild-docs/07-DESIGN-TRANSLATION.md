# 07 — Design Translation

> Phase 1. No code. Target: latest iOS SDK, SwiftUI, Liquid Glass.
>
> **Revised 2026-07-10** per [13-REVIEW-AND-REVISIONS.md](ios-rebuild-docs/13-REVIEW-AND-REVISIONS.md): share-as-image card added (§1.4, veto item 27), Sign in with Apple slot filled at M11 (§1.10, item 28), §4 open items resolved.
>
> Every **RESTRUCTURE**, **CUT**, and **MERGE** is tagged so you can veto it individually. Nothing here adds a feature the site does not have.

## 0. Two principles I am applying throughout

**Liquid Glass is a property of the navigation layer, not the content layer.** Glass belongs on things that float above your content and let it show through: tab bars, toolbars, sheets, floating buttons, the audio accessory. It does not belong on a poem. Somali poetry is the entire point of this app, and rendering long-form serif text on a translucent, blurring, refracting surface is a legibility failure. Content sits on opaque `Color(.systemBackground)`. Chrome floats in glass above it. I hold this line on every screen below.

**The web app's layout is a desktop grid, and almost none of it survives contact with a phone.** The site is built on 12-column grids, three-across card walls, and 8/4 content-plus-sidebar splits. On a 393-point-wide screen, a three-column grid is one column, and a sidebar is not a sidebar. Wherever I say "RESTRUCTURE," it is usually this: the grid was load-bearing on desktop and is meaningless on iPhone.

An important consequence, stated once: **the site's card grid becomes a `List`.** Nine of twelve screens are affected. `SubmissionCard` renders as a full-bleed row with a serif headline, not a bordered tile.

---

## 1. Screen-by-screen

### 1.1 `/` Home → **CUT as a screen**

**Web:** an 85vh marketing hero ("Abwaan", "Preserving Heritage"), two static category blurbs, a random archival photo with attribution, then the three most recent submissions ([HomePage.vue](client/src/features/home/HomePage.vue)).

**iOS:** none of this exists. A marketing landing page is a website's job — it converts a stranger who arrived from a link. Someone who has installed your app has already converted. Apple's own apps have no equivalent; you do not launch Books into a pitch for reading.

- **CUT** the hero, the "Preserving Heritage" pill, and the Gabay/Maahmaahyo blurb cards. The mission copy already lives on `/about` and moves to Settings → About.
- **CUT** the random archival photo gallery. Eight hard-coded images with attribution strings are editorial furniture, not a feature. *(If you want them, they belong in About as a gallery, not on a launch surface. Say the word.)*
- **MERGE** "3 most recent submissions" into the Archive tab, which already sorts by `createdAt desc` by default. Home was showing a truncated view of Archive.

**Net:** the app launches into Archive. **Flag this one hard — it is the largest single cut in the document.**

---

### 1.2 `/collections` Archive → **Tab 1, `NavigationStack` + `List`**

The primary surface. Everything the site's filter bar does, done natively.

**Native pattern:** `NavigationStack` containing a `List` of submissions, with `.searchable` promoted to a dedicated search tab (§1.3).

| Web control | iOS translation | Why |
|---|---|---|
| Type tabs (All / Proverbs / Poetry) | **Search scopes** when searching; a `Picker` in the toolbar menu otherwise | Segmented controls pinned above a list eat vertical space permanently. A toolbar `Menu` costs one tap and zero pixels. |
| Language dropdown | Row inside the same toolbar filter `Menu` | |
| Sort dropdown (Newest / Top Rated) | Row inside the same toolbar filter `Menu`, with `Picker(selection:)` showing a checkmark | Native menus already render selection state; `BaseDropdown`'s 200 lines of ARIA and roving-tabindex code (see [BaseDropdown.vue](client/src/shared/components/BaseDropdown.vue)) evaporate entirely. |
| "Load Next Batch" button | **Infinite scroll** — `.task` on the last row triggers the next page | iOS convention. The button is a web affordance for people who fear scroll hijacking. |
| Filter bar that hides on scroll (broken — see [02-FEATURES.md](ios-rebuild-docs/02-FEATURES.md) B2) | `.tabBarMinimizeBehavior(.onScrollDown)` on the `TabView` | The system does this correctly, for free, with the glass tab bar shrinking to a pill as you scroll. The web version computed `isFilterBarVisible` and never bound it to anything. |
| 3-column card grid | Single-column `List`, `.listStyle(.plain)` | **RESTRUCTURE.** On iPad, a `NavigationSplitView` with a two-column grid in the detail pane is defensible. Phone-first for now. |
| 6 skeleton cards while loading | `.redacted(reason: .placeholder)` on 6 real rows | |
| `EmptyState` component | `ContentUnavailableView` | Three variants already exist on the web (searching / filtering / neither). `ContentUnavailableView.search(text:)` covers one of them out of the box. |

**Liquid Glass on this screen:**
- Tab bar: system glass. Minimizes on scroll-down.
- Navigation bar: system glass, with `.scrollEdgeEffectStyle(.soft, for: .top)` so serif headlines dissolve into the bar rather than colliding with it.
- Toolbar filter button: `.buttonStyle(.glass)`, grouped with any sibling toolbar buttons inside a `ToolbarSpacer(.fixed)` so they read as one glass capsule.
- **Glass-free:** every list row. Poetry and proverb text render on opaque background.

**Filters + search now actually compose.** On the web these are mutually exclusive — selecting Poetry then searching silently searches everything ([02-FEATURES.md](ios-rebuild-docs/02-FEATURES.md) B2, and Q5). Native search scopes make that behaviour indefensible, because the scope bar is *right there* showing "Poetry" while returning proverbs. Since the schema is now free, search respects scope. **This is a behaviour change from the site — flagged, and it is the one place I think the site is simply wrong.**

---

### 1.3 Search → **Tab with `role: .search`** *(new native surface, same feature)*

**Web:** an `<input>` in the filter bar, submitted on Enter.

**iOS:** a dedicated `Tab(value: .search, role: .search)`. On the latest SDK this renders as a distinct search affordance in the glass tab bar that expands into a full search field when tapped, morphing rather than pushing.

- Search field placement `.toolbar`, with `.searchToolbarBehavior(.minimize)`.
- Scopes: **All / Proverbs / Poetry**, via `.searchScopes`.
- Debounced as you type. The site debounced in an unused component ([SearchBar.vue](client/src/features/collections/SearchBar.vue), zero call sites) and used Enter-to-submit instead.
- Empty state: `ContentUnavailableView.search(text:)`.

**On the search backend.** The site's dual-query hack — a prefix range on `searchIndex` plus `array-contains` on a 60-token `searchKeywords` array, merged client-side — exists only because Firestore has no full-text search. It has real, visible failure modes: `searchIndex` means *title* for Poetry but *text* for Proverbs, so prefix search behaves differently per type; and multi-word queries can never hit the `array-contains` branch because the term is never tokenized.

Three options for Phase 2, in ascending cost. **I am not choosing this for you:**

1. **Port the dual query as-is.** Cheapest. Inherits every flaw.
2. **Keep it, but scope it properly** (`type` and `language` as query predicates). Needs new composite indexes. Fixes Q5, keeps the tokenization weakness.
3. **Firestore + a real index** (Algolia, Typesense, or Firestore's vector/full-text extensions). Correct, adds a dependency and probably a cost.

This lands in [10-TECH-PLAN.md](ios-rebuild-docs/10-TECH-PLAN.md).

---

### 1.4 `/s/:id` Submission Detail → **push onto the stack; sidebar dissolves**

The site's 1,158-line monster ([SubmissionDetailPage.vue](client/src/features/submissions/SubmissionDetailPage.vue)). It does eight jobs in one file: read, edit, vote, favorite, report, share, moderate, delete — plus comments. It is the screen most improved by translation.

**Native pattern:** `NavigationStack` push. `ScrollView` of content. All actions leave the body and go into chrome.

**The 8/4 content + sidebar grid is deleted.** Here is where each sidebar block goes:

| Web sidebar block | iOS home | Pattern |
|---|---|---|
| "Archived By" author card | Inline row directly under the title | Tappable, pushes `/p/:uid`. Not chrome — it is content. |
| "Community Validation" vote widget | **Bottom glass toolbar**: `▲ · score · ▼` | `.toolbar { ToolbarItemGroup(placement: .bottomBar) }`. Always reachable with a thumb; never scrolls away. |
| Share ID | Bottom toolbar → `ShareLink` | **RESTRUCTURE.** The web copies a URL to the clipboard through a three-tier fallback ending in `window.prompt` ([SubmissionDetailPage.vue:265-297](client/src/features/submissions/SubmissionDetailPage.vue:265)). `ShareLink` replaces all of it and gives AirDrop, Messages, and Markup for free. Requires a Universal Link — see [08-NAVIGATION-ARCHITECTURE.md](ios-rebuild-docs/08-NAVIGATION-ARCHITECTURE.md). **ADDITION (13 §D2): a share-as-image quote card ships alongside the URL.** `ImageRenderer` renders the detail screen's existing serif typography — the text, the handle, the app name — into an image attached to the same `ShareLink`. For a proverb-and-poetry archive, quote cards on WhatsApp/X/Instagram *are* the growth loop, and an image survives even where a link dies (R13). It is a small component, not a feature: the typography it renders already exists at M3. |
| Save (favorite) | Bottom toolbar, `bookmark` / `bookmark.fill` | Plus a **swipe action** on the list row in Archive, so saving never requires opening the item. |
| Report | Overflow `Menu` (`ellipsis.circle`) in the nav bar | Destructive-adjacent, low frequency. Does not deserve a permanent button. |
| Author Tools → "Edit Submission" | Overflow `Menu` → "Edit" | |
| Moderation → Hide / Restore | Overflow `Menu`, role-gated section | |
| Danger zone → "Permanently Delete" | Overflow `Menu`, `role: .destructive` | Confirmed with `.confirmationDialog`, not a custom modal. |

**Result:** the entire right-hand column becomes one bottom glass toolbar (vote, save, share) plus one nav-bar overflow menu (report, edit, hide, delete). This is the single biggest structural win in the port.

**Content rendering** stays faithful, and stays glass-free:
- Proverb: `text` as the serif headline.
- Poetry: `title` as headline, `text` as an indented verse block preserving line breaks.
- Optional sections: Interpretation (`meaning`), English Translation (`translation`), Historical Reference (`source`, only when `origin != original`) — the latter as a `GroupBox` or a distinct opaque card.
- The site's `/// INTERPRETATION` mono-caps labels become plain `.caption` section headers. **CUT** the ASCII-slash motif; it is a web aesthetic that reads as a rendering bug on iOS.

**Liquid Glass:** bottom toolbar and nav bar only, both system-provided. The verse block is opaque. Reading is the job.

**Comments — RESTRUCTURE.** On the web, comments live in a second full-width section below the fold, inside a `max-h-[520px]` inner scroll container ([CommentList.vue:54](client/src/features/submissions/CommentList.vue:54)). A scrolling region inside a scrolling page is an iOS antipattern and fights the gesture system.

- Comment **count** becomes a button in the bottom toolbar (`bubble.left` + count).
- Tapping presents comments in a **sheet** with `.presentationDetents([.medium, .large])` — the pattern users already know from every social app on the platform.
- The composer lives at the bottom of that sheet, glass, above the keyboard.
- Delete: **swipe action**, `role: .destructive`, on the author's own comments and on any comment for admins. Replaces the web's `[Delete]` text link.
- Guest state: the composer is replaced by a sign-in prompt row, same as the web.

**Edit mode — RESTRUCTURE.** The web swaps the article body for an inline form. On iOS that is a **full-screen cover** presenting the same form as Contribute, because it is a long, multi-section form and inline editing inside a `ScrollView` is miserable. Save is disabled until the draft both validates and differs, exactly as today.

---

### 1.5 `/contribute` Create → **full-screen cover, not a tab**

**Web:** a route at `/contribute`, guarded by `requiresAuth`, with four numbered sections and a full-width dark submit bar.

**iOS:** a `+` button in the Archive and Desk toolbars presents a `.fullScreenCover`.

- **Not a tab.** Composition is a *task* with a beginning and an end, not a *place*. It gets a modal, with Cancel and Post in the navigation bar. This is Mail, Messages, and every other compose surface on the platform.
- `Form` with `Section`s replacing the four numbered blocks. The section headers ("01. Classification", "02. The Manuscript") become `Section("Classification")` etc. — **CUT** the numbering.
- Type and Language: `Picker(.segmented)` and `Picker(.menu)`.
- Title field appears only for Poetry, animated with the same conditional as the web.
- Origin `Picker`; source fields revealed only for `attributed`. **The `attributed` ↔ `shared` vocabulary split at the API boundary should not survive.** Pick one word. *(Schema is free — I suggest the wire format simply says `attributed`, matching what users are shown.)*
- **CUT** the smooth-scroll-to-first-error behaviour and the `showErrors` gate. `Form` validation on iOS surfaces inline as you go; a disabled Post button plus per-field messages is the idiom. No scroll choreography.
- Submit: nav bar `Post` button, `.buttonStyle(.glassProminent)`, disabled until valid.

**Liquid Glass:** the modal's own navigation bar. The `Form` itself is standard grouped-list material, not glass.

---

### 1.6 `/desk` The Desk → **Tab 2** *(auth-gated)*

**Web:** hero + "Quick Metrics" panel + two tabs (Works / Collection), each a card grid.

**iOS:**
- **CUT** the hero and the "The Study." display heading. A personal workspace does not need a masthead.
- **MERGE** the two-tab switcher into a `Picker(.segmented)` in the navigation bar's principal slot, or `.searchable`-adjacent toolbar. Two options is exactly what a segmented control is for.
- **Works** — the author's own submissions, including hidden ones. Hidden rows get a `Label("Hidden", systemImage: "eye.slash")` badge.
- **Collection** — favorites. **Swipe-to-unsave**, `role: .destructive`, replacing the toggle button.
- The "Quick Metrics" counts (Works, Collection) become the section headers of each list, or a small `.subheadline` under the title. Not a bordered panel.

**Naming (Q7).** The web has `/desk` titled "The Study." and `/admin` titled "The Desk." — inverted. On iOS this tab is **"Desk"**. Admin becomes "Moderation" and is not a tab (§1.9).

---

### 1.7 `/settings` + `/about` + `/roadmap` → **Tab 3, merged**

**MERGE.** Three routes collapse into one `Form`-based Settings tab. This is where the marketing pages go to be useful instead of decorative.

```
You  (Tab 3)
├─ [avatar]  Display Name  ·  @username
├─ Section "Profile"
│   ├─ Display Name         → inline TextField
│   ├─ Bio                  → TextEditor row
│   └─ Username             → read-only, @handle, "Permanent" footnote
├─ Section "Moderation"     → visible only when isAdmin
│   └─ Moderation Queue     → push (§1.9)
├─ Section "About"
│   ├─ About Abwaan         → push, the /about editorial content
│   ├─ Roadmap              → push, the /roadmap phase cards
│   └─ Version 2.0.15       → footnote
└─ Section
    └─ Sign Out             → .destructive, .confirmationDialog
```

- **CUT** the Settings page's "Claim Handle" form (Q3 — unreachable dead code on the web).
- **CUT** the "Archive Identity." display heading and the `01. / 02.` section numbering.
- **CUT** the `useDatabaseStatus` "SYSTEM ONLINE / Heartbeat" indicator. It reads `navigator.onLine` and never touches the database ([dbStatus.ts:13](client/src/shared/utils/dbStatus.ts:13)). It is theatre. Real connectivity is handled in §1.11.
- **CUT** the entire `Footer` — its index links become the tab bar, its contact link becomes a Settings row, its newsletter form was already commented out.
- Roadmap's `/build.json` fetch becomes a compile-time constant.

**Avatar.** `profiles.photoURL` is written once by the auth trigger and read by nothing ([03-DATA-MODEL.md](ios-rebuild-docs/03-DATA-MODEL.md) §1). Every avatar on the site is a generated letter initial. **Decision needed:** either render `photoURL` (a two-line change, and Google users get real avatars) or drop the field. Doing neither, as today, is the only wrong answer. I default to **rendering it**, with the letter initial as the `AsyncImage` placeholder.

---

### 1.8 `/p/:uid` Public Profile → **push**

Straight translation. Header with avatar, display name, `@username`, bio; then that author's published works as a `List`.

- **FIX** the contribution count (Q6). The web renders `submissions.length` — the number of rows currently loaded — so it climbs as you paginate ([PublicProfilePage.vue:96](client/src/features/profile/PublicProfilePage.vue:96)). iOS shows a real count.
- Reachable from any submission row's author chip and from the detail screen's author row.
- Deep-linkable (§08).

---

### 1.9 `/admin` → **"Moderation", pushed from Settings**

**RESTRUCTURE.** Not a tab.

Tab bars must be stable. A tab that materializes for 0.1% of users, after an async profile fetch resolves, is a layout that changes under the user. The moderation queue is a pushed screen from a role-gated Settings section.

- Two-tab structure (Submissions / Reports) → a `Picker(.segmented)` in the nav bar.
- Status filters (`hidden`/`published`, `open`/`reviewed`/`dismissed`) → toolbar `Menu`.
- Report groups → `List` with `DisclosureGroup`, replacing the HTML `<details>`.
- Dismiss / Resolve → **swipe actions** plus buttons in the row. Swipe is the native verb for triage.
- **FIX** the unbounded query: `listReports(status, 0)` passes `limit = 0`, which is falsy, so no limit is applied and every matching report loads at once ([reports.store.ts:16](client/src/features/admin/reports.store.ts:16)). Paginate.
- Admin edit/delete on others' content (Q14): the backend permits it; the web UI never exposed it. **Recommend matching the web** — admins hide and restore, nothing more. Say if you want otherwise.

---

### 1.10 `/login` + `/onboarding/username` → **sheet, and non-dismissible cover**

**Critical structural point: guests can read everything.** The site allows unauthenticated browsing of all published submissions and all comments. So the app **must not** open on a login wall. It opens on Archive.

**Auth is action-triggered.** Voting, saving, reporting, commenting, or contributing while signed out presents a sign-in **sheet** with `.presentationDetents([.medium])`. On the web these actions call `router.push('/login')`, throwing the user out of context and losing their place. A sheet does not.

- Login sheet: email, password, "Continue with Google", and a register/sign-in toggle.
- **CUT** the "Member Access" / "Security Key" / "Initialize new account" copy. It is costume. Use "Sign In", "Password", "Create Account".
- **The third button slot is Sign in with Apple, filled at M11** (13 §D1 — supersedes Q1's "no"). The original blocker was the missing Developer account, which must exist to ship at all; once enrolled, SIWA is roughly a day (`OAuthProvider("apple.com")`, a capability, the button) and it retires the R9 rejection risk for that day's work.

**Username onboarding** is a `.fullScreenCover` with `.interactiveDismissDisabled()`, presented when an authenticated user has no username. It is a hard gate on the web; it stays a hard gate here.

- **Add availability checking as you type.** The `usernames/{lower}` collection is world-readable ([firestore.rules:122](firestore.rules:122)), so a debounced existence check is one document read. The web discovers collisions only by submitting and catching `already-exists` — a worse experience for no reason. *(This is a UX improvement on an existing feature, not a new feature. Veto if you disagree.)*
- Copy stays blunt: "This handle is permanent."

---

### 1.11 App chrome → mostly **CUT**

| Web | iOS | Reason |
|---|---|---|
| Splash screen with 400 ms floor / 5000 ms ceiling ([App.vue:46-58](client/src/App.vue:46)) | **CUT.** Static launch screen; auth resolves behind it. | Deliberately delaying a fast launch is user-hostile. iOS launch screens exist to make launch feel instant, not to be admired. |
| "Connection Lost" banner with a page-reload button | **CUT** the banner. Firestore's offline cache serves reads; failed *writes* surface as inline errors. | `window.location.reload()` has no iOS analogue and reloading is not a fix. |
| `vue-sonner` toasts, top-center | **CUT** as a general mechanism. | iOS has no toast idiom. Success is communicated by the UI changing — the bookmark fills, the row appears. Where confirmation is genuinely needed, use haptics (`.sensoryFeedback`) or an inline status. |
| `GlobalDialog` custom modal | `.alert` / `.confirmationDialog` | The singleton promise-resolver composable ([useDialog.ts](client/src/shared/utils/useDialog.ts)) disappears entirely. |
| Lenis smooth scrolling + its CSS | **CUT.** | Native scrolling is already correct. This library exists to fix a web problem. |
| `@vueuse/motion` entrance animations on every card | **CUT.** | Staggered fade-ins on list rows fight `List` cell reuse and feel sluggish. |
| Page fade transitions | **CUT.** | `NavigationStack` push/pop is the transition. |
| `AppLoader` full-screen spinner | `ProgressView`, or `.redacted` skeletons | |
| PWA manifest / service worker | **CUT.** | It is an app now. |

### 1.12 Ambient audio player → **`.tabViewBottomAccessory`**

The site's floating "Ambient On/Off" pill ([AudioPlayer.vue](client/src/shared/components/AudioPlayer.vue)) — a Web Audio graph running a low-pass-filtered loop at 3% volume, autoplaying on mount, skipping 2G/3G, pausing on tab-hide.

This has an *exact* native home, and it is one of the better arguments for the latest SDK: **`.tabViewBottomAccessory`**, the slot Apple Music uses for its mini-player. It sits above the tab bar, is Liquid Glass by default, and collapses gracefully as the tab bar minimizes on scroll.

- Toggle + a small waveform indicator. Tap to play/pause.
- **CUT the autoplay.** iOS will not autoplay audio into a silent-switched phone, and attempting it is the kind of thing that makes people delete apps. Off by default; the user opts in.
- **CUT** the connection-speed check. `AVAudioSession` and a bundled asset make it irrelevant.
- Audio session category `.ambient`, `.mixWithOthers` — it must duck to nothing and never interrupt a podcast. It respects the ringer switch. It does **not** play in the background and does **not** claim the lock screen.
- The Web Audio low-pass filter → a pre-filtered audio asset, or `AVAudioUnitEQ`. Probably just ship a pre-filtered file.

**Per Q8, this is still yours to kill.** It is the single most "web" thing in the app. But `.tabViewBottomAccessory` is the reason it can stay without looking foreign.

---

## 2. Where Liquid Glass is used, and where it is banned

**Used** — always system-provided unless noted:

| Surface | Treatment |
|---|---|
| Tab bar | System glass; `.tabBarMinimizeBehavior(.onScrollDown)` |
| Bottom accessory (audio) | System glass, inherits tab bar behaviour |
| Navigation bars | System glass; `.scrollEdgeEffectStyle(.soft, for: .top)` |
| Bottom toolbar on Detail | System glass; vote/save/share/comments grouped with `ToolbarSpacer` |
| Sheets (comments, sign-in, report) | System glass with `.presentationDetents` |
| Toolbar buttons | `.buttonStyle(.glass)`; primary actions `.glassProminent` |
| Related floating controls | Wrapped in `GlassEffectContainer` so they merge and morph rather than stacking |

**Banned** — opaque, always:

- Any surface displaying poetry, proverb text, meaning, or translation.
- List rows.
- The comment body.
- `Form` fields in Contribute and Settings.
- Anything behind long-form reading.

**Rule of thumb:** if the user is *reading*, it is opaque. If the user is *acting*, it may be glass. Nested glass on glass is a defect — group with `GlassEffectContainer` and `.glassEffectUnion` instead.

---

## 3. Every cut, merge, and restructure — the veto list

Ordered by blast radius. Reply with the numbers you reject.

| # | Change | Kind | Rationale |
|---|---|---|---|
| 1 | Home screen deleted; app launches into Archive | **CUT** | Marketing hero has no job in an installed app |
| 2 | Card grid → single-column `List` (9 screens) | RESTRUCTURE | Desktop grid, phone reality |
| 3 | Detail sidebar → bottom glass toolbar + overflow menu | RESTRUCTURE | The 1,158-line screen's core problem |
| 4 | Comments → sheet with detents | RESTRUCTURE | Nested scroll is an antipattern |
| 5 | Contribute → full-screen cover, not a tab | RESTRUCTURE | Compose is a task, not a place |
| 6 | Admin → pushed from Settings, not a tab | RESTRUCTURE | Tab bars must not mutate per-role |
| 7 | Settings + About + Roadmap merged into one tab | MERGE | Three routes, one destination |
| 8 | Login → action-triggered sheet, never a launch wall | RESTRUCTURE | Guests can read; don't gate them |
| 9 | Edit → full-screen cover, not inline swap | RESTRUCTURE | Long form inside a `ScrollView` |
| 10 | Splash screen deleted | CUT | Artificial delay |
| 11 | Toasts deleted as a mechanism | CUT | No iOS idiom |
| 12 | Lenis, `@vueuse/motion`, page transitions deleted | CUT | Native |
| 13 | Offline banner + reload button deleted | CUT | No analogue |
| 14 | `useDatabaseStatus` / "SYSTEM ONLINE" deleted | CUT | Never touched the database |
| 15 | Footer deleted | CUT | Tab bar + Settings absorb it |
| 16 | Random archival photo gallery deleted | CUT | Editorial furniture |
| 17 | Load-more button → infinite scroll | RESTRUCTURE | iOS convention |
| 18 | Ambient audio → `.tabViewBottomAccessory`, autoplay removed | RESTRUCTURE | Native slot exists; autoplay is hostile |
| 19 | `/// LABEL` and `01.` numbering motifs dropped | CUT | Web aesthetic, reads as a bug |
| 20 | "Member Access"/"Security Key" copy → plain language | CUT | Costume |
| 21 | Search respects type/language scopes | **BEHAVIOUR CHANGE** | The site silently ignores filters during search (Q5) |
| 22 | Username availability checked as you type | **UX ADDITION** | One document read; registry is public |
| 23 | `photoURL` actually rendered | **UX ADDITION** | Field is written and never read today |
| 24 | Public profile count fixed | FIX | Site counts loaded rows (Q6) |
| 25 | Admin report list paginated | FIX | Site passes `limit = 0` and loads everything |
| 26 | Swipe actions for save / unsave / delete comment / triage report | ADDITION | Native affordance replacing text buttons |
| 27 | Share-as-image quote card via `ImageRenderer` | **UX ADDITION** | Accepted 2026-07-10 (13 §D2). The growth loop for a quotes archive. |
| 28 | Sign in with Apple, third slot filled at M11 | **ADDITION** | Accepted 2026-07-10 (13 §D1). Supersedes Q1. |

Items **21, 22, 23, 26, 27, 28** are the ones that add or alter behaviour rather than re-housing it. Items **24, 25** fix defects. All 28 accepted as of 2026-07-10.

---

## 4. Open, still

All resolved via [10 §0](ios-rebuild-docs/10-TECH-PLAN.md) assumptions and the 2026-07-10 review pass:

- **§1.7 avatar** — render `photoURL`, letter-initial placeholder (M4 default, confirm on sight).
- **§1.12 audio** — kept, `.tabViewBottomAccessory`, opt-in, no autoplay.
- **§1.9 admin powers** — hide/restore only, now via the `setSubmissionStatus` callable (13 §A4).
- **§1.3 search backend** — Option 2, with Somali apostrophe normalization added (13 §A9). Typesense stays a later milestone.
- **iPad** — out of scope for v1.
</content>
