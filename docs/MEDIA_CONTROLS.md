# Media controls (Now Playing / remote commands)

Implemented in `Sources/AmazonMusic/Integrations/NowPlayingController.swift`.

## Modes
- **override (default)**: native code registers play, pause, togglePlayPause, nextTrack, previousTrack, changePlaybackPosition on `MPRemoteCommandCenter` (each calls `PlayerBridge.send`) and publishes `MPNowPlayingInfoCenter` (title/artist/album/artwork/duration/elapsed/rate, playbackState). Skip/seek-by-interval and other commands are disabled. Elapsed time is only written on play/pause/track change/seek/wake, never per tick.
- **rely**: registers nothing; WebKit's own session (from the page's `navigator.mediaSession`) handles keys. Select with `AMAZONMUSIC_NOWPLAYING=rely`.

## Residual risk
No public API disables WebKit's own Now Playing publication. In override mode WebKit's entry may still appear (duplicate entry in Control Center) or compete for media keys. Not verifiable by automated tests; needs the human A/B test below. If override shows duplicates/misrouted keys, use rely mode (change `NowPlayingMode.default`).

## Human A/B steps (run for each mode)
Override: launch app normally. Rely: `AMAZONMUSIC_NOWPLAYING=rely build/Build/Products/Debug/AmazonMusic.app/Contents/MacOS/AmazonMusic`.
Play a full track, then:
1. F8 play/pause, F9 next, F7 previous with another app frontmost.
2. Close the app window (app still running), repeat F7/F8/F9.
3. Control Center / menu bar Now Playing: count entries for this app (expect exactly one); check title, artist, artwork, progress bar, scrubbing, play/pause/next/previous.
4. AirPods: play/pause, double-tap next, triple-tap previous. Wired headset button too.
5. Disconnect Bluetooth headphones: playback should pause.
6. Play audio in Safari/Music, then return; keys should still control this app.
7. Sleep/wake the Mac; repeat F8.
8. Reload page / break bridge: Now Playing entry should clear (override).
Record: which mode works, entry count, any key misrouting.

## Next / Previous (bridge 1.2.0)
- Root cause of the dead buttons: the old bridge patched `setActionHandler` on the `navigator.mediaSession` *instance* only; in WKWebView that patch did not take effect (`hasOwnProperty` false, `__amzHooked` unset), so the page's `nexttrack`/`previoustrack` handlers were never captured, and the fallback SELECTORS (`transport-next` etc.) were placeholders that match nothing. Result `{ok:false, reason:"no_nexttrack_control"}`, and Swift discarded it.
- Fix: patch `MediaSession.prototype.setActionHandler` (instance as fallback); `next()`/`previous()` are async: call the captured handler, verify a track change or position reset within 1.5 s, else click the real player-bar button (`IconButton,MiniPlayer_NextButton` / `IconButton,MiniPlayer_PreviousButton`, plus aria-label fallbacks scoped to MiniPlayer). Returns `{ok, via, changed}` or `{ok:false, reason}`.
- Previous: Amazon's own handler/button restarts the track when past ~3 s and goes back otherwise (observed on the real page). We do exactly what the page does; no `seek(0)` emulation.
- Swift: `PlayerBridge.send` returns `CommandResult`, awaits via `callAsyncJavaScript` (JSON string), and logs every command result (category `bridge`).
