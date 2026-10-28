# Up Next queue (bridge 1.5.1)

The menu bar popover ends with a collapsible **Up Next** section. Collapsed (default): the very next song (artwork, title, artist) and a chevron. Expanded: up to 10 upcoming songs, scrolling after ~5 rows. The expanded state persists (`UserDefaults` key `upNextExpanded`). The section is hidden when there is no queue information.

## Where the data comes from

The queue is **not in the DOM** unless Amazon's queue panel is open (the only queue element is the `IconButton,MiniPlayer_PlayQueueButton` button, "View Queue"). `mediaSession` only has the current track. `localStorage` (`*.cloud-queue-store.*`) holds queue items as ids only (no titles) and only a small window.

The web player itself calls a persisted GraphQL query on page load and when the queue changes:

- `POST https://gql.music.amazon.com/` (same origin family the page already uses), `credentials: "include"`
- body: `{"operationName":"QueueView","variables":{"id":<queueId>,"currentEntityReferenceId":<ref>,"isAuthenticated":true,"limit":20,"direction":"FORWARD"},"extensions":{"persistedQuery":{"version":1,"sha256Hash":"e80be83c…"}}}`
- response: `data.queue.view.edges[]`, each `{entityReferenceId, node:{__typename:"Track", title, contributingArtists.edges[].node.name (role PRIMARY), images[{url,width}], …}}`, plus `pageInfo.hasNextPage`. The first edge is the current track; the rest are upcoming.
- `queueId` = `data._currentQueueId` and `ref` = `data.activeEntityReferenceId` from the `cloud-queue-store` localStorage entry.
- headers: the page's own set (`x-api-key`, `csrf-token/-rnd/-ts`, `x-amzn-device-id`, `x-amzn-session-id`, `music-territory`, tier, feature flags, …). The CSRF values equal `window.amznMusic.appConfig.csrf`; device/session/territory equal the other `appConfig` fields.

## How bridge.js does it

`bridge.js` wraps `window.fetch` at document start (knowledge in the `QUEUE` constant next to `SELECTORS`):

1. **Observe:** any request to `https://gql.music.amazon.com` has its headers remembered **in memory in the page**; a `QueueView` FORWARD response is parsed into the cache. The page's own call is the normal source.
2. **Replay:** if the cache can't answer, the bridge calls the same persisted query itself, using the page's remembered headers (CSRF refreshed from `appConfig`). Triggers: the queue id changed or the active entry is not in the cache; fewer than 10 upcoming remain **and** the server has more pages; or the popover opened (`refreshQueue`). At most one call per 4 s, debounced 1.2 s after a change, never for the same (queue, track) twice automatically. Tracks advancing inside the cached list need no call.
3. **Report:** the `state` message gains `queue: [{title, artist, artworkURL}]` (max 10, next first), sent only when it changes. Tokens, cookies and headers never go to Swift, logs, disk or the repo.

Any error, non-OK response, unknown shape, non-`Track` item or unknown active entry yields `queue: null` and the section disappears. If Amazon changes the query, bump `QUEUE.hash` (the page's current hash is visible in its own QueueView requests).

## Next / Previous and track changes (bridge 1.5.1)

Found live: Amazon's own `cloud-queue-store` active entity ref (and `playback-controller`) is a persisted snapshot that **lags a track change by ~3-5 s**, and the page does **not** issue a new `QueueView` on Next/Previous. Keying the list off that ref made Up Next show the just-started track as "next" for several seconds.

Now the playing track is matched **by title** (artist as tie-breaker; the page's artist string can list several artists) against the cached edges, using mediaSession/the player bar, which update immediately. The store ref is only a tie-breaker for duplicate titles. So:
- Next/Previous/natural end/media keys/page buttons that stay inside the cached list re-derive the list on the next state check (~0.1-0.5 s live), with no request.
- If the playing track isn't in the cache (Previous before the cached start, or beyond the 20-entry window) the bridge **extends** the cache: `QueueView` `BACKWARD` from the first cached ref (verified live to return the earlier tracks ending with that ref), then `FORWARD` from the last cached ref, merging the edges. It never needs the lagging store ref. A later attempt falls back to a full snapshot (the store may have caught up). At most 3 attempts per track.
- Triggers: any `trackId` change, and after the `next()`/`previous()` commands at +0.3/+1.2/+3 s. These bypass the 4 s routine throttle but are limited to one request per 0.7 s; rapid clicks coalesce (an in-flight request marks the state dirty and one follow-up runs).
- A snapshot that lacks the playing track never replaces a cache that has it.

Verified live (Debug build): Next x2 and Previous x2 via the app's command path, the same via the page's own player-bar buttons, a natural track end (seek near the end), and Previous past the cached start (cache grew from `Flare…` to `Accelerate, Stardust, Solo, Flare…`). The upcoming list was correct about 0.1-0.6 s after each change.

## Security notes and limits

- **Who may talk to Swift:** `HandlerProxy` accepts a script message only from the **main frame** over **https** whose security-origin host is exactly one of the preset `music.amazon.*` hosts, or the configured start URL's host if that is also `music.amazon.*` (`BridgeOriginPolicy`, exact match, no substring). Anything else is dropped silently.
- **Artwork:** every artwork URL from the bridge (now playing and queue) must be https on `media-amazon.com` / `ssl-images-amazon.com` (exact host or dot-boundary subdomain, no userinfo; `ArtworkPolicy`). Others decode to `nil`. `ArtworkCache` enforces the same check; the live artwork host is `m.media-amazon.com`.
- **Message limits, applied before serialization** (`BridgeMessage.Limits`): arrays are cut to 20 (queue items 20; Swift shows at most 10), strings to 2048 characters, title/artist/album/id to 300, depth to 5; the re-serialized message must be ≤ 64 KB or it is dropped (`.unknown`). Over-limit input is truncated or dropped, never a crash.
- **Transient failures:** a replay times out after 10 s (`AbortController` plus a timer, so a hung request never blocks later ones). Network errors, timeouts and non-OK statuses (429/5xx) keep a snapshot that still matches the page's queue and allow a retry (throttled to one call per 4 s); only an unparseable (schema-changed) response or a snapshot that no longer matches the store hides the section.
- **Hosts:** the observer/replay only trusts `https://gql.music.amazon.com` (`QUEUE.hostRe`). If a regional site uses another gql host, no headers are observed and the section simply stays hidden.
- **Staleness:** a cached snapshot is only used if its queue id equals the page's current queue id (`cloud-queue-store`) **and** the playing track (by title) is in it; otherwise the section hides and a refetch runs (not throttled when the queue itself was replaced). Responses carry a request sequence number: an older response never overwrites a newer snapshot, and a response whose queue id is no longer current is ignored.

## Verified live vs synthetic

Live (signed-in page, Debug build, album playing): the page's own `QueueView` calls on load (BACKWARD and FORWARD, limit 20); header names and that CSRF/device/session/territory match `appConfig`; a replayed call from page context returned the upcoming tracks with titles, artists and artwork; the bridge's passive path produced the list; the list shifted correctly after natural track changes; `refreshQueue()` made exactly one call.

Synthetic: `tools/bridge-test/bridge.test.mjs` (fake data in the captured shape: passive parse, 10 cap, shift on advance, replay headers/body, throttle, other origin ignored, failure hides, no secrets in posted messages); XCTest for decoding and `PlayerState.upNext`.

Not verified live: the SwiftUI section's appearance in the real popover (only previews and unit tests), radio/stations, podcasts, queues with `hasNextPage: true`.

## Limitations

- Needs one observed Amazon gql request before the first replay (happens on page load); the page's own queue call usually fills the cache first.
- Radio/stations, podcasts and ads: expected to hide (items that aren't `Track`, or an unknown active entry); not tested.
- Shuffle: the queue order Amazon reports is shown; not tested with shuffle on.
- Queue edits made elsewhere show up on the next popover open (throttled), not instantly.
- The `persistedQuery` hash and `cloud-queue-store` layout are undocumented and can change.

## Jump to an Up Next song (bridge 1.7.0, hardened in 1.7.1)
Clicking an Up Next row starts that song immediately. In the popover the song area plays it (hover highlight, "Play <title>" tooltip/VoiceOver label, dimmed with a spinner until the track changes or 6 s pass); the chevron toggles expansion (the expanded header still toggles). If jumping isn't available the collapsed row falls back to toggling.

**Mechanism (verified live):** the page's queue panel is unusable here (the "View Queue" button is `disabled`), and Next/Previous/jumping are local player operations (no GraphQL "skip" call; the network only sees `ReportDevicePlayback`/`Transport`/`FetchRemoteQueue` afterwards). The page's queue-row click handler calls

`playbackController.playQueueEntity({ entityPlaybackInstanceId: edge.entityReferenceId, uri: node.playParams.id, duration: node.duration, id: node.id }, Date.now())`

(which calls `queueStore.moveToSpecificQueueEntity(entityPlaybackInstanceId)` and starts playback). `playbackController` is an export of a Metro module in the page's bundle; module ids change per build.

**Finding the controller (1.7.1):** the bridge wraps the bundle's `__d` (Metro `define`, a plain writable global; verified live) at document start and inspects each module's exports right after the *page itself* runs its factory, so nothing extra is executed and it is id-independent (verified live: found with no scan, 0 `__r` calls). Fallbacks, in order: Metro's registry if the runtime exposes `__r.getModules()` (only modules already `isInitialized`; this runtime does not expose it), then, only if the `__d` hook couldn't be installed, a scan of ±200 module ids around a hint (3266), in chunks of ≤8 ms per tick, at most 3 attempts with 5 s / 20 s / 60 s backoff (one more attempt after a track change if 60 s passed). A miss is never cached forever. Measured live: probing the hint takes ~1 ms; 401 unknown ids take ~2 ms. The scan can still initialise modules the page hasn't loaded yet (it is the last resort). Tried and rejected: `playQueueEntity(entityReferenceId)` (restarts the current track), `queueStore.skipTo(ref)` (takes an *index*; passing a ref corrupts the local store pointer, restored with `skipTo(1)` in the Debug session), clicking the panel (disabled), and Next N times (not needed).

Each queue item sent to Swift carries `id` = the entry's `entityReferenceId` (an opaque UUID, not a credential); Swift validates it (<= 100 chars of `[A-Za-z0-9_.:-]`, anything else drops the id and the row isn't clickable) and only validated ids are put into script text. The command `playQueueItem(id)` fails silently (logged) with `invalid_argument`, `busy` (< 0.6 s after the last jump), `unknown_item` (not in the cached queue; a refresh runs), `stale_item` (the entry is the playing track or already played, so the list has moved on), `unsupported_item`, `no_controller`, `jump_failed` or, from Swift, `timeout` (commands are abandoned after 8 s; pending spinners clear after 6 s regardless). State carries `canJumpToQueueItem` (true once the controller was found), so rows only look clickable when it can work.

Verified live (Debug build): jumping to the 1st, 2nd and 3rd upcoming songs (the 3rd is beyond the page's 4-entry local window) played the right song within ~1 s, with Up Next updating (`Melt` → `Dissolve` → `Cerulean` in the test queue). Not verified live: failure paths, shuffle/radio queues, podcasts.

Limitations: it relies on the page's internal module layout (`playbackController.playQueueEntity` and the object shape above); if that changes, `canJumpToQueueItem` stays false and rows fall back to the old behaviour. If the `__d` hook can't be installed (bundle loaded before the bridge) and no registry exists, the capped fallback scan may initialise a few not-yet-loaded modules near the hint.
