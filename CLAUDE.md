# Amazon Music (macOS) — agent notes

- Build: `./scripts/build.sh` (XcodeGen + xcodebuild into `build/`). Swift 6, strict concurrency.
- Network-free launch modes (never load a web view, never touch the network):
  - `build/Build/Products/Debug/AmazonMusic.app/Contents/MacOS/AmazonMusic --snapshot [dir]` (default `build/snapshots`, or `APP_SNAPSHOT_DIR`) writes `<surface>-<light|dark>.png` for every MiniPlayer fixture, each Settings tab and About, then exits.
  - `... --selftest` prints `PASS`/`FAIL` lines, exit 0 only if all pass.
- Snapshot rendering method that worked: host the view in an offscreen borderless `NSWindow` (origin -30000,-30000, `orderFrontRegardless`, `window.appearance` set), pump the run loop ~0.4s, then `bitmapImageRepForCachingDisplay` + `cacheDisplay`. `ImageRenderer` renders Form/glass blank. Settings uses a titled window and captures the frame view; the tab strip does not paint reliably in dark (white band, known limitation), contents are fine. About is AppKit (`BackgroundStackView`) because a bare view skips the window background.
- Fixtures live in `Sources/AmazonMusic/Model/PlayerStateFixtures.swift` (shared by #Previews, snapshot, selftest).
- Tests: `xcodebuild test -scheme AmazonMusic -destination 'platform=macOS,arch=arm64' -derivedDataPath build`, `node tools/bridge-test/bridge.test.mjs`, `node tools/hidesections-test/hidesections.test.mjs`.

## Scripts
- `scripts/build.sh` — build only. `--open` also installs to `~/Applications/AmazonMusic.app` (file name must stay; display name comes from InfoPlist.strings), kills and relaunches it. `--selftest` builds then runs the binary's `--selftest`.
- `scripts/snapshot.sh --baseline` writes `build/snapshots/baseline`; `scripts/snapshot.sh --diff` re-renders into `build/snapshots/current/` and prints changed pixels per file (`magick compare -metric AE -fuzz 8%`), exit 1 on any difference/missing file unless `--allow-diff`; exit 2 if ImageMagick is missing (`brew install imagemagick`).
- Tests: see commands above.
- Caveat: snapshots use fixtures only (fixed, dated data); never real network data, so diffs reflect UI changes only.
