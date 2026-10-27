# Like (heart) button — DOM findings and design

Investigated 2026-10-27 with the spike app (signed in, Safari UA; temporary `SPIKE_PROBE=1` file-driven eval loop, spike dir only).
No account names, library contents or listening history were recorded.

## Real page (react-native-web, no shadow DOM, hashed class names: unusable)
The player bar ("MiniPlayer") is present whenever a track is loaded (even paused / after reload); it is a plain `<button>`.
- Not liked: `button[data-testid="IconButton,MiniPlayer_Follow_Follow"]`, outline heart svg (2 subpaths), white fill.
- Liked: `button[data-testid="IconButton,MiniPlayer_Follow_Unfollow"]`, filled heart svg (1 subpath), accent-coloured fill.
- **State lives in the data-testid (`Follow` vs `Unfollow`)**. No `aria-pressed` / `aria-checked` on the real control.
  `aria-label` is a past-tense confirmation, not state: `Liked <title>` while *not* liked, `Unliked` while liked, so it is not used.
- The same pattern exists elsewhere: track page toolbar `Toolbar_FollowButton_(Follow|Unfollow)` (labels `Like`/`Unlike`), track rows `TrackLike_Follow`.
- The control always acts on the **currently playing** track (it sits next to `MiniPlayer_Title`).
- Toggle takes ~1-4 s to flip the testid after click (server round trip).

## Bridge (1.1.0)
- `SELECTORS.likeButton` / `unlikeButton` (testid variants) + `likeToggleAria` (`aria-pressed` fallback if Amazon changes markup).
- `state.liked`: `true` (unlike button present) / `false` (like button present) / aria-pressed fallback / `null` unknown. Never guessed.
- `window.__amzBridge.toggleLike() | like() | unlike()` -> `{ok:true,via:"dom"}` or `{ok:false,reason}`
  (`no_like_control`, `unknown_like_state` for like()/unlike() when state is unknown). like()/unlike() are idempotent (no click when already in state).
  Extra state checks run 0.6 s and 1.5 s after a click so `liked` is pushed soon after the page flips.

## Swift
`BridgeMessage.StatePayload.liked: Bool?` (optional, old bridges decode as nil); `PlayerState.isLiked` = optimistic value while a toggle is in flight
(3 s window) else page value; stale reports inside the window are ignored; mismatch after the window, command failure or a track change drops the optimistic value.
`isLiked == nil` hides the heart and the menu item. `TrackInfo` identity is untouched. Status item menu shows "Like"/"Unlike" when known.

## Verification performed
- Real page (spike): read state of the player-bar button in both states (via a reversible round trip, see below); `bridge.js` 1.1.0 injected in the live page:
  `getState().liked` false -> `like()` -> true -> `unlike()` -> false; `unlike()` when already unliked is a no-op. Not tested in the real app WebView with its message channel
  (spike has no `amazonMusic` handler), but the identical script was used.
- **Account changes made:** on a single track, 3 like->unlike round trips (toolbar button, player-bar button, bridge commands). Original state (not liked) restored and confirmed each time.
- Not verified: behaviour for podcast episodes / audiobooks / ads (control may be absent -> `liked: null`), liked-state of a *playing* (vs loaded) track.
