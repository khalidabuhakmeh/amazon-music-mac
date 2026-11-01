# Amazon Music (macOS) — agent notes

- Build: `./scripts/build.sh` (XcodeGen + xcodebuild into `build/`). Swift 6, strict concurrency.
- Network-free launch modes (never load a web view, never touch the network):
  - `build/Build/Products/Debug/AmazonMusic.app/Contents/MacOS/AmazonMusic --snapshot [dir]` (default `build/snapshots`, or `APP_SNAPSHOT_DIR`) writes `<surface>-<light|dark>.png` for every MiniPlayer fixture, each Settings tab and About, then exits.
  - `... --selftest` prints `PASS`/`FAIL` lines, exit 0 only if all pass.
- Snapshot rendering method that worked: host the view in an offscreen borderless `NSWindow` (origin -30000,-30000, `orderFrontRegardless`, `window.appearance` set), pump the run loop ~0.4s, then `bitmapImageRepForCachingDisplay` + `cacheDisplay`. `ImageRenderer` renders Form/glass blank. Settings uses a titled window and captures the frame view; the tab strip does not paint reliably in dark (white band, known limitation), contents are fine. About is AppKit (`BackgroundStackView`) because a bare view skips the window background.
- Fixtures live in `Sources/AmazonMusic/Model/PlayerStateFixtures.swift` (shared by #Previews, snapshot, selftest).
- Tests: `xcodebuild test -scheme AmazonMusic -destination 'platform=macOS,arch=arm64' -derivedDataPath build`, `node tools/bridge-test/bridge.test.mjs`, `node tools/hidesections-test/hidesections.test.mjs`.
