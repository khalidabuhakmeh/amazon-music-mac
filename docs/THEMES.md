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

1. Create `Sources/AmazonMusic/Resources/themes/<name>.css` (copy `light.css`, change the palette).
2. Add the case to `Theme` (already declared for synthwave, cyberpunk, vampire), set `colorScheme` / `underPageRGB` if needed, and
   append it to `Theme.available`.
3. `ThemeTests` automatically checks the CSS file is bundled, non-empty, and has no `filter: invert`.
4. Verify in the real signed-in app (see below) on Home, Search, Library, an album page, the transport bar, a menu and the lyrics view.

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
