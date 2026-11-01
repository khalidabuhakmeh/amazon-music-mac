# Web themes

Amazon's web player (music.amazon.com in the WKWebView) is dark only. Themes are injected CSS, picked in
Settings → General → Theme and applied live (no reload). `Default` means *no override*: the page is untouched.

## How it works

| Piece | Where |
|---|---|
| `Theme` enum (all five cases, `Theme.available` = what the picker lists), `ThemeScript` (JS builders) | `Sources/AmazonMusic/Web/Theme.swift` |
| JS helper `window.__amzTheme` (`set(css\|null, scheme)`, `state()`) | `Sources/AmazonMusic/Resources/themeHelper.js` |
| One CSS file per theme, named after the enum raw value | `Sources/AmazonMusic/Resources/themes/<rawValue>.css` |
| Wiring: user script at document start, live apply, re-apply after each navigation | `WebController` in `Web/MusicWebView.swift` |
| Setting (`UserDefaults` key `theme`, unknown value → `default`) | `Settings/AppSettings.swift` |

- At **document start** `WebController` injects `themeHelper.js` followed by `__amzTheme.set(<css>, <scheme>)` with the current
  theme baked in, so there is no dark flash. The CSS goes in as a JSON string literal (`ThemeScript.literal`), never raw.
- The helper keeps one `<style id="amz-theme-style">` in `<head>`, re-adds it if the SPA wipes it, sets `data-amz-theme` and
  `color-scheme` on `<html>`, and also writes the style into any shadow root created via `attachShadow` (none exist today; it is
  insurance if Amazon adopts web components).
- Switching themes rebuilds the user scripts (future loads) **and** calls `set(...)` on the loaded page. `Default` calls
  `set(null, …)`, which removes the style node and the attribute/`color-scheme`: nothing is left behind.
- `didFinish` re-applies the theme after every navigation. `webView.underPageBackgroundColor` is set per theme to avoid overscroll flashes.
- Does not touch `bridge.js` / `hideSections.js` (they only read the DOM; the style node has an id they ignore).

## Adding a theme

1. Create `Sources/AmazonMusic/Resources/themes/<name>.css` (light.css is the full-remap pattern; the dark themes below only re-map what differs from Amazon's native dark palette).
2. Add the case to `Theme` (already declared for synthwave, cyberpunk, vampire), set `colorScheme` / `underPageRGB` if needed, and
   append it to `Theme.available`.
3. `ThemeTests` automatically checks the CSS file is bundled, non-empty, has no `filter: invert`, no `@import`/`url(`/`http(s)://` (themes are fully offline), and that every theme's CSS is distinct.
4. Verify in the real signed-in app (see below) on Home, Search, Library, an album page, the transport bar, a menu and the lyrics view.

## Dark themes: Synthwave, Cyberpunk, Vampire

Picker order: Default, Light, Synthwave, Cyberpunk, Vampire. All three set `color-scheme: dark` and an `underPageRGB` equal to their page color.
They re-map: page/top-bar/chrome backgrounds, primary/secondary/dim text, accent text + icons (`rgb(37,209,218)`), accent *fills*
(inline `background-color: rgb(37,209,218)` **and** the CSS-module primary button `button[class*="_accent"][class*="_filled"]`; label color
is forced to the "on-fill" color), hairlines/secondary fills, the progress fill (gradient), the detail-page `LinearGradient` fade (fades to the page color), menus/dialogs, scrollbars, selection and focus rings.
Artwork is never filtered; text on artwork stays white (last block). Cyberpunk additionally uses 2–3px radii on buttons/inputs/menus (never on artwork tiles) and a thin yellow edge on the player bar.

| Theme | page | surface (top bar, menus) | text / secondary | accent text | accent fill (label) | glow / lines |
|---|---|---|---|---|---|---|
| Synthwave | `#120a2a` | `#1c1040` | `#f6eeff` / `#b9a7e0` | `#2de2e6` cyan | `#ff2bd6` magenta (`#120a2a`); progress gradient `#ff2bd6→#ff8a3d` | magenta glow `rgba(255,43,214,.35)`, cyan hairlines |
| Cyberpunk | `#0b0b0f` | `#14141b` | `#f4f4f0` / `#a9acb8` | `#fcee09` yellow | `#fcee09` (`#0b0b0f`); progress `#fcee09→#ff003c`; cyan `#00f0ff` secondary fills, red `#ff003c` selection | yellow hairlines, cyan glow |
| Vampire | `#0a0405` | `#1a0508` | `#efe6e1` / `#b49ea3` | `#ff4d63` | `#c4122f` (`#ffffff`); progress `#8f0e24→#e01b3c`; `#2b0a10`-range burgundy washes | crimson glow `rgba(224,27,60,.3)` |

WCAG contrast (computed from the hex values, sRGB relative luminance; all ≥ 4.5:1):

| Theme | text / page | secondary / page | accent text / page | dim (inactive lyrics, .62 alpha) / page | text / secondary / accent on surface | label on accent fill |
|---|---|---|---|---|---|---|
| Synthwave | 16.9 | 8.8 | 11.9 | 6.8 | 15.5 / 8.1 / 11.0 | 6.0 |
| Cyberpunk | 17.8 | 8.7 | 16.3 | 7.1 | 16.6 / 8.1 / 15.2 | 16.3 |
| Vampire | 16.5 | 8.1 | 6.3 | 6.5 | 16.0 / 7.8 / 6.1 | 6.0 |

Glow is `box-shadow` / one `text-shadow` on accent text only (Synthwave, 8px, same hue) so it never sits behind body text.
CSS-module class names (`_accent`, `_filled`) have a build hash prefix; selectors use `[class*=…]` substrings, so a hash change is harmless but a rename of those words would need a CSS fix.
Screenshots: `docs/screenshots/themes/{synthwave,vampire}-*.png` (cyberpunk screenshots were verified live but not saved; see the task report).

## What Amazon's DOM looks like (investigated Nov 2026, signed-in)

- It is **react-native-web**. There are **no custom elements (`music-*`) and no Shadow DOM**: page CSS reaches everything. No `--*`
  custom properties exist apart from `--expo-image-timing` and Radix's `--radix-*` positioning vars, so there is nothing to override.
- Class names are hashed atoms (`css-g5y9jx` View, `css-146c3p1`/`css-1jxf684` Text, `r-*`): unstable, **not used for selection** except `r-jwli3a`, `r-c68hjy`, `r-kizejy`, `r-17u3ijr`.
- Almost all colors are **inline `style=""` values from a small fixed palette**. `data-testid`s (`Page`, `TopNavBar_*`, `Tile…`, `MiniPlayer_*`, `LinearGradient`, `Badge`, `PlaceholderArt`, `ThumbnailButton…`) are stable.
- So themes re-map exact palette values with attribute selectors and `!important` (inline styles lose to `!important`):
  text is matched as `[style^="color: X"], [style*="; color: X"]` so `background-color: X` never matches; SVG icons use the `fill="…"` attribute.

| Palette value (inline) | Meaning | Light mapping |
|---|---|---|
| `rgb(255,255,255)` text / fill | primary text, icons | `#14191a` |
| `rgb(163,163,163)`, `rgba(255,255,255,.5–.7)` | secondary text | `#596269` |
| `rgba(255,255,255,.3/.4)` | inactive lyrics | `rgba(20,25,26,.46)` |
| `rgb(37,209,218)` | accent text/icons | `#0a7b86` (accent *fills* keep `#25d1da`) |
| `rgb(0,0,0)` bg, `rgb(20,25,26)` (body, menus) | page | `#f4f6f7` (menus/dialogs `#fff`) |
| header: `rgb(0,0,0)` + `border-bottom-color`, glass `rgba(25,25,25,.7)` | top bar | `#fff` / `rgba(255,255,255,.86)` |
| `rgba(255,255,255,.15)` border / fill | hairlines, secondary buttons | `rgba(20,25,26,.14 / .16)` |
| `[data-testid="LinearGradient"]` (black fade over blurred cover on detail pages) | album/playlist backdrop | fade to page color |
| `img[src*="/music/logo/"]` (white wordmark file) | logo | `filter: brightness(0)` (logo only) |
| `[role=menu|dialog|tooltip]` (Radix) | popovers | white surface + shadow |

Text that sits **on artwork/gradients** (`ThumbnailButton`, `TopRecommender`, tile play badges) must stay light: the last block of `light.css` re-asserts white there. Artwork (`img`, `background-image`, video) is never filtered.

If Amazon changes a palette value or testid, fix it in the CSS file only (the JS helper has no selectors). Discover current values by dumping inline-style colors in the Web Inspector (the web view is inspectable in Debug builds).

## Verifying

`defaults write com.khalidabuhakmeh.amazonmusic theme light` then `scripts/build.sh --open` (or use the picker), navigate with
`amazonmusic open --path /search/jazz`, screenshot with `screencapture -l <windowid>`. Light screenshots: `docs/screenshots/themes/light-*.png`.
`amazonmusic track show --json` must still report state. Snapshots (`--snapshot`) never load the web view and always use the default theme.
