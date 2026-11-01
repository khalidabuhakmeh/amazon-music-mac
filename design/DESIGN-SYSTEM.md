# Design system

Tokens live in `Sources/AmazonMusic/UI/DesignTokens.swift`. Views use tokens, never raw values.
Checks: `tools/grid-lint.sh` (also run by `scripts/build.sh --selftest`) and
`rg -n 'opacity\(0\.|\.font\(\.system\(size:' Sources/AmazonMusic/UI` (no hits outside DesignTokens.swift).

## Space (4 pt grid)
`xxs 2` hairline gaps only (row hover inset). `xs 4` icon-to-edge nudges. `s 8` related controls, row insets.
`m 12` between artwork and text. `l 16` popover margin and row leading edge. `xl 24` between groups.
Raw numbers in layout are 0, 1, 2 or a multiple of 4; the lint enforces it. Escape: `// grid: ok <why>`
(hairline 0.5 pt borders, scrub-knob `.offset`).

Decisions when snapping old values: 14 → `l` (popover/row margin); 10 → `m`; 6 → `s` (gap) or `xxs`+`s` for row hover inset;
3 → `xs`; 30/42 control hit sizes → 32/44; scrub bar 6 → 8, scrub hit 14 → 16; Up Next header 30 → 32.

## Radius
`xs 4` row thumbnails, `s 8` row hover fills, `m 12` cover art. Inner radius = outer radius − inset.

## Surface (opacities)
`secondaryText .65` de-emphasised text/glyphs/divider · `hoverFill .07` · `hairline .12` borders ·
`scrim .5` black behind glyphs on artwork · `faint .3` disabled, scrub track, shadows · `dim .7` resting/pending controls
and the popover tint layer. Add a new name only when none fits.

## Motion
`quick` (0.15 s ease-out) hover/press, `standard` (0.2 s ease-out) expand/collapse. No durations in views.

## Type
System text styles only: `.caption2` times, `.caption`/`.callout` rows, `.body` subtitle, `.title3` heading
(`.monospacedDigit()` on times). SF Symbol glyphs use `Glyph.*` (fixed sizes, icons not text).

## Settings
Each tab: `Form` + `.formStyle(.grouped)` + `.fitsContent()` (scrolling off, 480 pt wide, ideal height).
Settings scene uses `.windowResizability(.contentSize)`; `SettingsView` uses `.noInitialFocus()` so nothing is focused on open.
