# Manual QA checklist

Mark `[x]` and fill `Result:` (PASS/FAIL + notes). Run against the Release build.

## Build & install
```
CONFIG=Release ./scripts/build.sh
rm -rf /Applications/AmazonMusic.app
cp -R build/Build/Products/Release/AmazonMusic.app /Applications/
open /Applications/AmazonMusic.app   # ad-hoc signed: right-click > Open if blocked
```
Build date/commit: ____  macOS: ____  Mode (override/rely): ____

## 1. Login
The app has its own data store: sign in once in this app even if signed in elsewhere.
- [ ] Fresh login (email + password) succeeds. Expect: library/home loads. Result: ____
- [ ] 2FA/captcha prompt completes in-app. Result: ____
- [ ] Popup sign-in (any "Sign in with…"/new-window flow) opens a window and returns to the main view signed in. Result: ____
- [ ] Quit (⌘Q) and relaunch: still signed in. Result: ____
- [ ] Log out, then log in again. Expect: clean sign-out, re-login works. Result: ____

## 2. DRM
- [ ] Full track (>30 s, past the preview mark) plays to the end; not a 30 s preview. Result: ____
- [ ] Seek forward/back within a track works. Result: ____
- [ ] 1 h continuous session: no stalls, auth errors or silent stops. Result: ____
- [ ] Sleep/wake while playing/paused: playback resumes or can be resumed without relaunch. Result: ____

## 3. Media controls (core)
Play a full track first. Run once in **override** (default) and once in **rely** (`AMAZONMUSIC_NOWPLAYING=rely /Applications/AmazonMusic.app/Contents/MacOS/AmazonMusic`). Procedure details: `docs/MEDIA_CONTROLS.md`.

| # | Check (expected) | Override | Rely |
|---|---|---|---|
| 1 | F8 play/pause, F9 next, F7 previous with another app frontmost | ☐ ____ | ☐ ____ |
| 2 | Same keys with the main window closed (app still running) | ☐ ____ | ☐ ____ |
| 3 | Control Center: correct title, artist, album, artwork | ☐ ____ | ☐ ____ |
| 4 | Control Center: progress bar moves; scrub works | ☐ ____ | ☐ ____ |
| 5 | Control Center: play/pause, next, previous work | ☐ ____ | ☐ ____ |
| 6 | AirPods: stem/double-tap play/pause; double = next; triple = previous | ☐ ____ | ☐ ____ |
| 7 | Wired headset button play/pause (and next/prev if supported) | ☐ ____ | ☐ ____ |
| 8 | Disconnect Bluetooth / remove AirPods: playback pauses | ☐ ____ | ☐ ____ |
| 9 | Exactly ONE Now Playing entry for this app (no WebKit duplicate) | ☐ ____ | ☐ ____ |
| 10 | Play audio in Safari and Music, return: keys still control this app | ☐ ____ | ☐ ____ |
| 11 | Sleep/wake, then F8 works | ☐ ____ | ☐ ____ |
| 12 | Reload page / break bridge: entry clears (override); controls recover after reload | ☐ ____ | ☐ ____ |

### Override vs rely A/B decision
- Duplicate entries or misrouted keys in override? ____  Rely fully working (rows 1–12)? ____
- Decision: keep override / switch to rely (change `NowPlayingMode.default`). Result: ____

## 4. Menu bar
- [ ] Mini player shows artwork, title, artist, progress, prev/play-pause/next. Result: ____
- [ ] Controls work; progress scrubs; updates on track change. Result: ____
- [ ] Idle state (nothing playing) is sensible, no crash. Result: ____
- [ ] Popover icon buttons: only two small borderless icon buttons (arrow.up.forward.app = Open Amazon Music, gearshape = Settings) directly under the cover, right-aligned (no separate footer row), secondary colour, subtle hover highlight, tooltips, VoiceOver labels. No Quit button in the popover. Result: ____
- [ ] Right-click the menu bar icon: menu shows Play/Pause (title matches state), Next, Previous, —, Open Amazon Music, Settings…, —, Quit Amazon Music (⌘Q). Left click still toggles the popover. Result: ____
- [ ] Context menu items work with the main window closed (Open reopens it; playback controls act on the bridge; Quit exits). Result: ____

## 5. Notifications
- [ ] ON: permission prompt appears on first use. Note: ad-hoc signing may prevent/alter the prompt or delivery; record behavior. Result: ____
- [ ] Track change posts a notification (title, artist, artwork). Result: ____
- [ ] OFF (Settings): no notifications on track change. Result: ____
- [ ] Notify-when-frontmost: honored per setting (see §8). Result: ____

## 6. Dock menu
- [ ] Right-click Dock icon: shows current track and Play/Pause, Next, Previous. Result: ____
- [ ] Items work and update with track changes. Result: ____

## 7. Window
- [ ] Close (⌘W/red button): music keeps playing, app stays running. Result: ____
- [ ] Reopen (Dock click / menu): same page, no reload, playback uninterrupted. Result: ____
- [ ] Quit (⌘Q): audio stops, app exits. Result: ____
- [ ] Relaunch: window frame (size/position) restored. Result: ____

## 8. Settings
Each: change, observe live effect, quit/relaunch, confirm persisted.
- [ ] Menu bar toggle: icon appears/disappears immediately. Result: ____
- [ ] Notifications toggle: effect per §5. Result: ____
- [ ] Notify-when-frontmost: with app frontmost, notification appears only if enabled. Result: ____
- [ ] UA override: set custom UA; after reload `navigator.userAgent` matches (Web Inspector). Clear restores default. Result: ____
- [ ] Start URL: relaunch opens the new URL. Result: ____
- [ ] Reset website data: signed out; login required again. Result: ____
- [ ] Hide podcasts (General, default OFF): toggle ON with a page loaded. Expected live (no restart): top-nav "Podcasts" tab gone; on `/search/jazz` the "Podcasts"/"Podcast Episodes" filter pills and result shelves gone; podcast cards/links (`/podcasts/...`) gone from Home/Browse shelves. Toggle OFF: everything returns without reload. Quit/relaunch: state persisted and applied on first paint. While playing a podcast episode, the player bar and now-playing UI stay visible. Console (Develop > app): `__amzHideSections.isEnabled("podcasts")`. Independent of Hide Audible. See docs/PODCASTS.md. Result: ____
- [ ] Hide Audible (General, default ON when never set — fresh install/never-touched users now have the Audible-logo nav icon gone; an explicit OFF is kept; independent of Hide podcasts): toggle ON with a page loaded. Expected live: top-nav "Audiobook" tab (the icon-only Audible-logo button, testid TopNavBar_AudiobooksTab) gone at 1100px and ~800px window widths; on `/search/jazz` the "Audiobooks" filter pill and result shelf gone; Podcasts tab/pills unaffected. Toggle OFF: returns without reload. Both toggles on: both tabs gone; turning one off restores only that one. Relaunch: persisted and applied on first paint. Console: `__amzHideSections.isEnabled("audible")`. Result: ____
- [ ] Hide 'Get App' button (General, default ON when never set): the right-hand header "Get App" button (testid `Button,GetAppButton`) is gone on first paint, after navigating (Home, search, Library) and after reload; search icon, account avatar and player bar remain. Toggle OFF: button returns live; ON: hidden again. Relaunch: persisted. Console: `__amzHideSections.isEnabled("getApp")`. Result: ____
- [ ] Hide Home page banner (General, default ON when never set): Home (`/`) top hero/promo carousel (testid `BrowseHome_Top_Recommender`) is gone with no empty gap (first shelf directly under the nav) after launch, reload and navigating Library → Home; other pages and shelves (Recently played, playlists), nav, search, player unaffected. Toggle OFF: banner returns live; ON: hidden again. Relaunch: persisted. Console: `__amzHideSections.isEnabled("homeBanner")`. Result: ____
- [ ] Menu bar popover: compact ~340×168pt horizontal card, layout like Amazon Music's player bar. Top-right icon row (~14pt from the card edge, ~10pt apart, ~26×24pt hit targets), left to right: open-app, settings (no heart there; no Quit; Quit is only in the right-click menu). Left column top-to-bottom: 19pt title (max 2 lines, truncating) and artist, slim scrubbable progress with elapsed left / remaining right, then ONE row of five evenly spread solid semibold glyphs: Repeat, Previous (skip-back bar), Play/Pause (largest), Next, Shuffle. ~120pt square cover on the right below the icons, with a circular heart badge overlaid at its bottom-right (see Like section). Paused state does not tick the time; no-track state shows placeholder cover + "Nothing playing" / sign-in text with all five controls dimmed/disabled. Result: ____

## 9. Bridge (graceful degradation)
Resource: `Sources/AmazonMusic/Resources/bridge.js`.
- [ ] Web Inspector (Develop menu > app) console, while playing: `__amzBridge.toggle()` pauses/resumes; `__amzBridge.next()` skips; `__amzBridge.seek(30)` jumps to 0:30. (Task 4 left this for human verification.) Result: ____
- [ ] Break a selector: in `bridge.js` edit entries of `SELECTORS` (e.g. `title`, `artwork`) to nonexistent selectors, rebuild, play. Expected: no crash/exceptions loop; the missing field is blank/omitted, other metadata and controls still work; app marks bridge unhealthy as designed. Result: ____
- [ ] Revert the edit and rebuild; metadata returns. Result: ____

### Next / Previous (bridge 1.2.0)
Play an album/playlist with several tracks first (skip limits on free tiers may apply). Each item: track actually changes, Amazon's player bar follows, popover/Now Playing update within ~2 s. Check Console.app (subsystem `com.khalidabuhakmeh.amazonmusic`, category `bridge`) for `command next ok via=mediaSession changed=true`; any failure logs `command ... failed: <reason>`.
- [ ] Popover Next: skips to the next track. Result: ____
- [ ] Popover Previous after >3 s into a track: restarts the current track (the page's own behaviour); pressing again within 3 s goes to the previous track. Result: ____
- [ ] Dock menu (right-click Dock icon) Next and Previous behave as above. Result: ____
- [ ] Menu bar item right-click menu Next and Previous behave as above. Result: ____
- [ ] Media keys F9 (next) and F7 (previous) behave as above, also with the window closed. Result: ____
- [ ] Control Center / AirPods next/previous behave as above. Result: ____
- [ ] Last track of a queue with repeat off, Next: no crash; log shows `changed=false` or a failure reason (not silent). Result: ____
- [ ] Console: `await __amzBridge.next()` resolves `{ok:true,via:"mediaSession",changed:true}`; `await __amzBridge.previous()` likewise. Result: ____

## 10. Deferred (after Task 13)
- [ ] Notarized build passes Gatekeeper (`spctl -a -vv`, opens without warning). Result: ____
- [ ] Launches on a clean user account (sign in fresh). Result: ____
- [ ] DRM full-track playback works under Developer ID signing. Result: ____

## Like (heart)
- [ ] Play a track: the heart badge overlaid on the bottom-right corner of the popover cover (dark translucent circle, ~6pt inset) matches Amazon's player-bar heart (outline = not liked, red filled = liked).
- [ ] Liked = red filled heart, always visible. Not liked = white outline at ~70% opacity, full opacity on hover (discoverable without hover). Legible on bright and dark artwork. Clicking elsewhere on the cover does nothing; double-click on the cover toggles like.
- [ ] Click the heart badge in the popover: it flips instantly; the Amazon player bar heart flips within a few seconds; popover stays consistent (no flicker back).
- [ ] Toggle the heart in Amazon's own UI: the popover heart follows within ~2 s.
- [ ] Change track: heart reflects the new track's state.
- [ ] Right-click the menu bar item: "Like"/"Unlike" matches state and toggles it.
- [ ] Heart badge (no heart on the cover at all) and menu item are absent when no like control exists (e.g. nothing loaded, podcast/ad, signed out); nothing else breaks.
- [ ] Help tooltip says "Like"/"Unlike"; VoiceOver reads the same label.
- [ ] Restore any track you liked while testing.

## Shuffle / Repeat (bridge 1.3.0; details in docs/CONTROLS.md)
- [ ] Popover row order is Repeat, Previous, Play/Pause, Next, Shuffle, evenly spaced; glyphs solid/bold (skip glyphs `backward.end.fill`/`forward.end.fill`, `pause.fill`/`play.fill`), play/pause visibly the largest. Result: ____
- [ ] Shuffle off in Amazon's bar: popover shuffle glyph is dim (~50%). Click it: glyph turns accent colour instantly; Amazon's shuffle icon turns cyan; popover stays consistent. Click again: off. Result: ____
- [ ] Repeat: click cycles off -> all (accent `repeat`) -> one (accent `repeat.1`) -> off, matching Amazon's own icon (which shows a "1" icon for repeat one). Result: ____
- [ ] Toggle shuffle/repeat in Amazon's own UI: popover follows within ~2 s. Change track: state stays correct. Result: ____
- [ ] Right-click the menu bar item: "Turn Shuffle On/Off" and "Repeat All" / "Repeat One" / "Turn Repeat Off" (names the click's effect) change the state. Result: ____
- [ ] No player bar loaded (nothing playing / signed out): Shuffle/Repeat dimmed and disabled, menu items absent, nothing else breaks. Result: ____
- [ ] Tooltips ("Shuffle: off (click to turn on)", "Repeat: all (click to repeat one)", ...) and VoiceOver labels ("Shuffle", value On/Off; "Repeat", value Off/All/One). Result: ____
- [ ] Restore your shuffle/repeat settings after testing.
