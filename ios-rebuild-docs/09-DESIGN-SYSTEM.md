# 09 — Design System

> Phase 1. No code. Values marked **(verify)** should be checked against the SDK you actually install — I could not compile against it.
>
> **Revised 2026-07-10**: localization resolved — String Catalog discipline from M2 (§9).

## 1. Typography

The site pairs three Google fonts: **Manrope** (sans, UI), **Cormorant Garamond** (serif, all poetry and headlines), and **Kalam** (cursive, declared but unused) ([tailwind.config.js:81-85](client/tailwind.config.js:81)).

The serif is not decoration. Gabay and Maahmaahyo are the product, and setting them in a serif is an editorial decision worth preserving.

**iOS gets this for free.** The system ships a serif — **New York** — as a design variant, and it supports Dynamic Type, optical sizing, and every weight. No font files, no CDN, no `@font-face`, no FOUT.

| Role | Font | SwiftUI |
|---|---|---|
| Poem title, proverb text | New York | `.font(.system(.largeTitle, design: .serif))` |
| Verse body (`text` for Poetry) | New York | `.system(.title3, design: .serif)`, `.italic()` |
| Translation | New York italic | `.system(.body, design: .serif).italic()` |
| Meaning / interpretation | SF Pro | `.body` |
| Comment body | New York | `.system(.body, design: .serif)` |
| All UI chrome, labels, buttons | SF Pro | `.body`, `.callout`, `.caption` |
| Metadata (dates, IDs, counts) | SF Pro | `.caption.monospacedDigit()` |

**Two things the site does that must not survive:**

- **`text-[10px]` uppercase tracking-widest labels, everywhere.** Ten pixels is below the iOS minimum for legibility and is not Dynamic-Type-aware. These become `.caption` or `.caption2` with `.textCase(.uppercase)` where the label genuinely reads as a label — sparingly.
- **`tracking-tighter` on display headlines.** New York's optical sizing already tightens tracking at large sizes. Do not fight it.

**Dynamic Type is mandatory, not optional.** Every font above is a text style, never a fixed point size. Test at `.accessibility5`. Two specific breakages to watch:

- The vote control (`▲ score ▼`) in the bottom toolbar — the score is a variable-width number. Use `.monospacedDigit()` so it does not jitter as counts change, and let the toolbar wrap at large sizes.
- The Contribute form's section headers, which on the web carry both a number and a title.

`.dynamicTypeSize(...(.accessibility3))` may be clamped on the bottom toolbar only. Never clamp content.

## 2. Color

### Accent

The site's brand color is `carrotOrange-500` = **`#eb932e`** ([tailwind.config.js:42](client/tailwind.config.js:42)). Every hover, focus ring, active state, and CTA uses the `carrotOrange` ramp.

Note: both the PWA manifest and the Vite PWA config declare `theme_color: '#FF6B35'` ([vite.config.ts:23](client/vite.config.ts:23), [public/manifest.json:8](client/public/manifest.json:8)) — a color that appears **nowhere** in the palette. It is wrong on the web. Do not carry it over. **`#eb932e` is the accent.**

`#eb932e` on white is roughly **2.3:1** contrast **(verify)** — it fails WCAG AA for text. The site uses `carrotOrange-600` (`#db751b`) for actual text links, which is closer. **Rule: `#eb932e` tints controls and fills; it never colors small text on a light background.** Use the 600 stop, or a semantic label color, for text.

### Dark mode — this is net-new work

The web app has **no dark mode**. None. Every surface is `bg-white`, every text is `text-gray-900`, hard-coded ([App.vue:84](client/src/App.vue:84)). [ROADMAP.md:19](ROADMAP.md:19) acknowledges this: *"No dark mode infrastructure despite the color palette being ready for it."*

On iOS, dark mode is not a feature. It is table stakes, and Liquid Glass makes it non-negotiable — glass adapts to what is behind it, and "behind it" is the user's chosen appearance. **This is unavoidable new design work with no web counterpart.**

Strategy: **semantic colors for everything except the accent.**

| Purpose | Token | Never |
|---|---|---|
| Page background | `Color(.systemBackground)` | `.white` |
| Grouped form background | `Color(.systemGroupedBackground)` | `gray-50` |
| Card / raised surface | `Color(.secondarySystemBackground)` | |
| Primary text | `Color(.label)` | `gray-900` |
| Secondary text | `Color(.secondaryLabel)` | `gray-500` |
| Tertiary / metadata | `Color(.tertiaryLabel)` | `gray-400` |
| Separator | `Color(.separator)` | `gray-200` |
| Accent | `Color.accentColor` = `#eb932e` (Asset Catalog, light + dark variants) | |
| Destructive | `Color(.systemRed)` | `red-500` |
| Upvote active | `Color(.systemGreen)` | |
| Downvote active | `Color(.systemRed)` | |
| Hidden / moderated badge | `Color(.systemOrange)` | |

The accent needs a **dark-mode variant** in the Asset Catalog. `#eb932e` is tuned for white; on `#000` it will vibrate. Lighten and desaturate slightly **(verify against a real device, not the simulator)**.

**Delete the rest of the palette.** `seashell`, `saffron`, `redDamask`, and `cinnabar` are four full 11-stop ramps ([tailwind.config.js:9-76](client/tailwind.config.js:9)) and the app uses `carrotOrange` plus Tailwind's stock grays, red, green, and emerald. The other ramps are dead weight.

### The dot pattern

Every page carries `background-image: radial-gradient(#000 1px, transparent 1px)` at 3% opacity ([App.vue:80](client/src/App.vue:80) and five other places). It is the app's one piece of texture.

**Recommendation: cut it.** Under Liquid Glass, a repeating high-frequency dot pattern is exactly the kind of content that makes glass refraction look like a moiré artifact. If you want it, it belongs behind the *content* layer only, never behind a glass toolbar, and it must invert for dark mode. **Your call.**

## 3. Spacing and layout

The site's spacing is desktop-scaled: `p-12`, `p-20`, `lg:p-24`. That is 48–96 px of padding on surfaces that will be 393 pt wide.

| Context | Value |
|---|---|
| Screen horizontal margin | 16 pt (system default; do not override) |
| List row vertical padding | 12 pt |
| Section spacing | 24 pt |
| Related element spacing | 8 pt |
| Reading measure | let `List` handle it |

Use the **8-point grid**. Do not port a single Tailwind spacing value.

**Corner radius:** use `.rect(cornerRadius:style: .continuous)` or, better, the concentric shapes Liquid Glass expects — `.capsule` for toolbar buttons, `.containerConcentric` for nested surfaces **(verify)**. The site's mix of `rounded-full`, `rounded-lg`, `rounded-xl`, and hard `rounded-none` corners is not a system.

## 4. SF Symbols — complete mapping

Every icon in the app. The site uses two extracted icon components, ~15 inline SVGs, and three Heroicons on one page.

| Where | Web icon | SF Symbol |
|---|---|---|
| Tab: Archive | — (new) | `books.vertical` / `.fill` |
| Tab: Desk | — (new) | `tray.full` / `.fill` |
| Tab: You | — (new) | `person.crop.circle` / `.fill` |
| Tab: Search | `SearchIcon.vue` | `magnifyingglass` |
| Dropdown chevron | `ChevronDownIcon.vue` | `chevron.down` |
| Upvote | `▲` text glyph | `arrowtriangle.up` / `.fill` |
| Downvote | `▼` text glyph | `arrowtriangle.down` / `.fill` |
| Save / favorite | inline bookmark SVG | `bookmark` / `bookmark.fill` |
| Share | inline share-node SVG | `square.and.arrow.up` (via `ShareLink`) |
| Report | inline document SVG | `flag` / `flag.fill` |
| Delete | inline trash SVG | `trash` |
| Edit | inline pencil SVG (onboarding) | `pencil` or `square.and.pencil` |
| Overflow menu | — (new) | `ellipsis.circle` |
| Comments | — (count text only) | `bubble.left` / `.fill` |
| Hide submission | `EyeSlashIcon` (Heroicons) | `eye.slash` |
| Restore / approve | `CheckIcon` (Heroicons) | `checkmark` or `checkmark.circle` |
| Inspect / open | `ArrowUpRightIcon` (Heroicons) | `arrow.up.right` |
| Compose | — (text button) | `plus` or `square.and.pencil` |
| Filter | — (dropdowns) | `line.3.horizontal.decrease.circle` |
| Sort | — (dropdown) | `arrow.up.arrow.down` |
| Offline / error | inline warning SVG | `exclamationmark.triangle` |
| Warning (dialog) | inline warning SVG | `exclamationmark.triangle.fill` |
| Success | inline check SVG | `checkmark.circle.fill` |
| Ambient audio on | colored dot | `speaker.wave.2` |
| Ambient audio off | gray dot | `speaker.slash` |
| Language | — (dropdown) | `globe` |
| Google sign-in | inline Google `<path>` | **none** — must ship the Google brand asset. Google's guidelines forbid substitution. |
| Sign out | — (text) | `rectangle.portrait.and.arrow.right` |
| Empty state (generic) | dashed circle + `?` | `ContentUnavailableView` supplies its own |
| Not found | `?` in circle | `questionmark.circle` |
| Hidden badge | — (text "hidden") | `eye.slash.circle.fill` |
| Moderation queue | — | `shield.lefthalf.filled` |
| About | — | `info.circle` |
| Roadmap | — | `map` |

Use `.symbolRenderingMode(.hierarchical)` by default. `.symbolEffect(.bounce)` on a successful vote is the kind of feedback that replaces a toast. Vote arrows should use `.contentTransition(.symbolEffect(.replace))` when toggling filled state.

## 5. Component inventory

Mapped from the web. **"New"** means no web counterpart exists.

| Web component | iOS | Notes |
|---|---|---|
| [SubmissionCard.vue](client/src/shared/components/SubmissionCard.vue) | `SubmissionRow` | `List` row. Serif headline, author chip, score. Swipe to save. |
| [EmptyState.vue](client/src/shared/components/EmptyState.vue) | `ContentUnavailableView` | System. Delete the component. |
| [LoadMore.vue](client/src/shared/components/LoadMore.vue) | — | **Deleted.** Infinite scroll via `.task` on the last row. |
| [BaseDropdown.vue](client/src/shared/components/BaseDropdown.vue) | `Menu` + `Picker` | **Deleted.** ~200 lines of hand-rolled ARIA, roving tabindex, and click-outside handling that `Menu` provides natively. |
| [GlobalDialog.vue](client/src/shared/components/GlobalDialog.vue) + [useDialog.ts](client/src/shared/utils/useDialog.ts) | `.alert`, `.confirmationDialog` | **Deleted.** Including the singleton promise-resolver. |
| [AppLoader.vue](client/src/shared/components/AppLoader.vue) | `ProgressView` / `.redacted` | **Deleted** as a full-screen splash. |
| [AudioPlayer.vue](client/src/shared/components/AudioPlayer.vue) | `AmbientAudioControl` | Moves into `.tabViewBottomAccessory`. Web Audio graph → `AVAudioSession(.ambient, .mixWithOthers)`. |
| [CommentForm.vue](client/src/features/submissions/CommentForm.vue) | `CommentComposer` | Bottom of the comments sheet, glass, keyboard-aware. |
| [CommentList.vue](client/src/features/submissions/CommentList.vue) | `CommentList` | `List` in a sheet. No nested scroll. Swipe to delete. |
| [TheNavigation.vue](client/src/shared/navigation/TheNavigation.vue) + [DesktopNav.vue](client/src/shared/navigation/DesktopNav.vue) + [MobileNav.vue](client/src/shared/navigation/MobileNav.vue) | `TabView` | **Three components deleted.** Plus the scroll-direction hide/show logic — `.tabBarMinimizeBehavior` does it. |
| [Footer.vue](client/src/shared/navigation/Footer.vue) | — | **Deleted.** |
| [SiteLogo.vue](client/src/shared/navigation/SiteLogo.vue) | — | **Deleted.** The app icon is the logo. |
| [SearchBar.vue](client/src/features/collections/SearchBar.vue) | `.searchable` | Already dead code on the web. |
| [icons/](client/src/shared/components/icons) | SF Symbols | **Deleted.** |
| [alerts.ts](client/src/shared/utils/alerts.ts) (toasts) | — | **Deleted.** See [07](ios-rebuild-docs/07-DESIGN-TRANSLATION.md) §1.11. |
| [sanitize.ts](client/src/shared/utils/sanitize.ts) | — | **Deleted.** SwiftUI `Text` does not interpret markup. The entire XSS surface is a web problem. |
| [dbStatus.ts](client/src/shared/utils/dbStatus.ts) | — | **Deleted.** |
| — | `VoteControl` | **New.** Bottom-toolbar segment. |
| — | `AuthSheet` | **New.** Action-triggered sign-in. |
| — | `SignInPrompt` | **New.** Inline, for the Desk tab. |
| — | `HiddenBadge` | **New.** |
| — | `AvatarView` | **New.** `AsyncImage(photoURL)` with a letter-initial placeholder. |

**Roughly 14 components and 4 utility modules disappear**, replaced by system behaviour. That is the bulk of the "way less code" you are after, and it is not achieved by writing tighter Swift — it is achieved by not reimplementing the platform.

## 6. Liquid Glass rules for this app

**The single rule:** glass is for the layer the user *acts on*. Opaque is for the layer the user *reads*.

### Permitted

| Surface | Treatment |
|---|---|
| Tab bar | System. `.tabBarMinimizeBehavior(.onScrollDown)` |
| Bottom accessory (audio) | System. Inherits tab-bar minimize. |
| Navigation bars | System. `.scrollEdgeEffectStyle(.soft, for: .top)` |
| Detail bottom toolbar | System, via `.toolbar { ToolbarItemGroup(placement: .bottomBar) }` |
| Sheets | System glass + `.presentationDetents` |
| Toolbar buttons | `.buttonStyle(.glass)` |
| Primary action (Post, Claim, Sign In) | `.buttonStyle(.glassProminent)` |
| Grouped floating controls | `GlassEffectContainer` + `.glassEffectID(_:in:)` for morph transitions |

### Banned

- **Any surface rendering poetry, proverb text, meaning, translation, or a comment body.** Non-negotiable. This is a reading app.
- List rows.
- `Form` fields.
- The dot pattern behind glass (§2).
- **Glass nested inside glass.** A glass button on a glass toolbar is a defect. Group with `GlassEffectContainer`; merge related capsules with `.glassEffectUnion(id:namespace:)` **(verify)**.
- Custom `.ultraThinMaterial` backgrounds hand-rolled to imitate glass. Use the real API or use opaque.

### Grouping

The Detail screen's bottom toolbar has four logical items: vote (a compound control), save, share, comments. They belong in **one** `GlassEffectContainer`, separated by `ToolbarSpacer(.fixed)` so the system renders them as grouped capsules that merge and separate correctly during scroll and during the tab-bar minimize animation. Four independently glassed buttons floating side by side is the most common way to get this wrong.

## 7. Accessibility

Liquid Glass degrades gracefully, but only if you let it.

### Reduce Transparency

`@Environment(\.accessibilityReduceTransparency)`. System glass falls back to an opaque material automatically. **Any custom `.glassEffect` must be checked manually** — if the setting is on, render an opaque `Color(.secondarySystemBackground)` fill instead. The audio accessory and the vote control are the two places we might hand-roll glass; both need the branch.

### Reduce Motion

`@Environment(\.accessibilityReduceMotion)`. Disable the glass morph transitions (`.glassEffectID` animations), the symbol bounce on vote, and the tab-bar minimize animation. The web app's `@vueuse/motion` staggered entrances are already being cut, so there is less to guard than it sounds.

### Increase Contrast

`@Environment(\.colorSchemeContrast)`. Glass borders strengthen automatically. Verify `#eb932e` against `Color(.label)` in both appearances at increased contrast — I expect the accent will need the 600 stop (`#db751b`) for text in that mode.

### VoiceOver

The web app is mediocre here and the port should not inherit it.

| Element | Requirement |
|---|---|
| `SubmissionRow` | One accessibility element. Label: *"Proverb. \(text). By @\(username). Score \(n)."* Not five separately-focusable fragments. |
| Vote control | `.accessibilityValue` reports the score. Actions labeled "Upvote"/"Remove upvote". State announced on change. |
| Vote arrows | The site uses bare `▲`/`▼` **text glyphs** — VoiceOver reads them as "black up-pointing triangle". Must be `Button` + `Label` + SF Symbol. |
| Card tap target | The site's `SubmissionCard` is `role="link"` on an `<article>` with a nested `router-link` for the author — a nested-interactive-element trap. On iOS: row taps to detail, author is an `.accessibilityAction`, not a nested button. |
| Swipe actions | Automatically exposed as VoiceOver actions. Free. |
| Hidden badge | `.accessibilityLabel("Hidden from public listings")` |
| Bottom accessory | `.accessibilityLabel("Ambient sound")`, `.accessibilityValue("On"/"Off")` |
| Sheets | `.presentationDetents` handles focus. Ensure the composer is the first focused element in the comments sheet. |
| Report modal | The web manages focus manually with `nextTick` and refs. Sheets do this for free. |

### Touch targets

44×44 pt minimum. The site's `text-[10px]` `[Delete]` link on comments and its `p-1` dismiss button are both far under. Swipe actions solve most of this by removing the tiny buttons entirely.

### Dynamic Type

Covered in §1. The single largest risk is the bottom toolbar at `.accessibility5` — four items plus a compound vote control. It will need to reflow, and I would rather it reflow than clamp content.

## 8. What I am not carrying over

Stated so nobody has to ask later.

`tracking-widest` uppercase micro-labels · `/// ERROR:` and `/// INTERPRETATION` slash motifs · `01.` / `02.` section numbering · "The Study." / "The Desk." display headings · "Member Access" / "Security Key" / "Initialize new account" copy · "System Level 01" · "End of Ledger" · the `font-mono` metadata treatment · `Kalam` · four unused color ramps · the 12-column grid · every `hover:` state (no hover on touch) · `group-hover:translate-x-2` reveal animations · the dot pattern (pending your call) · `theme_color: #FF6B35`.

Some of this is genuinely good voice, and the archival tone is worth keeping in **words**. It just should not be carried in *typography tricks* that read as broken rendering on a phone.

## 9. Still open

- **Dot pattern** — keep behind content, or cut entirely?
- **Accent for text** — confirm `#db751b` (600) as the text-safe accent, `#eb932e` (500) for fills only.
- **Dark-mode accent variant** — needs to be chosen on hardware.
- **App icon** — `Abwaan_4.svg` exists ([assets/logo](client/src/assets/logo)). Does it work at 1024×1024 and at 29pt? Liquid Glass icons have their own layered treatment **(verify)**.
- **iPad** — out of scope unless you say otherwise (raised in [07](ios-rebuild-docs/07-DESIGN-TRANSLATION.md) §4).
- **Localization — RESOLVED (13 §C3).** The app ships English-only, but **every user-facing string goes through a String Catalog from M2 onward** — no hardcoded strings, ever. The expensive part of localization is the retrofit, not the translation; this discipline costs nothing now and makes a Somali UI a translation task later instead of a refactor. For an app whose reason to exist is Somali language preservation, "English-only" must stay a reversible decision.
</content>
