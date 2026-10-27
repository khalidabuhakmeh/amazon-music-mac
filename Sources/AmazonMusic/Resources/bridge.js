// Amazon Music bridge: observes player state, executes commands.
// Injected at document start, main frame only. Never throws.
(function () {
  "use strict";
  const BRIDGE_VERSION = "1.3.0";

  // The ONLY place DOM selectors live. Last-resort fallbacks; adjust here if the site changes.
  const SELECTORS = {
    title: ['[data-testid="player-title"]', "music-horizontal-item.queue-now-playing [slot=primary-text]"],
    artist: ['[data-testid="player-artist"]'],
    album: ['[data-testid="player-album"]'],
    artwork: ['[data-testid="player-artwork"] img'],
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
    toggleIconPath: ["svg path", "path"],
    previousButton: ['button[data-testid="IconButton,MiniPlayer_PreviousButton"]', '[data-testid*="MiniPlayer"][aria-label="Previous" i]'],
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
  function readDOM() {
    const t = queryFirst(SELECTORS.title), a = queryFirst(SELECTORS.artist), al = queryFirst(SELECTORS.album);
    const img = queryFirst(SELECTORS.artwork);
    return {
      title: t ? str(t.textContent) : null,
      artist: a ? str(a.textContent) : null,
      album: al ? str(al.textContent) : null,
      artworkURL: img ? str(img.currentSrc || img.src) : null,
    };
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

  function readState() {
    const ms = safe(readMediaSession, null);
    const dom = ms && ms.title ? null : safe(readDOM, null);
    const el = safe(pickMedia, null);
    const pick = (k) => (ms && ms[k]) || (dom && dom[k]) || null;
    const title = pick("title"), artist = pick("artist"), album = pick("album");
    const artworkURL = absURL(pick("artworkURL"));
    const duration = el ? finite(safe(() => el.duration, null)) : null;
    const position = el ? finite(safe(() => el.currentTime, null)) : null;
    let isPlaying = false;
    if (el) isPlaying = !safe(() => el.paused, true) && !safe(() => el.ended, false);
    else {
      const ps = safe(() => navigator.mediaSession && navigator.mediaSession.playbackState, null);
      isPlaying = ps === "playing";
    }
    const trackId = title || artist || album ? [title, artist, album].map((x) => x || "").join("|") : null;
    const liked = safe(readLiked, null);
    const shuffle = safe(readShuffle, null);
    const repeat = safe(readRepeat, null);
    return { title, artist, album, artworkURL, duration, position, isPlaying, trackId, liked, shuffle, repeat };
  }

  // --- change detection ---
  function check(force) {
    try {
      const s = readState();
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
  const wrap = (fn) => function () { try { const r = fn.apply(null, arguments); setTimeout(scheduleCheck, 0); return r; } catch (e) { return fail("exception"); } };

  const wrapAsync = (fn) => function () {
    return Promise.resolve().then(() => fn.apply(null, arguments)).catch(() => fail("exception")).then((r) => { setTimeout(scheduleCheck, 0); return r; });
  };

  try {
    Object.defineProperty(window, "__amzBridge", {
      value: {
        version: BRIDGE_VERSION,
        play: wrap(play), pause: wrap(pause), toggle: wrap(toggle),
        next: wrapAsync(() => action("nexttrack", SELECTORS.nextButton)),
        previous: wrapAsync(() => action("previoustrack", SELECTORS.previousButton)),
        seek: wrap(seek),
        toggleLike: wrap(() => setLike(undefined)),
        toggleShuffle: wrap(() => clickToggle(SELECTORS.shuffleButton, "shuffle")),
        cycleRepeat: wrap(() => clickToggle(SELECTORS.repeatButton, "repeat")),
        like: wrap(() => setLike(true)),
        unlike: wrap(() => setLike(false)),
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
      setInterval(() => { attachAll(); check(false); }, 2000);
    } catch (e) { err("start_failed", e && e.message); }
  }
  if (document.readyState === "loading" && !document.documentElement) {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
})();
