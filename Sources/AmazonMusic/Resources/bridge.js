// Amazon Music bridge: observes player state, executes commands.
// Injected at document start, main frame only. Never throws.
(function () {
  "use strict";
  const BRIDGE_VERSION = "1.7.1";

  // The ONLY place DOM selectors live. Last-resort fallbacks; adjust here if the site changes.
  const SELECTORS = {
    // Player bar (verified on the real page): title <a data-testid=MiniPlayer_Title aria-label=...>; artist/album are <a href="/artists/..">
    // and <a href="/albums/.."> in the same block (aria-label = name), found by playerBarLink() scoped to the title's block (NOT page-wide).
    // These DOM values are the fallback when mediaSession has no metadata yet (loaded-but-paused track right after launch).
    title: ['a[data-testid="MiniPlayer_Title"]', '[data-testid="player-title"]', "music-horizontal-item.queue-now-playing [slot=primary-text]"],
    artist: ['[data-testid="player-artist"]'],
    album: ['[data-testid="player-album"]'],
    barArtistLink: ['a[href^="/artists/"]'],
    barAlbumLink: ['a[href^="/albums/"]'],
    artwork: ['[data-testid="ListItemImage,MiniPlayer_Image"] img', '[data-testid="player-artwork"] img'],
    // Playback position/duration persisted by the page (localStorage "...playback-controller...": data.currentTimeInSeconds, data.duration);
    // the fallback for a loaded-but-paused track whose media element has no duration yet.
    playbackStoreKey: /playback-controller/,
    // Signed-out signals: sign-in URL paths; signed in = appConfig.customerId present (window.amznMusic.appConfig from config.json).
    signInPath: /\/ap\/(signin|register)|\/signin(\/|$)/i,
    // Player-bar transport buttons (verified on the real page: IconButton,MiniPlayer_{Play,Pause,PreviousButton,NextButton}).
    playButton: ['button[data-testid="IconButton,MiniPlayer_Play"]', '[data-testid*="MiniPlayer"][aria-label="Play" i]'],
    pauseButton: ['button[data-testid="IconButton,MiniPlayer_Pause"]', '[data-testid*="MiniPlayer"][aria-label="Pause" i]'],
    nextButton: ['button[data-testid="IconButton,MiniPlayer_NextButton"]', '[data-testid*="MiniPlayer"][aria-label="Next" i]'],
    // Like (heart) control in the player bar. The testid encodes the state: *_Follow = not liked (click to like),
    // *_Unfollow = liked (click to unlike). Fallback: any player-bar like button exposing aria-pressed.
    likeButton: ['button[data-testid="IconButton,MiniPlayer_Follow_Follow"]'],
    unlikeButton: ['button[data-testid="IconButton,MiniPlayer_Follow_Unfollow"]'],
    likeToggleAria: ['[data-testid*="MiniPlayer"][data-testid*="Like"][aria-pressed]', '[data-testid*="MiniPlayer"][data-testid*="Follow"][aria-pressed]'],
    // Shuffle / repeat (div role=togglebutton, NOT a <button>; verified on the real page). State is NOT in aria-*: it is the icon's
    // fill colour (white = off, accent = on) and, for repeat-one, a different icon (several <path>s). aria-label names the NEXT action
    // ("Repeat" -> off, "Repeat Once" -> all is active, "Repeat Off" -> one is active), so it is only a last-resort hint.
    shuffleButton: ['[data-testid="IconButton,MiniPlayer_ShuffleButton"]', '[data-testid*="MiniPlayer"][data-testid*="Shuffle"]'],
    repeatButton: ['[data-testid="IconButton,MiniPlayer_LoopButton"]', '[data-testid*="MiniPlayer"][data-testid*="Loop"]', '[data-testid*="MiniPlayer"][data-testid*="Repeat"]'],
    // Player-bar "..." menu (verified on the real page): the button opens a portal menu (fixed <div> child of <body> holding
    // [role=menu] > [role=menuitem]); the items exist ONLY while it is open. "Play Similar Music" is one of them; clicking it makes the
    // page run its own CreateRemoteQueue(startAsStation:true) and switch playback (replaying that call alone would not switch the player).
    moreButton: ['button[data-testid="IconButton,MiniPlayer_ContextMenu"]'],
    menuRoot: ['[role="menu"]'],
    menuItem: ['[role="menuitem"]'],
    // Language-independent: the menu item sits in a wrapper with data-testid "OverflowMenu_Option_PlaySimilar" (verified live, en).
    // Fallback: the localized label (en/de/fr/es/it/pt/ja, one per regional preset language; non-English entries are NOT live-verified).
    similarItemTestId: '[data-testid="OverflowMenu_Option_PlaySimilar"]',
    similarLabel: /play similar|ähnliche musik|musique similaire|música similar|musica simile|música semelhante|似た(音楽|曲)/i,
    toggleIconPath: ["svg path", "path"],
    previousButton: ['button[data-testid="IconButton,MiniPlayer_PreviousButton"]', '[data-testid*="MiniPlayer"][aria-label="Previous" i]'],
  };

  // Up Next queue (docs/QUEUE.md). The page itself calls this persisted GraphQL query (operation QueueView, FORWARD) on load; we
  // observe those responses and, when needed, replay the same call from the page with the page's OWN request headers
  // (kept in memory here, never sent to Swift, never logged). Only the parsed {title, artist, artworkURL} list leaves the page.
  const QUEUE = {
    hostRe: /^https:\/\/gql\.music\.amazon\.com(\/|$)/,
    operation: "QueueView",
    hash: "e80be83c966f681904ddcf1ef1888afb3c1ef2fb866da063864fe5c1de57f76f", // persistedQuery sha256Hash (changes if Amazon ships a new query)
    storeKeyRe: /cloud-queue-store/, // localStorage: data._currentQueueId, data.activeEntityReferenceId
    limit: 20, // edges requested (current + upcoming)
    max: 10, // upcoming tracks reported to Swift
    lowWater: 10, // refetch on track change when fewer than this many upcoming remain in the cache
    timeoutMs: 10000, // a hung replay must not block later ones
    minGapMs: 4000, // routine refreshes (low water, popover) never call more often than this
    kickGapMs: 700, // refresh caused by a track change / next / previous: at most this often (rapid clicks coalesce)
    // In-page player (verified live): Metro module exporting `playbackController`; the queue panel's row click calls
    // playbackController.playQueueEntity({entityPlaybackInstanceId: edge.entityReferenceId, uri: node.playParams.id, duration, id: node.id}, Date.now()).
    // Module ids change per build. Preferred: capture the export when the page itself initialises the module (a wrapper around the
    // bundle's __d installed at document start; executes nothing extra). Fallbacks: Metro's registry if exposed, else a small chunked
    // scan of +-controllerScanRadius ids around the hint (this can initialise modules the page hasn't yet; capped, backed off, max 3 tries).
    controllerModuleHint: 3266, controllerScanRadius: 200, scanBudgetMs: 8, jumpGapMs: 600,
    maxMissTries: 3, // per track: attempts to find the playing track in the queue before giving up
  };

  try {
    if (window.top !== window) return;
    if (window.__amzBridge && window.__amzBridge.version) return; // idempotent
  } catch (e) { return; }

  const DEBUG = () => !!window.__amzBridgeDebug;
  const handlers = {}; // captured mediaSession action handlers
  const detached = new Set(); // media elements seen via play() hook
  let lastStateJSON = null;
  let lastPositionAt = 0;
  let debounceTimer = null;

  function post(type, payload) {
    try {
      const h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.amazonMusic;
      if (!h) return false;
      h.postMessage({ v: 1, type: type, payload: payload });
      return true;
    } catch (e) { return false; }
  }
  function log(msg) { if (DEBUG()) post("log", { message: String(msg) }); }
  function err(code, message) { post("error", { code: code, message: String(message) }); }
  function safe(fn, fallback) {
    try { const r = fn(); return r === undefined ? fallback : r; } catch (e) { return fallback; }
  }
  const finite = (n) => (typeof n === "number" && isFinite(n) ? n : null);
  const str = (s) => (typeof s === "string" && s.trim() !== "" ? s.trim() : null);

  // --- hooks (installed at document start) ---
  // The page registers handlers via navigator.mediaSession.setActionHandler. Patch the PROTOTYPE (an instance-only patch
  // was observed NOT to take effect in WKWebView, so handlers were never captured) and, as a fallback, the instance.
  function makeHook(orig) {
    const hooked = function (action, handler) {
      try { if (typeof handler === "function") handlers[action] = handler; else delete handlers[action]; } catch (e) {}
      return orig.apply(this, arguments);
    };
    hooked.__amzHooked = true;
    return hooked;
  }
  safe(() => {
    const proto = window.MediaSession && window.MediaSession.prototype;
    if (proto && typeof proto.setActionHandler === "function" && !proto.setActionHandler.__amzHooked) {
      proto.setActionHandler = makeHook(proto.setActionHandler);
    }
  });
  safe(() => {
    const ms = navigator.mediaSession;
    if (ms && typeof ms.setActionHandler === "function" && !ms.setActionHandler.__amzHooked) {
      ms.setActionHandler = makeHook(ms.setActionHandler);
    }
  });
  safe(() => {
    const proto = window.HTMLMediaElement && window.HTMLMediaElement.prototype;
    if (proto && typeof proto.play === "function" && !proto.play.__amzHooked) {
      const orig = proto.play;
      const hooked = function () {
        try { detached.add(this); attach(this); scheduleCheck(); } catch (e) {}
        return orig.apply(this, arguments);
      };
      hooked.__amzHooked = true;
      proto.play = hooked;
    }
  });

  // Capture the page's playback controller as the PAGE initialises its module: wrap the bundle's `__d` (Metro define) at document start
  // so each factory's exports are inspected right after it runs. Nothing is executed that the page wasn't going to run.
  let capturedPC = null, defineHookActive = false;
  const isController = (c) => !!c && typeof c.playQueueEntity === "function";
  safe(() => {
    if (Object.getOwnPropertyDescriptor(window, "__d")) { // bundle already loaded: too late, use the fallbacks
      return;
    }
    let realD;
    const wrapFactory = (factory) => {
      if (typeof factory !== "function") return factory;
      return function () {
        const r = factory.apply(this, arguments);
        try {
          const ex = arguments[4] && arguments[4].exports;
          if (ex && isController(ex.playbackController)) { capturedPC = ex.playbackController; scheduleCheck(); }
        } catch (e) {}
        return r;
      };
    };
    Object.defineProperty(window, "__d", {
      configurable: true, enumerable: true,
      get() { return realD; },
      set(v) {
        if (typeof v === "function" && !v.__amzHooked) {
          const wrapped = function (factory) { const a = Array.prototype.slice.call(arguments); a[0] = wrapFactory(factory); return v.apply(this, a); };
          try { Object.assign(wrapped, v); } catch (e) {}
          wrapped.__amzHooked = true;
          realD = wrapped;
        } else realD = v;
      },
    });
    defineHookActive = true;
  });

  // --- queue: observe + replay the page's own QueueView call ---
  let gqlURL = null, gqlHeaders = null; // in memory only
  let queueAll = null; // [{ref, title, artist, artworkURL}] as last fetched (current track + upcoming)
  let qGen = 0, appliedGen = 0, lastIdx = 0, qDirty = false, missTries = 0, lastTrackSeen = null, kickTimer = null;
  let queueId = null, queueHasNext = false, lastFetchKey = null, qInFlight = false, lastQFetch = 0, qTimer = null;
  const origFetch = safe(() => (typeof window.fetch === "function" ? window.fetch : null), null);

  function headersToObject(h) {
    if (!h) return null;
    return safe(() => {
      if (typeof h.entries === "function" && !Array.isArray(h)) return Object.fromEntries(Array.from(h.entries()));
      if (Array.isArray(h)) return Object.fromEntries(h);
      return Object.assign({}, h);
    }, null);
  }
  function readQueueStore() {
    return safe(() => {
      const k = Object.keys(window.localStorage).find((x) => QUEUE.storeKeyRe.test(x));
      const d = k ? JSON.parse(window.localStorage.getItem(k)).data : null;
      const id = d && str(d._currentQueueId), ref = d && str(d.activeEntityReferenceId);
      return id && ref ? { queueId: id, ref: ref } : null;
    }, null);
  }
  // QueueView JSON -> [{ref,title,artist,artworkURL}] (null if the shape is not recognised).
  function parseQueueEdges(json) {
    return safe(() => {
      const edges = json.data.queue.view.edges;
      if (!Array.isArray(edges)) return null;
      const out = [];
      for (const e of edges) {
        const n = e && e.node;
        const ref = e && str(e.entityReferenceId);
        if (!n || !ref || n.__typename !== "Track") { out.push({ ref: ref, title: null }); continue; } // non-track (podcast/ad): not listed
        const arts = safe(() => n.contributingArtists.edges, []) || [];
        const primary = arts.find((a) => a && a.role === "PRIMARY") || arts[0];
        const imgs = (Array.isArray(n.images) ? n.images : []).filter((i) => i && str(i.url)).sort((a, b) => (a.width || 0) - (b.width || 0));
        const img = imgs.find((i) => (i.width || 0) >= 120) || imgs[imgs.length - 1];
        out.push({ ref: ref, title: str(n.title) || str(n.shortTitle), artist: primary && primary.node ? str(primary.node.name) : null, artworkURL: img ? absURL(img.url) : null,
          id: str(n.id), uri: str(safe(() => n.playParams.id, null)) || str(n.uri), duration: finite(n.duration) });
      }
      return out;
    }, null);
  }
  // The playing track as the page shows it right now (mediaSession, else the player bar). This is the freshest source: the
  // localStorage store's active entity ref is a persisted snapshot that lags a track change by ~3-5 s, so it is only a tie-breaker.
  function currentNames() {
    const ms = safe(readMediaSession, null);
    const dom = ms && ms.title ? null : safe(readDOM, null);
    return { title: (ms && ms.title) || (dom && dom.title) || null, artist: (ms && ms.artist) || (dom && dom.artist) || null };
  }
  // Index of the playing track in the cached edges, matched by title (artist as tie-breaker; the page's artist string may list
  // several artists while edges carry the primary one). -1 if absent (e.g. went Previous past the cached start).
  function matchIndex(cur) {
    if (!queueAll || !cur || !cur.title) return -1;
    const cands = [];
    queueAll.forEach((x, i) => { if (x.title === cur.title) cands.push(i); });
    if (!cands.length) return -1;
    const artistOk = (i) => { const a = queueAll[i].artist; return !a || !cur.artist || cur.artist.indexOf(a) >= 0 || a.indexOf(cur.artist) >= 0; };
    const good = cands.filter(artistOk);
    const pool = good.length ? good : cands;
    const st = readQueueStore();
    const byRef = st ? pool.find((i) => queueAll[i].ref === st.ref) : undefined;
    if (byRef !== undefined) return (lastIdx = byRef);
    const after = pool.find((i) => i >= lastIdx);
    return (lastIdx = after !== undefined ? after : pool[0]);
  }
  // Upcoming = tracks after the playing track. null when it isn't in the cached list (different queue, radio, podcast...).
  function upcomingQueue() {
    if (!queueAll) return null;
    const st = readQueueStore();
    if (!st) return null;
    if (queueId !== st.queueId) return null; // snapshot belongs to a different (replaced) queue, even if entity refs coincide
    const idx = matchIndex(currentNames());
    if (idx < 0) return null;
    const items = [];
    for (const x of queueAll.slice(idx + 1)) {
      if (!x.title) break; // stop at the first unknown item rather than skipping it
      items.push({ id: x.ref || null, title: x.title, artist: x.artist || null, artworkURL: x.artworkURL || null });
      if (items.length >= QUEUE.max) break;
    }
    return items.length ? items : null;
  }
  function observeFetch(input, init, p) {
    const url = typeof input === "string" ? input : input && input.url;
    if (!url || !QUEUE.hostRe.test(url)) return;
    const hdrs = headersToObject((init && init.headers) || (input && input.headers));
    if (hdrs && Object.keys(hdrs).length) { gqlHeaders = hdrs; gqlURL = String(url).split("?")[0]; }
    const body = init && typeof init.body === "string" ? init.body : null;
    if (!body || body.indexOf('"' + QUEUE.operation + '"') < 0 || body.indexOf('"FORWARD"') < 0) return;
    const gen = ++qGen; // order of REQUEST start, so a late older response can't replace a newer snapshot
    p.then((r) => r.clone().json()).then((j) => {
      if (parseQueueEdges(j) && applyQueueResponse(j, gen, false)) scheduleCheck();
    }).catch(() => {});
  }
  // Applies a QueueView response unless it is older than what's already applied or belongs to a queue that is no longer current.
  // j == null (request failed) clears the snapshot when hideOnFail. Returns whether the cache changed.
  function applyQueueResponse(j, gen, hideOnFail) {
    if (gen < appliedGen) return false;
    const all = j ? parseQueueEdges(j) : null;
    if (!all) { if (!hideOnFail) return false; appliedGen = gen; queueAll = null; queueId = null; queueHasNext = false; return true; }
    const rid = safe(() => j.data.queue.id, null);
    const st = readQueueStore();
    if (!rid || !st || rid !== st.queueId) return false;
    // A snapshot built from a lagging store ref (e.g. right after Previous) can start AFTER the playing track; never replace a cache
    // that contains the playing track with one that doesn't.
    {
      const names = currentNames();
      if (names.title && queueAll && queueId === rid && matchIndex(names) >= 0 && !all.some((x) => x.title === names.title)) return false;
    }
    appliedGen = gen; queueAll = all; queueId = rid; lastIdx = 0;
    queueHasNext = !!safe(() => j.data.queue.view.pageInfo.hasNextPage, false);
    lastQFetch = Date.now();
    return true;
  }
  // One QueueView call with the page's own headers (10 s timeout). Resolves to the parsed JSON; rejects on network/timeout/non-OK.
  async function queueRequest(qid, ref, direction) {
    const hdr = Object.assign({}, gqlHeaders);
    const csrf = safe(() => window.amznMusic.appConfig.csrf, null); // freshest tokens the page holds
    if (csrf && hdr["csrf-token"] && csrf.token) { hdr["csrf-token"] = csrf.token; hdr["csrf-rnd"] = csrf.rnd; hdr["csrf-ts"] = String(csrf.ts); }
    hdr["x-amzn-trace-start"] = String(Date.now());
    const body = JSON.stringify({ operationName: QUEUE.operation,
      variables: { id: qid, currentEntityReferenceId: ref, isAuthenticated: true, limit: QUEUE.limit, direction: direction },
      extensions: { persistedQuery: { version: 1, sha256Hash: QUEUE.hash } } });
    const ac = safe(() => (typeof window.AbortController === "function" ? new window.AbortController() : null), null);
    const init = { method: "POST", credentials: "include", headers: hdr, body: body };
    if (ac) init.signal = ac.signal;
    let timer = null;
    const timeout = new Promise((_, rej) => { timer = setTimeout(() => { safe(() => ac && ac.abort()); rej(new Error("timeout")); }, QUEUE.timeoutMs); });
    try {
      return await Promise.race([timeout, (async () => {
        const r = await origFetch.call(window, gqlURL, init);
        if (!r || !r.ok) throw new Error("http"); // 429/5xx/...: transient
        return r.json();
      })()]);
    } finally { if (timer) clearTimeout(timer); }
  }
  // Merge extra edges around the cache instead of replacing it (anchor = a ref both lists share). Returns whether it merged.
  function mergeEdges(j, anchorRef, where, gen) {
    const edges = parseQueueEdges(j);
    const st = readQueueStore();
    if (!edges || !edges.length || !queueAll || gen < appliedGen || !st || queueId !== st.queueId) return false;
    const i = queueAll.findIndex((x) => x.ref === anchorRef);
    if (i < 0) return false;
    if (where === "before") {
      if (edges[edges.length - 1].ref !== anchorRef) return false;
      queueAll = edges.slice(0, -1).concat(queueAll.slice(i));
    } else {
      if (edges[0].ref !== anchorRef) return false;
      queueAll = queueAll.slice(0, i).concat(edges);
      queueHasNext = !!safe(() => j.data.queue.view.pageInfo.hasNextPage, false);
    }
    if (queueAll.length > 80) queueAll = queueAll.slice(queueAll.length - 80);
    lastIdx = 0;
    return true;
  }
  // kind: "full" = new snapshot via the store's queue id/active ref; "extend" = grow the cached list around the playing track
  // (Previous past the cached start -> BACKWARD from the first cached entry; Next/low water -> FORWARD from the last one).
  async function fetchQueue(st, kind) {
    if (qInFlight || !origFetch || !gqlURL || !gqlHeaders) return;
    qInFlight = true; lastQFetch = Date.now();
    const prevKey = lastFetchKey;
    if (kind === "full") lastFetchKey = st.queueId + "|" + st.ref;
    const gen = ++qGen;
    try {
      if (kind === "full") {
        applyQueueResponse(await queueRequest(st.queueId, st.ref, "FORWARD"), gen, true); // unparseable (schema change) -> cleared -> hidden
      } else {
        const cur = currentNames();
        if (matchIndex(cur) < 0) { // went back past the cached start?
          const first = queueAll[0].ref;
          mergeEdges(await queueRequest(st.queueId, first, "BACKWARD"), first, "before", gen);
        }
        if (matchIndex(cur) < 0 || (queueHasNext && queueAll.length - matchIndex(cur) - 1 < QUEUE.lowWater)) {
          const last = queueAll[queueAll.length - 1].ref;
          mergeEdges(await queueRequest(st.queueId, last, "FORWARD"), last, "after", gen);
        }
      }
    } catch (e) {
      // Transient failure (network/timeout/non-ok): keep a snapshot that still matches the store, and allow a later retry.
      if (kind === "full") lastFetchKey = prevKey;
    } finally {
      qInFlight = false;
    }
    scheduleCheck();
    if (qDirty) { qDirty = false; setTimeout(() => safe(() => maybeRefreshQueue(false, true)), QUEUE.kickGapMs); }
  }
  // Fetch only when needed. `requested` = popover opened; `urgent` = the playing track changed / next / previous (bypasses the
  // routine 4 s throttle but still at most one request per kickGapMs, rapid clicks coalesce into the in-flight/next one).
  function maybeRefreshQueue(requested, urgent) {
    const st = readQueueStore();
    if (!st || !origFetch || !gqlURL || !gqlHeaders) return;
    const cur = currentNames();
    const replaced = !!queueAll && queueId !== st.queueId; // a different queue: don't make the user wait out the throttle
    const idx = queueAll && !replaced ? matchIndex(cur) : -1;
    const miss = !!cur.title && idx < 0; // the playing track isn't in the cache (Previous, beyond the window, new queue)
    const low = idx >= 0 && queueHasNext && queueAll.length - idx - 1 < QUEUE.lowWater;
    if (!requested && !miss && !replaced && !low) return;
    const gap = Date.now() - lastQFetch;
    const limit = requested || (low && !urgent) ? QUEUE.minGapMs : QUEUE.kickGapMs;
    if (!replaced && gap < limit) {
      if (urgent || miss) { if (!kickTimer) kickTimer = setTimeout(() => { kickTimer = null; safe(() => maybeRefreshQueue(false, true)); }, limit - gap + 30); }
      return;
    }
    if (qInFlight) { qDirty = true; return; }
    if (miss && !replaced && missTries >= QUEUE.maxMissTries) return;
    if (low && !miss && !requested && lastFetchKey === st.queueId + "|" + st.ref && !urgent) return;
    if (miss) missTries++;
    if (requested || replaced || !queueAll || (miss && missTries > 1)) fetchQueue(st, "full"); // first miss: extend; later: new snapshot (store may have caught up)
    else fetchQueue(st, "extend");
  }
  // --- jump to a queue entry (Up Next row click) ---
  let pcCache = null, pcAttempts = 0, pcNextAt = 0, pcScanning = false, pcLastEnd = 0, lastJumpAt = 0;
  const PC_BACKOFF = [5000, 20000, 60000];
  // Non-executing lookup only (capture, then Metro's registry if the runtime exposes one: already-initialised modules only).
  function findPlaybackController() {
    if (pcCache) return pcCache;
    if (isController(capturedPC)) return (pcCache = capturedPC);
    const reg = safe(() => (typeof window.__r === "function" && typeof window.__r.getModules === "function" ? window.__r.getModules() : null), null);
    if (reg && typeof reg.forEach === "function") {
      safe(() => reg.forEach((m) => {
        if (pcCache || !m || !m.isInitialized) return;
        const ex = m.publicModule && m.publicModule.exports;
        if (ex && isController(ex.playbackController)) pcCache = ex.playbackController;
      }));
      if (pcCache) return pcCache;
    }
    return null;
  }
  // Last resort when neither the capture hook nor a registry is available: scan +-radius ids around the hint in small time-budgeted
  // chunks (never one long task), at most 3 attempts with backoff.
  function schedulePlaybackScan() {
    if (pcCache || pcScanning || defineHookActive || pcAttempts >= PC_BACKOFF.length || Date.now() < pcNextAt) return;
    const req = safe(() => (typeof window.__r === "function" ? window.__r : null), null);
    if (!req) return;
    pcScanning = true; pcAttempts++;
    const hint = QUEUE.controllerModuleHint, radius = QUEUE.controllerScanRadius;
    const ids = []; for (let d = 0; d <= radius; d++) { ids.push(hint + d); if (d && hint - d >= 0) ids.push(hint - d); }
    let i = 0;
    const probe = (id) => safe(() => { const m = req(id); return m && isController(m.playbackController) ? m.playbackController : null; }, null);
    const step = () => {
      const t0 = Date.now();
      while (i < ids.length && Date.now() - t0 < QUEUE.scanBudgetMs) { const c = probe(ids[i++]); if (c) { pcCache = c; break; } }
      if (pcCache || i >= ids.length) {
        pcScanning = false; pcLastEnd = Date.now(); pcNextAt = pcLastEnd + PC_BACKOFF[Math.min(pcAttempts - 1, PC_BACKOFF.length - 1)];
        scheduleCheck();
      } else setTimeout(step, 0);
    };
    setTimeout(step, 0);
  }
  // Reported to Swift so the rows only look clickable when jumping can work.
  function canJumpToQueue() {
    if (findPlaybackController()) return true;
    schedulePlaybackScan();
    return false;
  }
  async function playQueueItem(id) {
    if (typeof id !== "string" || !id || id.length > 200) return fail("invalid_argument");
    if (Date.now() - lastJumpAt < QUEUE.jumpGapMs) return fail("busy");
    const cur = currentNames();
    const idx = queueAll ? matchIndex(cur) : -1;
    const j = queueAll ? queueAll.findIndex((x) => x.ref === id) : -1;
    if (idx < 0 || j < 0) return fail("unknown_item"); // not in the cached queue (refresh runs on its own)
    if (j <= idx) return fail("stale_item"); // already played / current: the list has moved on
    const e = queueAll[j];
    if (!e.id || !e.uri) return fail("unsupported_item");
    const pc = findPlaybackController();
    if (!pc) { schedulePlaybackScan(); return fail("no_controller"); }
    lastJumpAt = Date.now();
    try {
      const r = pc.playQueueEntity({ entityPlaybackInstanceId: e.ref, uri: e.uri, duration: e.duration || 0, id: e.id }, Date.now());
      if (r && typeof r.then === "function") await Promise.race([r, new Promise((res) => setTimeout(res, 4000))]);
    } catch (err) { return fail("jump_failed"); }
    try { kickQueue(); } catch (err) {}
    return { ok: true, via: "controller" };
  }

  // After an explicit Next/Previous: re-derive soon and again as the page settles (state may update a moment after the click).
  function kickQueue() {
    [300, 1200, 3000].forEach((ms) => setTimeout(() => { missTries = 0; safe(() => maybeRefreshQueue(false, true)); scheduleCheck(); }, ms));
  }
  safe(() => {
    if (typeof window.fetch === "function" && !window.fetch.__amzHooked) {
      const orig = window.fetch;
      const hooked = function (input, init) {
        const p = orig.apply(this, arguments);
        try { observeFetch(input, init, p); } catch (e) {}
        return p;
      };
      hooked.__amzHooked = true;
      window.fetch = hooked;
    }
  });

  // --- source readers ---
  function queryFirst(list) {
    for (const sel of list) {
      const el = safe(() => document.querySelector(sel), null);
      if (el) return el;
    }
    return null;
  }
  function allMedia() {
    const set = new Set(detached);
    safe(() => document.querySelectorAll("audio,video").forEach((e) => set.add(e)));
    return Array.from(set);
  }
  function pickMedia() {
    const els = allMedia();
    let playing = null, best = null, bestDur = -1;
    for (const el of els) {
      const d = finite(safe(() => el.duration, null));
      if (d === null) continue;
      if (!playing && !safe(() => el.paused, true)) playing = el;
      if (d > bestDur) { best = el; bestDur = d; }
    }
    return playing || best;
  }
  function readMediaSession() {
    const md = safe(() => navigator.mediaSession && navigator.mediaSession.metadata, null);
    if (!md) return null;
    let art = null;
    const arr = safe(() => Array.from(md.artwork || []), []);
    let bestArea = -1;
    for (const a of arr) {
      const src = a && str(a.src);
      if (!src) continue;
      const m = /^(\d+)x(\d+)/.exec(String(a.sizes || "").trim());
      const area = m ? Number(m[1]) * Number(m[2]) : 0;
      if (area > bestArea) { bestArea = area; art = src; }
    }
    return { title: str(md.title), artist: str(md.artist), album: str(md.album), artworkURL: art };
  }
  function absURL(u) {
    const s = str(u);
    if (!s) return null;
    return safe(() => new URL(s, document.baseURI || window.location.href).href, s);
  }
  // Artist/album links live in the same block as the title: walk up from the title to the first ancestor containing one.
  function playerBarLink(title, selectors) {
    return safe(() => {
      for (let n = title, i = 0; n && i < 6; n = n.parentElement, i++) {
        for (const sel of selectors) { const el = n.querySelector && n.querySelector(sel); if (el) return el; }
      }
      return null;
    }, null);
  }
  const elText = (e) => (e ? str(e.getAttribute && e.getAttribute("aria-label")) || str(e.textContent) : null);
  // The player bar shows a 128px thumbnail; ask Amazon's image service for a larger rendition (same path, verified live).
  function upsizeArt(u) {
    return typeof u === "string" ? u.replace(/(\/images\/I\/[^/]*)\._[A-Z]{2}\d+,\d+_\./, "$1._UR512,512_.") : u;
  }
  function readDOM() {
    const t = queryFirst(SELECTORS.title), a = queryFirst(SELECTORS.artist), al = queryFirst(SELECTORS.album);
    const img = queryFirst(SELECTORS.artwork);
    return {
      title: t ? str(t.getAttribute && t.getAttribute("aria-label")) || str(t.textContent) : null,
      artist: a ? str(a.textContent) : elText(t ? playerBarLink(t, SELECTORS.barArtistLink) : null),
      album: al ? str(al.textContent) : elText(t ? playerBarLink(t, SELECTORS.barAlbumLink) : null),
      artworkURL: img ? upsizeArt(str(img.currentSrc || img.src)) : null,
    };
  }
  function readPlaybackStore() {
    return safe(() => {
      const k = Object.keys(window.localStorage).find((x) => SELECTORS.playbackStoreKey.test(x));
      const d = k ? JSON.parse(window.localStorage.getItem(k)).data : null;
      return d ? { position: finite(d.currentTimeInSeconds), duration: finite(d.duration),
        entityType: d.currentEntity && typeof d.currentEntity.__typename === "string" ? d.currentEntity.__typename : null,
        mediaType: d.currentEntity && typeof d.currentEntity.mediaType === "string" ? d.currentEntity.mediaType : null } : null;
    }, null);
  }
  // true = signed in; false = signed out (sign-in URL or expired auth only); null = not known (config missing/partial).
  function readSignedIn() {
    const path = safe(() => window.location.pathname + "", "");
    if (SELECTORS.signInPath.test(path)) return false;
    const cfg = safe(() => window.amznMusic.appConfig, null);
    if (!cfg || typeof cfg !== "object") return null;
    if (cfg.isCirrusAuthExpired === true) return false;
    return str(cfg.customerId) ? true : null; // a config without a customer is not proof of signed-out (could be loading/partial)
  }
  function sources() {
    return {
      mediaSession: !!safe(() => navigator.mediaSession && navigator.mediaSession.metadata, null),
      mediaElement: !!pickMedia(),
      dom: !!(queryFirst(SELECTORS.title) || queryFirst(SELECTORS.playButton) || queryFirst(SELECTORS.pauseButton)),
    };
  }

  // true = liked, false = not liked, null = unknown/no control (never guessed).
  function readLiked() {
    if (queryFirst(SELECTORS.unlikeButton)) return true;
    if (queryFirst(SELECTORS.likeButton)) return false;
    const el = queryFirst(SELECTORS.likeToggleAria);
    if (el) {
      const v = safe(() => el.getAttribute("aria-pressed"), null);
      if (v === "true") return true;
      if (v === "false") return false;
    }
    return null;
  }

  // Fill colour of a toggle's icon -> true (coloured/accent = on), false (white/grey = off), null (unreadable). Never guessed.
  function iconActive(el) {
    const p = safe(() => { for (const sel of SELECTORS.toggleIconPath) { const x = el.querySelector(sel); if (x) return x; } return null; }, null);
    const fill = p ? safe(() => window.getComputedStyle(p).fill, null) : null;
    const m = typeof fill === "string" ? /rgba?\(\s*(\d+)[ ,]+(\d+)[ ,]+(\d+)/.exec(fill) : null;
    if (!m) return null;
    const rgb = [Number(m[1]), Number(m[2]), Number(m[3])];
    return Math.max.apply(null, rgb) - Math.min.apply(null, rgb) > 40; // saturated => accent; white/grey => off
  }
  function ariaOn(el) {
    for (const a of ["aria-pressed", "aria-checked"]) {
      const v = safe(() => el.getAttribute(a), null);
      if (v === "true") return true;
      if (v === "false") return false;
    }
    return null;
  }
  // true / false / null (no control or unreadable).
  function readShuffle() {
    const el = queryFirst(SELECTORS.shuffleButton);
    if (!el) return null;
    const a = ariaOn(el);
    return a !== null ? a : iconActive(el);
  }
  // 'off' | 'all' | 'one' | null. One = active with the different (multi-path) icon, or the page's "Repeat Off" next-action label.
  function readRepeat() {
    const el = queryFirst(SELECTORS.repeatButton);
    if (!el) return null;
    const on = iconActive(el);
    if (on === null) { const a = ariaOn(el); return a === null ? null : a ? "all" : "off"; }
    if (!on) return "off";
    const paths = safe(() => el.querySelectorAll("path").length, 0);
    const label = safe(() => el.getAttribute("aria-label"), "") || "";
    return paths > 1 || /\boff\b/i.test(label) ? "one" : "all";
  }

  // "Play Similar Music" is offered for music tracks only (not podcasts/audiobooks/ads) when the player bar has its "..." button, and not
  // for a track where the menu turned out not to have the item.
  const noSimilar = new Set(), noSimilarCount = new Map(); // a track is only blacklisted after 2 consecutive 'menu has no such item' results
  let similarBusy = false;
  function readCanPlaySimilar(trackId) {
    if (similarBusy || !queryFirst(SELECTORS.moreButton)) return false;
    if (trackId && noSimilar.has(trackId)) return false;
    const ps = readPlaybackStore();
    return !!ps && ps.entityType === "Track" && (ps.mediaType === null || ps.mediaType === "AUDIO");
  }

  function readState() {
    const ms = safe(readMediaSession, null);
    const dom = ms && ms.title ? null : safe(readDOM, null);
    const el = safe(pickMedia, null);
    const pick = (k) => (ms && ms[k]) || (dom && dom[k]) || null;
    const title = pick("title"), artist = pick("artist"), album = pick("album");
    const artworkURL = absURL(pick("artworkURL"));
    let duration = el ? finite(safe(() => el.duration, null)) : null;
    let position = el ? finite(safe(() => el.currentTime, null)) : null;
    if (duration === null && title) { // loaded-but-paused: the media element has no duration yet; use the page's persisted values
      const ps = safe(readPlaybackStore, null);
      if (ps && ps.duration !== null && ps.duration > 0) { duration = ps.duration; position = ps.position !== null ? Math.min(ps.position, ps.duration) : null; }
    }
    let isPlaying = false;
    if (el) isPlaying = !safe(() => el.paused, true) && !safe(() => el.ended, false);
    else {
      const ps = safe(() => navigator.mediaSession && navigator.mediaSession.playbackState, null);
      // No media element yet: the player bar shows Pause while playing and Play while paused.
      isPlaying = ps === "playing" || (!!queryFirst(SELECTORS.pauseButton) && !queryFirst(SELECTORS.playButton));
    }
    const trackId = title || artist || album ? [title, artist, album].map((x) => x || "").join("|") : null;
    const liked = safe(readLiked, null);
    const shuffle = safe(readShuffle, null);
    const repeat = safe(readRepeat, null);
    const queue = title ? safe(upcomingQueue, null) : null;
    return { title, artist, album, artworkURL, duration, position, isPlaying, trackId, liked, shuffle, repeat, queue, signedIn: safe(readSignedIn, null), canPlaySimilar: !!title && safe(() => readCanPlaySimilar(trackId), false),
      canJumpToQueueItem: !!queue && safe(canJumpToQueue, false) };
  }

  // --- change detection ---
  function check(force) {
    try {
      const s = readState();
      if (s.trackId !== lastTrackSeen) { // any track change (page buttons, media keys, natural end, our commands)
        lastTrackSeen = s.trackId; missTries = 0;
        safe(() => { if (!pcCache && pcAttempts >= PC_BACKOFF.length && Date.now() - pcLastEnd > 60000) { pcAttempts = PC_BACKOFF.length - 1; pcNextAt = 0; } });
        if (s.trackId) setTimeout(() => safe(() => maybeRefreshQueue(false, true)), 0);
      }
      const { position, ...rest } = s; // position excluded from change comparison
      const json = JSON.stringify(rest);
      if (force || json !== lastStateJSON) {
        lastStateJSON = json;
        post("state", s);
      }
      if (s.isPlaying) {
        const now = Date.now();
        if (now - lastPositionAt >= 1000) {
          lastPositionAt = now;
          post("position", { position: s.position, duration: s.duration });
        }
      }
    } catch (e) { err("check_failed", e && e.message); }
  }
  function scheduleCheck() {
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => { debounceTimer = null; check(false); }, 250);
  }
  const EVENTS = ["play", "pause", "ended", "durationchange", "loadedmetadata", "seeked", "timeupdate"];
  const attached = new WeakSet();
  function attach(el) {
    try {
      if (attached.has(el)) return;
      attached.add(el);
      EVENTS.forEach((ev) => el.addEventListener(ev, () => {
        check(ev === "seeked"); // seek changes position only; force a state message
      }));
    } catch (e) {}
  }
  function attachAll() { safe(() => allMedia().forEach(attach)); }

  // --- commands ---
  function fail(reason) { return { ok: false, reason: reason }; }
  function clickFirst(list) {
    const el = queryFirst(list);
    if (!el) return false;
    return safe(() => { el.click(); return true; }, false);
  }
  function mediaCmd(fn, name) {
    const el = pickMedia();
    if (!el) return null;
    return safe(() => { fn(el); return { ok: true, via: "mediaElement" }; }, fail(name + "_failed"));
  }
  const sleepMs = (ms) => new Promise((r) => setTimeout(r, ms));
  // A skip "took effect" if the track identity changed, or the position jumped back (restart / previous track).
  function skipChanged(s0) {
    const s = safe(readState, null);
    if (!s || !s0) return false;
    if (s.trackId !== s0.trackId) return true;
    return s0.position !== null && s.position !== null && s.position < s0.position - 1.5;
  }
  async function waitChanged(s0, ms) {
    const end = Date.now() + ms;
    while (Date.now() < end) {
      await sleepMs(100);
      if (skipChanged(s0)) return true;
    }
    return skipChanged(s0);
  }
  // Skip commands (async; resolve to {ok, via, changed?} | {ok:false, reason}).
  // 1) call the page's captured mediaSession handler and verify the effect within VERIFY_MS;
  // 2) if nothing changed (or no handler), click the real player-bar button from SELECTORS.
  // `previous`: the page's own handler/button restarts the track when position is past ~3s and goes back otherwise
  // (standard behaviour); we do exactly what the page does and do not emulate it.
  const VERIFY_MS = 1500;
  async function action(name, buttons) {
    const s0 = safe(readState, null);
    const h = handlers[name];
    if (typeof h === "function") {
      let threw = false;
      try { h({ action: name }); } catch (e) { threw = true; }
      if (!threw && (await waitChanged(s0, VERIFY_MS))) return { ok: true, via: "mediaSession", changed: true };
    }
    if (clickFirst(buttons)) {
      const changed = await waitChanged(s0, VERIFY_MS);
      return { ok: true, via: "dom", changed: changed };
    }
    return fail("no_" + name + "_control");
  }
  function play() {
    const r = mediaCmd((el) => { const p = el.play(); if (p && p.catch) p.catch(() => {}); }, "play");
    if (r) return r;
    if (typeof handlers.play === "function") return safe(() => { handlers.play({ action: "play" }); return { ok: true, via: "mediaSession" }; }, fail("play_failed"));
    return clickFirst(SELECTORS.playButton) ? { ok: true, via: "dom" } : fail("no_player");
  }
  function pause() {
    const r = mediaCmd((el) => el.pause(), "pause");
    if (r) return r;
    if (typeof handlers.pause === "function") return safe(() => { handlers.pause({ action: "pause" }); return { ok: true, via: "mediaSession" }; }, fail("pause_failed"));
    return clickFirst(SELECTORS.pauseButton) ? { ok: true, via: "dom" } : fail("no_player");
  }
  function toggle() {
    const el = pickMedia();
    if (el) return safe(() => (el.paused ? play() : pause()), fail("toggle_failed"));
    if (clickFirst(SELECTORS.pauseButton) || clickFirst(SELECTORS.playButton)) return { ok: true, via: "dom" };
    return fail("no_player");
  }
  function seek(seconds) {
    const t = Number(seconds);
    if (!isFinite(t)) return fail("invalid_argument");
    const el = pickMedia();
    if (el) {
      return safe(() => {
        const d = finite(el.duration);
        el.currentTime = Math.max(0, d !== null ? Math.min(t, d) : t);
        return { ok: true, via: "mediaElement" };
      }, fail("seek_failed"));
    }
    if (typeof handlers.seekto === "function") {
      return safe(() => { handlers.seekto({ action: "seekto", seekTime: t }); return { ok: true, via: "mediaSession" }; }, fail("seek_failed"));
    }
    return fail("no_player");
  }
  // desired: true = like, false = unlike, undefined = toggle. Idempotent for like()/unlike().
  function setLike(desired) {
    const liked = safe(readLiked, null);
    if (liked === null) {
      const el = queryFirst(SELECTORS.likeToggleAria);
      if (!el) return fail("no_like_control");
      if (desired !== undefined) return fail("unknown_like_state");
    }
    if (desired !== undefined && liked === desired) return { ok: true, via: "dom" };
    const list = liked === true ? SELECTORS.unlikeButton : liked === false ? SELECTORS.likeButton : [];
    if (!clickFirst(list) && !clickFirst(SELECTORS.likeToggleAria)) return fail("no_like_control");
    setTimeout(scheduleCheck, 600); setTimeout(scheduleCheck, 1500);
    return { ok: true, via: "dom" };
  }
  // Click the real player-bar toggle; state is pushed once the page re-renders (~0.5 s; extra checks cover slow ones).
  function clickToggle(list, name) {
    if (!queryFirst(list)) return fail("no_" + name + "_control");
    if (!clickFirst(list)) return fail(name + "_failed");
    setTimeout(scheduleCheck, 600); setTimeout(scheduleCheck, 1500);
    return { ok: true, via: "dom" };
  }
  // Opens the player bar's "..." menu, clicks "Play Similar Music" and lets the page do the rest. The portal menu is made invisible the
  // moment it is inserted (MutationObserver runs before paint) and restored afterwards, so nothing flashes in the main window.
  async function playSimilar() {
    if (similarBusy) return fail("busy");
    const btn = queryFirst(SELECTORS.moreButton);
    if (!btn) return fail("no_more_menu");
    const st0 = safe(readState, null);
    if (!st0 || !st0.trackId) return fail("no_track");
    const ps = safe(readPlaybackStore, null);
    if (!ps || ps.entityType !== "Track") return fail("unsupported_item");
    const menus = () => safe(() => Array.from(document.querySelectorAll(SELECTORS.menuRoot[0])), []);
    if (menus().length) return fail("menu_open"); // the user has a menu open: don't touch it
    const trackId = st0.trackId;
    const before = new Set(menus()); // empty here; kept so only menus inserted AFTER our click are ever hidden or clicked
    similarBusy = true;
    const hidden = []; // [node, prevVisibility, prevPointerEvents]
    let mo = null, menuSeen = false;
    const fresh = () => menus().filter((m) => !before.has(m));
    // The element to hide for a menu: its nearest fixed/absolute ancestor (the portal wrapper, at any depth), else the menu itself.
    const hideTarget = (m) => safe(() => {
      for (let n = m.parentElement; n && n !== document.body && n !== document.documentElement; n = n.parentElement) {
        const pos = window.getComputedStyle(n).position;
        if (pos === "fixed" || pos === "absolute") return n;
      }
      return m;
    }, m);
    const hideMenus = () => safe(() => fresh().forEach((m) => {
      menuSeen = true;
      const n = hideTarget(m);
      if (!hidden.some((h) => h[0] === n)) { hidden.push([n, n.style.visibility, n.style.pointerEvents]); n.style.visibility = "hidden"; n.style.pointerEvents = "none"; }
    }));
    const findItem = () => safe(() => {
      for (const m of fresh()) {
        const root = hideTarget(m);
        const byId = root.querySelector && root.querySelector(SELECTORS.similarItemTestId + " " + SELECTORS.menuItem[0]) || (root.querySelector && root.querySelector(SELECTORS.similarItemTestId));
        if (byId) return byId;
        const byLabel = Array.from(m.querySelectorAll(SELECTORS.menuItem[0])).find((e) => SELECTORS.similarLabel.test(e.textContent || ""));
        if (byLabel) return byLabel;
      }
      return null;
    }, null);
    const restore = () => hidden.forEach((h) => safe(() => { h[0].style.visibility = h[1]; h[0].style.pointerEvents = h[2]; }));
    try {
      const clicked = await new Promise((resolve) => {
        let done = false;
        const finish = (v) => { if (!done) { done = true; resolve(v); } };
        const attempt = () => { hideMenus(); const it = findItem(); if (it) { safe(() => it.click()); finish(true); } };
        mo = typeof MutationObserver === "function" ? new MutationObserver(attempt) : null;
        if (mo && document.body) mo.observe(document.body, { childList: true, subtree: true, characterData: true });
        setTimeout(() => finish(false), 1500);
        safe(() => btn.click());
        if (!mo) { const iv = setInterval(() => { attempt(); if (done) clearInterval(iv); }, 30); setTimeout(() => clearInterval(iv), 1600); }
        attempt();
      });
      if (!clicked) {
        if (fresh().length) safe(() => btn.click()); // close the menu we opened (toggle)
        if (!menuSeen) return fail("menu_timeout"); // the menu never appeared: a timeout says nothing about this track
        const n = (noSimilarCount.get(trackId) || 0) + 1;
        noSimilarCount.set(trackId, n);
        if (n >= 2) noSimilar.add(trackId); // two consecutive "menu has no such item": hide the button for this track
        return fail("no_similar_item");
      }
      noSimilarCount.delete(trackId);
      return { ok: true, via: "dom" };
    } finally {
      if (mo) mo.disconnect();
      // Un-hide once our menu is gone (the page reuses the wrapper for its own menu); hard stop after 2 s.
      let n = 0;
      const iv = setInterval(() => { n++; if (!fresh().length || n > 20) { clearInterval(iv); restore(); } }, 100);
      similarBusy = false;
      try { kickQueue(); } catch (e) {}
    }
  }
  const wrap = (fn) => function () { try { const r = fn.apply(null, arguments); setTimeout(scheduleCheck, 0); return r; } catch (e) { return fail("exception"); } };

  const wrapAsync = (fn) => function () {
    return Promise.resolve().then(() => fn.apply(null, arguments)).catch(() => fail("exception")).then((r) => { setTimeout(scheduleCheck, 0); return r; });
  };

  try {
    Object.defineProperty(window, "__amzBridge", {
      value: {
        version: BRIDGE_VERSION,
        play: wrap(play), pause: wrap(pause), toggle: wrap(toggle),
        next: wrapAsync(() => action("nexttrack", SELECTORS.nextButton).then((r) => { kickQueue(); return r; })),
        previous: wrapAsync(() => action("previoustrack", SELECTORS.previousButton).then((r) => { kickQueue(); return r; })),
        seek: wrap(seek),
        toggleLike: wrap(() => setLike(undefined)),
        playSimilar: wrapAsync(() => playSimilar()),
        playQueueItem: wrapAsync((id) => playQueueItem(id)),
        toggleShuffle: wrap(() => clickToggle(SELECTORS.shuffleButton, "shuffle")),
        cycleRepeat: wrap(() => clickToggle(SELECTORS.repeatButton, "repeat")),
        like: wrap(() => setLike(true)),
        unlike: wrap(() => setLike(false)),
        refreshQueue: () => { safe(() => maybeRefreshQueue(true)); return { ok: true }; },
        getState: () => safe(readState, null),
      },
      configurable: true,
    });
  } catch (e) { return; }

  // --- startup ---
  function start() {
    try {
      attachAll();
      const src = sources();
      post("ready", { bridgeVersion: BRIDGE_VERSION, sources: src });
      if (!src.mediaSession && !src.mediaElement && !src.dom) {
        err("no_sources", "No player sources found yet (mediaSession, media element, DOM)");
      }
      check(true);
      if (typeof MutationObserver === "function" && document.documentElement) {
        new MutationObserver(() => { attachAll(); scheduleCheck(); })
          .observe(document.documentElement, { childList: true, subtree: true });
      }
      setInterval(() => { attachAll(); check(false); safe(() => maybeRefreshQueue(false)); }, 2000);
    } catch (e) { err("start_failed", e && e.message); }
  }
  if (document.readyState === "loading" && !document.documentElement) {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
})();
