# Spike: Amazon Music web in WebKit (macOS 26)

> Historical record. The spike app source (`spike/`) was removed from the repository, and `spike-log.jsonl` was deleted because it contained account-related URLs. Paths below refer to files that no longer exist.

## Built
`spike/` — XcodeGen project (macOS 26, arm64, Hardened Runtime, ad-hoc signed, entitlement `com.apple.security.network.client` only [+ debug `get-task-allow` injected by Xcode], bundle `com.khalidabuhakmeh.amazonmusic.spike`).
Loads https://music.amazon.com in a persistent (`.default()`) data store, `isInspectable = true`, autoplay allowed.
Build: `cd spike && xcodegen && xcodebuild -project Spike.xcodeproj -scheme Spike -configuration Debug -derivedDataPath build -destination 'platform=macOS,arch=arm64' build`; run: `open build/Build/Products/Debug/Spike.app`.
UA: Safari UA (Version/27.2, from /Applications/Safari.app) by default; launch with env `SPIKE_UA=default` for WebKit default (run binary directly: `SPIKE_UA=default build/Build/Products/Debug/Spike.app/Contents/MacOS/Spike`).

## API choice (decided: WKWebView)
SDK WebKit-for-SwiftUI `WebPage` (swiftinterface) exposes `NavigationDeciding` and `DialogPresenting` but **no createWebView / window.open hook**. So popups can't be handled -> used **WKWebView in NSViewRepresentable** with `WKUIDelegate.webView(_:createWebViewWith:...)`, opening popups in a new NSWindow sharing the configuration.

## Now Playing
No public WKWebView/WKPreferences/WebPage API found in SDK headers/swiftinterface to disable WebKit's own Now Playing integration (grep for NowPlaying/MediaSession: nothing). Page's `navigator.mediaSession` drives it automatically.

## Log
Appends JSON lines to `spike/spike-log.jsonl`. Kinds: `start`, `nav.start|finish|fail|failProv`, `popup`, `popup.close`, `process.terminated`, `tick` (every 2s: url, title, mediaSession metadata, playbackState, media elements incl. detached via `play()` hook {currentTime,duration,paused,readyState,src kind}, `fps1`/`fps` = requestMediaKeySystemAccess results, `unsupportedText`, ua). No cookies/credentials logged.

## Preliminary observations
- Launch OK; FairPlay key system access resolves true for both `com.apple.fps.1_0` and `com.apple.fps`; no "unsupported browser" text on landing page; landing redirects to amazon.com/ap/signin.

## Verdict: **GO**

### Evidence (spike/spike-log.jsonl)
- User signed in; a full track (duration ~137s) played past 41s with readyState 4, playbackState "playing" -> not a preview.
- FairPlay `requestMediaKeySystemAccess` resolves for `com.apple.fps` and `com.apple.fps.1_0`. No unsupported-browser text.
- App is ad-hoc signed with only `network.client` entitlement; DRM works without Developer ID, so **Task 13 is not required**.
- Login persisted across quit and relaunch (no redirect to /ap/signin after relaunch; first launch redirected within ~5s).
- Note: spike/spike-log.jsonl contains account-related URLs (sign-in URL query string). Do not share it. The log, the spike app source and its build output have since been deleted.

### WebKit API
**WKWebView in NSViewRepresentable** with `WKUIDelegate.webView(_:createWebViewWith:...)` (popup window shares the configuration). `WebPage` lacks a window.open/createWebView hook. **Task 3 must use this.**

### User agent
Safari UA with Version/27.2 works: `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.2 Safari/605.1.15`. Default UA was not tested by a human; keep Safari UA as default. Derive the user's Safari version at runtime or keep it as a settings override.

### State sources observed
- `navigator.mediaSession.metadata` populated (title, artist, album, artwork array). Artwork URL had a trailing space -> trim it.
- Media element is a VIDEO tag (not AUDIO) with currentTime/duration/paused. An unused AUDIO element also exists (src none), so the bridge must pick the element that has a duration / is not paused.
- `playbackState`: "playing" / "none".

### Now Playing mode
No public API found to disable WebKit's Now Playing. Whether WebKit already publishes an entry, and whether media keys work with no native code, was NOT tested. Decided in Task 6: first test media keys/Control Center with no native code; if WebKit's entry works (play/pause/next/prev via mediaSession action handlers), prefer rely+augment; otherwise use override.

### Popup approach
WKWebView `createWebViewWith` child window implemented, but the actual popup login was not exercised (login worked in place). Untested.

### Hardened runtime
Build set ENABLE_HARDENED_RUNTIME=YES, but `codesign` showed flags 0x2(adhoc) only, so the runtime flag is not verified as applied. Check in Task 2 (ad-hoc may need `OTHER_CODE_SIGN_FLAGS=--options=runtime`).
