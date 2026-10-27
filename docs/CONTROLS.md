# Transport controls: Shuffle / Repeat and the popover control row

Investigated 2026-10-27 in the spike app (signed in, Safari UA, temporary `SPIKE_PROBE=1` file-driven eval loop; probe files deleted afterwards).
No account names, library contents or listening history were recorded.

## Real page: player bar (react-native-web, hashed classes are unusable)
Both controls are `div[role="togglebutton"][tabindex=0]`, **not** `<button>`, and are `el.click()`-able:
- Shuffle: `[data-testid="IconButton,MiniPlayer_ShuffleButton"]`, `aria-label="Shuffle"` (never changes).
- Repeat: `[data-testid="IconButton,MiniPlayer_LoopButton"]`, `aria-label` changes.
- Neither exposes `aria-pressed` / `aria-checked`, and the testid does not change with state (unlike the like button).

### Where the state lives
| Control state | icon `<path>` fill | icon | repeat `aria-label` |
|---|---|---|---|
| Shuffle off | `rgb(255,255,255)` | shuffle (1 path) | `Shuffle` |
| Shuffle on | `rgb(37,209,218)` (accent cyan) | same path | `Shuffle` |
| Repeat off | white | loop (1 path) | `Repeat` |
| Repeat all | accent | same loop path | `Repeat Once` |
| Repeat one | accent | **different icon, 3 paths** ("1" variant) | `Repeat Off` |

Click order of repeat: off -> all -> one -> off (3 clicks return to the start). **The repeat `aria-label` names the NEXT action, not the state**
(`Repeat Once` is shown while repeat-all is active), so it is misleading like the like button's label and is used only as a last-resort tie-break.

## Bridge 1.3.0
- `SELECTORS.shuffleButton`, `repeatButton`, `toggleIconPath` (selectors only live there).
- `state.shuffle`: `true | false | null`; `state.repeat`: `'off' | 'all' | 'one' | null`. null = no control / unreadable (never guessed).
  - aria-pressed/aria-checked are honoured first if Amazon ever adds them (shuffle), otherwise the computed `fill` of the icon path:
    saturated colour (max-min of RGB > 40) = on, white/grey = off.
  - repeat one = active **and** (more than one `<path>` **or** label matches `/off/i`), otherwise all.
- `__amzBridge.toggleShuffle()` / `cycleRepeat()` -> `{ok:true,via:"dom"}` or `{ok:false,reason:"no_shuffle_control"|"no_repeat_control"|"shuffle_failed"|"repeat_failed"}`.
  State re-checks run after 0.25 s, 0.6 s and 1.5 s so the change is pushed shortly after the page re-renders.
- Fragility: colour-based detection breaks if Amazon changes the active colour to near-white or greys. Then `shuffle/repeat` would read off permanently (not crash); update `iconActive`.

## Swift
- `BridgeMessage.StatePayload.shuffle: Bool?`, `.repeatMode: RepeatMode?` (JSON key `repeat`); missing / wrong type / unknown string -> nil (older bridges decode fine).
- `RepeatMode` (`off/all/one`, `.next` = the page's click order).
- `PlayerState.isShuffled`, `repeatMode`: optimistic value for 3 s (same rules as like: confirmed / unknown report / track change / deadline clears it; stale reports inside the window ignored).
  `beginOptimisticShuffle/Repeat`, `clearOptimistic...`; `PlayerBridge.toggleShuffle()/cycleRepeat()`; `PlayerCommand.toggleShuffle/.cycleRepeat`.
- nil => button dimmed + disabled in the popover; status item menu entries absent.
- Status item menu (titles name the effect): "Turn Shuffle On/Off"; "Repeat All" / "Repeat One" / "Turn Repeat Off".

## Popover layout (340pt wide, 168pt tall)
Top row (right aligned): heart (hidden if like unknown), open app, settings. Left column: title+artist, progress (TimelineView only here, paused when not playing/scrubbing),
row of five equal slots: `repeat`/`repeat.1` (14pt), `backward.end.fill` (16pt), `pause.fill`/`play.fill` (20pt), `forward.end.fill` (16pt), `shuffle` (14pt), all `.semibold`.
Toggles: accent colour when on, secondary @50% when off. No-track: all five dimmed and disabled. Rendered offscreen (ImageRenderer, dark background) for playing/paused/repeat-one/no-track/long title/like-unknown and visually checked.

## Verification and what was real vs mock
- **Real page (spike, injected the actual bridge.js 1.3.0 via the probe loop):** `getState()` read `{shuffle:false, repeat:'off'}`; `toggleShuffle()` -> true -> `toggleShuffle()` -> false;
  `cycleRepeat()` x3 -> `'all'`, `'one'`, `'off'`. All commands returned `{ok:true,via:"dom"}`. Earlier raw DOM probes (clicks on the real buttons) established the table above.
  **Account changes: shuffle toggled on and off twice, repeat cycled through 2 full cycles in total (one raw probe, one bridge). Original state (shuffle off, repeat off) restored and confirmed after each.** A track was loaded (paused) at the time.
- **Mock only:** node tests (`tools/bridge-test`) use a fake DOM; the Swift optimistic/reconciliation logic is unit tested; the SwiftUI popover was rendered offscreen with synthetic state and no artwork.
- **Not verified:** the real app's WKWebView message channel for these fields (spike has no `amazonMusic` handler; the same script ran, `post()` is a no-op there); behaviour while audio is actually playing (state read while paused),
  with podcasts/ads (controls may be absent -> null), queue-less or radio stations (repeat/shuffle may be disabled by Amazon; the disabled look is not detected); the clicked-in-app popover and menu interaction were not hand-tested.
