// Run: node tools/bridge-test/bridge.test.mjs  (no deps)
import vm from "node:vm";
import fs from "node:fs";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import path from "node:path";

const src = fs.readFileSync(path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../Sources/AmazonMusic/Resources/bridge.js"), "utf8");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

class Media {
  constructor(tag, o = {}) {
    this.tagName = tag; this.duration = o.duration ?? NaN; this.currentTime = o.currentTime ?? 0;
    this.paused = o.paused ?? true; this.ended = false; this.listeners = {};
  }
  addEventListener(e, f) { (this.listeners[e] ||= []).push(f); }
  emit(e) { (this.listeners[e] || []).forEach((f) => f()); }
  play() { this.paused = false; this.emit("play"); return Promise.resolve(); }
  pause() { this.paused = true; this.emit("pause"); }
}

function makePage({ mediaSession = true, media = [], selectors = {} } = {}) {
  const messages = [];
  const w = { messages };
  w.window = w; w.top = w;
  w.webkit = { messageHandlers: { amazonMusic: { postMessage: (m) => messages.push(JSON.parse(JSON.stringify(m))) } } };
  w.HTMLMediaElement = Media;
  w.URL = URL; w.setTimeout = setTimeout; w.clearTimeout = clearTimeout; w.clearInterval = clearInterval; w.setInterval = (f, ms) => setInterval(f, ms).unref(); w.Date = Date;
  w.getComputedStyle = (p) => ({ fill: p.fill, position: p.position });
  w.location = { href: "https://music.amazon.com/" };
  const observers = [];
  w.MutationObserver = class { constructor(cb) { this.cb = cb; observers.push(this); } observe() {} disconnect() {} };
  w.fireMutation = () => observers.forEach((o) => o.cb([]));
  const origSet = function (a, h) { w.origCalls.push([a, h]); };
  w.origCalls = [];
  w.navigator = mediaSession
    ? { mediaSession: { metadata: { title: "Example Track", artist: "Example Artist", album: "Example Album",
          artwork: [{ src: "/small.jpg ", sizes: "100x100" }, { src: "/big.jpg ", sizes: "500x500" }] },
          playbackState: "none", setActionHandler: origSet } }
    : {};
  w.media = media;
  const clicked = [];
  w.clicked = clicked;
  w.document = {
    readyState: "complete", documentElement: {}, baseURI: "https://music.amazon.com/",
    addEventListener() {},
    querySelectorAll: (s) => (s === "audio,video" ? w.media.filter((m) => w.attachedToDom?.(m) ?? true) : []),
    querySelector: (s) => selectors[s] ? { textContent: selectors[s].text, click: () => { clicked.push(s); selectors[s].onClick?.(); },
      getAttribute: (n) => selectors[s].attrs?.[n] ?? null,
      // toggle icon: opts.fill = computed fill of each <path>, opts.paths = number of <path>s
      querySelectorAll: () => Array.from({ length: selectors[s].paths ?? (selectors[s].fill ? 1 : 0) }, () => ({ fill: selectors[s].fill })),
      querySelector: () => (selectors[s].fill ? { fill: selectors[s].fill } : null) } : null,
  };
  vm.createContext(w);
  w.load = () => vm.runInContext(src, w);
  return w;
}
const states = (w) => w.messages.filter((m) => m.type === "state").map((m) => m.payload);

let pass = 0, failN = 0;
async function t(name, fn) {
  try { await fn(); pass++; console.log("ok   -", name); }
  catch (e) { failN++; console.log("FAIL -", name, "\n", e.stack); }
}

await t("state from mediaSession + VIDEO (AUDIO unused ignored)", async () => {
  const audio = new Media("AUDIO"); const video = new Media("VIDEO", { duration: 136.8, currentTime: 41, paused: false });
  const w = makePage({ media: [audio, video] }); w.load();
  const ready = w.messages.find((m) => m.type === "ready");
  assert.equal(ready.payload.bridgeVersion, "1.7.1"); assert.equal(ready.v, 1);
  assert.equal(ready.payload.sources.mediaSession, true);
  const s = states(w)[0];
  assert.deepEqual(s, { title: "Example Track", artist: "Example Artist", album: "Example Album",
    artworkURL: "https://music.amazon.com/big.jpg", duration: 136.8, position: 41, isPlaying: true,
    trackId: "Example Track|Example Artist|Example Album", liked: null, shuffle: null, repeat: null, queue: null, signedIn: null, canPlaySimilar: false, canJumpToQueueItem: false });
  assert.ok(w.messages.some((m) => m.type === "position"));
  assert.equal(w.__amzBridge.version, "1.7.1");
});

await t("track change -> new state; no duplicate when unchanged", async () => {
  const video = new Media("VIDEO", { duration: 100, paused: false });
  const w = makePage({ media: [video] }); w.load();
  w.fireMutation(); await sleep(300);
  assert.equal(states(w).length, 1);
  w.navigator.mediaSession.metadata = { title: "Two", artist: "B", album: "C", artwork: [] };
  w.fireMutation(); await sleep(300);
  const all = states(w); assert.equal(all.length, 2);
  assert.equal(all[1].title, "Two"); assert.equal(all[1].artworkURL, null);
  assert.equal(all[1].trackId, "Two|B|C");
});

await t("pause -> isPlaying false", async () => {
  const video = new Media("VIDEO", { duration: 100, paused: false });
  const w = makePage({ media: [video] }); w.load();
  video.pause();
  const all = states(w); assert.equal(all.at(-1).isPlaying, false);
});

await t("toggle/seek/next results", async () => {
  const video = new Media("VIDEO", { duration: 100, paused: false });
  const w = makePage({ media: [video] }); w.load();
  assert.deepEqual({ ...w.__amzBridge.toggle() }, { ok: true, via: "mediaElement" });
  assert.equal(video.paused, true);
  w.__amzBridge.toggle(); assert.equal(video.paused, false);
  assert.deepEqual({ ...w.__amzBridge.seek(30) }, { ok: true, via: "mediaElement" });
  assert.equal(video.currentTime, 30);
  assert.equal(w.__amzBridge.seek("x").ok, false);
  assert.equal((await w.__amzBridge.previous()).ok, false); // no handler, no button
});

const NEXT = 'button[data-testid="IconButton,MiniPlayer_NextButton"]';
const PREV = 'button[data-testid="IconButton,MiniPlayer_PreviousButton"]';
function titled(video, title) { return (w) => { w.navigator.mediaSession.metadata.title = title; video.currentTime = 0; }; }

await t("next via captured handler (verified by track change)", async () => {
  const video = new Media("VIDEO", { duration: 100, currentTime: 40, paused: false });
  const w = makePage({ media: [video] }); w.load();
  let called = 0;
  w.navigator.mediaSession.setActionHandler("nexttrack", (d) => { called++; assert.equal(d.action, "nexttrack"); titled(video, "Next Song")(w); });
  const r = await w.__amzBridge.next();
  assert.deepEqual({ ...r }, { ok: true, via: "mediaSession", changed: true });
  assert.equal(called, 1); assert.equal(w.clicked.length, 0);
});

await t("previous via handler: position reset (restart) counts as change", async () => {
  const video = new Media("VIDEO", { duration: 100, currentTime: 40, paused: false });
  const w = makePage({ media: [video] }); w.load();
  w.navigator.mediaSession.setActionHandler("previoustrack", () => { video.currentTime = 0; });
  assert.deepEqual({ ...(await w.__amzBridge.previous()) }, { ok: true, via: "mediaSession", changed: true });
});

await t("handler captured via MediaSession.prototype (page-style access)", async () => {
  const w = makePage({});
  const orig = function (a, h) { w.origCalls.push([a, h]); };
  w.MediaSession = function () {}; w.MediaSession.prototype.setActionHandler = orig;
  const ms = Object.create(w.MediaSession.prototype); ms.metadata = w.navigator.mediaSession.metadata; w.navigator.mediaSession = ms;
  w.load();
  assert.equal(w.MediaSession.prototype.setActionHandler.__amzHooked, true);
  let called = 0;
  w.MediaSession.prototype.setActionHandler.call(w.navigator.mediaSession, "nexttrack", () => { called++; w.navigator.mediaSession.metadata.title = "X"; });
  assert.equal((await w.__amzBridge.next()).via, "mediaSession"); assert.equal(called, 1);
  assert.equal(w.origCalls.length, 1); // original still called
});

await t("handler does nothing -> falls through to real button click", async () => {
  const video = new Media("VIDEO", { duration: 100, currentTime: 40, paused: false });
  const w = makePage({ media: [video], selectors: { [NEXT]: { text: "", onClick: () => { w.navigator.mediaSession.metadata.title = "Next Song"; } } } }); w.load();
  let called = 0;
  w.navigator.mediaSession.setActionHandler("nexttrack", () => { called++; });
  const r = await w.__amzBridge.next();
  assert.deepEqual({ ...r }, { ok: true, via: "dom", changed: true });
  assert.equal(called, 1); assert.deepEqual(w.clicked, [NEXT]);
});

await t("handler throws -> falls through to button (previous)", async () => {
  const video = new Media("VIDEO", { duration: 100, currentTime: 40, paused: false });
  const w = makePage({ media: [video], selectors: { [PREV]: { text: "", onClick: () => { video.currentTime = 0; } } } }); w.load();
  w.navigator.mediaSession.setActionHandler("previoustrack", () => { throw new Error("boom"); });
  assert.deepEqual({ ...(await w.__amzBridge.previous()) }, { ok: true, via: "dom", changed: true });
});

await t("button click with no observable change still reports dispatch (changed:false)", async () => {
  const w = makePage({ media: [], selectors: { [NEXT]: { text: "" } } }); w.load();
  assert.deepEqual({ ...(await w.__amzBridge.next()) }, { ok: true, via: "dom", changed: false });
});

await t("no handler and no button -> failure result with reason", async () => {
  const w = makePage({ media: [] }); w.load();
  assert.deepEqual({ ...(await w.__amzBridge.next()) }, { ok: false, reason: "no_nexttrack_control" });
  assert.deepEqual({ ...(await w.__amzBridge.previous()) }, { ok: false, reason: "no_previoustrack_control" });
});

await t("SELECTORS use the real player-bar testids", async () => {
  assert.ok(src.includes("IconButton,MiniPlayer_NextButton") && src.includes("IconButton,MiniPlayer_PreviousButton"));
  assert.ok(!src.includes("transport-next") && !src.includes("transport-previous"));
});

await t("setActionHandler hook calls original", async () => {
  const w = makePage({}); w.load();
  const h = () => {};
  w.navigator.mediaSession.setActionHandler("play", h);
  assert.equal(w.origCalls.length, 1); assert.equal(w.origCalls[0][1], h);
});

await t("missing mediaSession / broken selectors -> nulls + error, no throw", async () => {
  const w = makePage({ mediaSession: false, media: [] });
  assert.doesNotThrow(() => w.load());
  const err = w.messages.find((m) => m.type === "error");
  assert.equal(err.payload.code, "no_sources");
  const s = states(w)[0];
  assert.equal(s.title, null); assert.equal(s.duration, null); assert.equal(s.trackId, null); assert.equal(s.isPlaying, false);
  assert.equal(w.__amzBridge.toggle().ok, false);
  // throwing document
  const w2 = makePage({}); w2.document.querySelector = () => { throw new Error("boom"); };
  w2.document.querySelectorAll = () => { throw new Error("boom"); };
  assert.doesNotThrow(() => w2.load());
  assert.equal(states(w2)[0].title, "Example Track");
  // no webkit handler
  const w3 = makePage({}); delete w3.webkit; assert.doesNotThrow(() => w3.load());
});

await t("idempotent injection", async () => {
  const w = makePage({ media: [new Media("VIDEO", { duration: 5 })] }); w.load();
  const n = w.messages.length, b = w.__amzBridge;
  assert.doesNotThrow(() => w.load());
  assert.equal(w.messages.length, n); assert.equal(w.__amzBridge, b);
});

await t("sub-frame bails out", async () => {
  const w = makePage({}); w.top = {}; w.load();
  assert.equal(w.__amzBridge, undefined); assert.equal(w.messages.length, 0);
});

await t("NaN/Infinity durations -> null", async () => {
  const w = makePage({ media: [new Media("VIDEO", { duration: Infinity, currentTime: NaN, paused: false })] }); w.load();
  const s = states(w)[0]; assert.equal(s.duration, null); assert.equal(s.position, null);
  const w2 = makePage({ media: [new Media("VIDEO", { duration: NaN })] }); w2.load();
  assert.equal(states(w2)[0].duration, null);
});

await t("debug log only when flag set", async () => {
  const w = makePage({}); w.load();
  assert.ok(!w.messages.some((m) => m.type === "log"));
});

const LIKE = 'button[data-testid="IconButton,MiniPlayer_Follow_Follow"]';
const UNLIKE = 'button[data-testid="IconButton,MiniPlayer_Follow_Unfollow"]';
const ARIA = '[data-testid*="MiniPlayer"][data-testid*="Like"][aria-pressed]';

await t("liked: null when no like control; like commands fail gracefully", async () => {
  const w = makePage({ media: [new Media("VIDEO", { duration: 10 })] }); w.load();
  assert.equal(states(w)[0].liked, null);
  for (const c of ["toggleLike", "like", "unlike"]) assert.deepEqual({ ...w.__amzBridge[c]() }, { ok: false, reason: "no_like_control" });
});

await t("liked from testid variants (Follow=false, Unfollow=true)", async () => {
  const w = makePage({ selectors: { [LIKE]: { text: "" } } }); w.load();
  assert.equal(states(w)[0].liked, false);
  const w2 = makePage({ selectors: { [UNLIKE]: { text: "" } } }); w2.load();
  assert.equal(states(w2)[0].liked, true);
  assert.equal(w2.__amzBridge.getState().liked, true);
});

await t("liked from aria-pressed fallback", async () => {
  const w = makePage({ selectors: { [ARIA]: { text: "", attrs: { "aria-pressed": "true" } } } }); w.load();
  assert.equal(states(w)[0].liked, true);
  const w2 = makePage({ selectors: { [ARIA]: { text: "", attrs: { "aria-pressed": "false" } } } }); w2.load();
  assert.equal(states(w2)[0].liked, false);
  const w3 = makePage({ selectors: { [ARIA]: { text: "", attrs: { "aria-pressed": "mixed" } } } }); w3.load();
  assert.equal(states(w3)[0].liked, null);
});

await t("toggleLike/like/unlike click the right button; idempotent; state reconciles", async () => {
  const sel = {};
  let liked = false;
  const sync = () => { delete sel[LIKE]; delete sel[UNLIKE]; sel[liked ? UNLIKE : LIKE] = { text: "", onClick: () => { liked = !liked; sync(); } }; };
  sync();
  const w = makePage({ selectors: sel }); w.load();
  assert.equal(states(w)[0].liked, false);
  assert.deepEqual({ ...w.__amzBridge.unlike() }, { ok: true, via: "dom" }); assert.equal(w.clicked.length, 0); // already unliked
  assert.deepEqual({ ...w.__amzBridge.like() }, { ok: true, via: "dom" }); assert.equal(liked, true);
  assert.deepEqual({ ...w.__amzBridge.like() }, { ok: true, via: "dom" }); assert.equal(w.clicked.length, 1); // idempotent
  await sleep(900);
  assert.equal(states(w).at(-1).liked, true);
  assert.deepEqual({ ...w.__amzBridge.toggleLike() }, { ok: true, via: "dom" }); assert.equal(liked, false);
  await sleep(900);
  assert.equal(states(w).at(-1).liked, false);
  assert.deepEqual(w.clicked, [LIKE, UNLIKE]);
});

await t("toggleLike via aria-pressed fallback clicks it", async () => {
  const w = makePage({ selectors: { [ARIA]: { text: "", attrs: { "aria-pressed": "false" } } } }); w.load();
  assert.deepEqual({ ...w.__amzBridge.toggleLike() }, { ok: true, via: "dom" }); assert.deepEqual(w.clicked, [ARIA]);
});

await t("liked change alone emits a new state message; trackId unaffected", async () => {
  const sel = { [LIKE]: { text: "" } };
  const w = makePage({ selectors: sel }); w.load();
  const n = states(w).length;
  delete sel[LIKE]; sel[UNLIKE] = { text: "" };
  w.fireMutation(); await sleep(300);
  const all = states(w); assert.equal(all.length, n + 1);
  assert.equal(all.at(-1).liked, true); assert.equal(all.at(-1).trackId, all[0].trackId);
});


const SHUF = '[data-testid="IconButton,MiniPlayer_ShuffleButton"]';
const LOOP = '[data-testid="IconButton,MiniPlayer_LoopButton"]';
const WHITE = "rgb(255, 255, 255)", ACCENT = "rgb(37, 209, 218)";

await t("shuffle/repeat null when controls absent; commands fail gracefully", async () => {
  const w = makePage({}); w.load();
  assert.equal(states(w)[0].shuffle, null); assert.equal(states(w)[0].repeat, null);
  assert.deepEqual({ ...w.__amzBridge.toggleShuffle() }, { ok: false, reason: "no_shuffle_control" });
  assert.deepEqual({ ...w.__amzBridge.cycleRepeat() }, { ok: false, reason: "no_repeat_control" });
});

await t("shuffle from icon fill colour (white=false, accent=true); unreadable=null", async () => {
  const off = makePage({ selectors: { [SHUF]: { text: "", fill: WHITE, attrs: { "aria-label": "Shuffle" } } } }); off.load();
  assert.equal(states(off)[0].shuffle, false);
  const on = makePage({ selectors: { [SHUF]: { text: "", fill: ACCENT, attrs: { "aria-label": "Shuffle" } } } }); on.load();
  assert.equal(states(on)[0].shuffle, true);
  const unk = makePage({ selectors: { [SHUF]: { text: "", fill: "none" } } }); unk.load();
  assert.equal(states(unk)[0].shuffle, null);
  const aria = makePage({ selectors: { [SHUF]: { text: "", attrs: { "aria-pressed": "true" } } } }); aria.load();
  assert.equal(states(aria)[0].shuffle, true); // aria fallback if Amazon adds it
});

await t("repeat off/all/one (real page: white / accent+1 path / accent+multi-path, labels name the next action)", async () => {
  const mk = (o) => { const w = makePage({ selectors: { [LOOP]: { text: "", ...o } } }); w.load(); return states(w)[0].repeat; };
  assert.equal(mk({ fill: WHITE, paths: 1, attrs: { "aria-label": "Repeat" } }), "off");
  assert.equal(mk({ fill: ACCENT, paths: 1, attrs: { "aria-label": "Repeat Once" } }), "all");
  assert.equal(mk({ fill: ACCENT, paths: 3, attrs: { "aria-label": "Repeat Off" } }), "one");
  assert.equal(mk({ fill: ACCENT, paths: 1, attrs: { "aria-label": "Repeat Off" } }), "one"); // label fallback
  assert.equal(mk({ fill: "none", paths: 1 }), null);
});

await t("toggleShuffle/cycleRepeat click the real controls and the change is pushed", async () => {
  let shuffle = false, rep = 0; const sel = {};
  const sync = () => {
    sel[SHUF] = { text: "", fill: shuffle ? ACCENT : WHITE, onClick: () => { shuffle = !shuffle; sync(); } };
    sel[LOOP] = { text: "", fill: rep ? ACCENT : WHITE, paths: rep === 2 ? 3 : 1, onClick: () => { rep = (rep + 1) % 3; sync(); } };
  };
  sync();
  const w = makePage({ selectors: sel }); w.load();
  assert.deepEqual([states(w)[0].shuffle, states(w)[0].repeat], [false, "off"]);
  assert.deepEqual({ ...w.__amzBridge.toggleShuffle() }, { ok: true, via: "dom" }); assert.equal(shuffle, true);
  for (const expect of ["all", "one", "off"]) { assert.deepEqual({ ...w.__amzBridge.cycleRepeat() }, { ok: true, via: "dom" }); await sleep(5); w.__amzBridge.getState(); }
  assert.equal(rep, 0);
  await sleep(300);
  const last = states(w).at(-1); assert.equal(last.shuffle, true); assert.equal(last.repeat, "off");
});

// --- Up Next queue (sanitized, fake data in the captured QueueView shape; see docs/QUEUE.md) ---
const fakeEdge = (ref, title, artist, extra = {}) => ({ entityReferenceId: ref, __typename: "QueueEntityEdge", node: {
  id: "X" + ref, __typename: "Track", title, shortTitle: title, uri: "mrn:track:" + ref, duration: 200, playParams: { id: "mrn:1.0:catalog:track:asin:X" + ref },
  contributingArtists: { edges: [{ role: "PRIMARY", node: { name: artist } }] },
  images: [{ url: "https://img.example/big.jpg", width: 1448 }, { url: "https://img.example/small.jpg", width: 500 }], ...extra } });
const fakeQueue = (refs, id = "Q1", prefix = "Song ") => ({ data: { queue: { id, view: { edges: refs.map((r, i) => fakeEdge(r, prefix + i, "Artist " + i)), pageInfo: { hasNextPage: false } } } } });

function queuePage({ refs, activeRef, calls }) {
  const w = makePage();
  w.navigator.mediaSession.metadata.title = "Song 0"; w.navigator.mediaSession.metadata.artist = "Artist 0"; // the playing track
  const store = { data: { _currentQueueId: "Q1", activeEntityReferenceId: activeRef } };
  w.localStorage = { getItem: () => JSON.stringify(store), "x.cloud-queue-store.2": "" };
  Object.defineProperty(w.localStorage, "length", { value: 1 });
  w.store = store;
  w.fetch = function (url, init) {
    calls.push({ url, init });
    return Promise.resolve({ ok: true, clone() { return this; }, json: () => Promise.resolve(fakeQueue(refs)) });
  };
  w.amznMusic = { appConfig: { csrf: { token: "tok", rnd: "rnd", ts: 123 } } };
  return w;
}
const GQL = "https://gql.music.amazon.com/";
const qBody = JSON.stringify({ operationName: "QueueView", variables: { id: "Q1", currentEntityReferenceId: "r0", limit: 20, direction: "FORWARD" } });

await t("queue: passive QueueView response -> upcoming list (after the active entry, titles/artist/artwork)", async () => {
  const calls = []; const refs = Array.from({ length: 14 }, (_, i) => "r" + i);
  const w = queuePage({ refs, activeRef: "r0", calls }); w.load();
  assert.equal(states(w)[0].queue, null); // nothing known yet
  await w.fetch(GQL, { method: "POST", headers: { "csrf-token": "tok", "x-api-key": "k" }, body: qBody });
  await sleep(350);
  const q = states(w).at(-1).queue;
  assert.equal(q.length, 10); // capped at 10
  assert.deepEqual({ ...q[0] }, { id: "r1", title: "Song 1", artist: "Artist 1", artworkURL: "https://img.example/small.jpg" });
  // track advances: list shifts without a new request, even though the persisted store still points at the old track
  const n = calls.length;
  w.navigator.mediaSession.metadata.title = "Song 3"; w.navigator.mediaSession.metadata.artist = "Artist 3";
  await sleep(2300);
  assert.equal(states(w).at(-1).queue[0].title, "Song 4"); assert.equal(calls.length, n);
});

await t("queue: unknown active entry / non-track / failures -> null (section hidden)", async () => {
  const calls = []; const w = queuePage({ refs: ["r0", "r1"], activeRef: "zzz", calls });
  w.navigator.mediaSession.metadata.title = "Not In Queue"; w.load();
  await w.fetch(GQL, { method: "POST", headers: { a: "b" }, body: qBody }); await sleep(350);
  assert.equal(w.__amzBridge.getState().queue, null); // active entry not in list (radio / other queue)
  const w2 = queuePage({ refs: ["r0"], activeRef: "r0", calls: [] }); w2.load();
  await w2.fetch(GQL, { method: "POST", headers: { a: "b" }, body: qBody }); await sleep(350);
  assert.equal(w2.__amzBridge.getState().queue, null); // last song: nothing upcoming
});

await t("queue: refreshQueue replays the page's headers with fresh csrf; only parsed fields leave the page", async () => {
  const calls = []; const w = queuePage({ refs: ["r0", "r1", "r2"], activeRef: "r0", calls }); w.load();
  assert.equal(w.__amzBridge.refreshQueue().ok, true); // no headers observed yet -> no call
  assert.equal(calls.length, 0);
  await w.fetch(GQL, { method: "POST", headers: { "csrf-token": "old", "csrf-rnd": "o", "csrf-ts": "1", "x-api-key": "key" }, body: JSON.stringify({ operationName: "Other" }) });
  assert.equal(calls.length, 1);
  w.__amzBridge.refreshQueue(); await sleep(50);
  assert.equal(calls.length, 2);
  const c = calls[1]; const body = JSON.parse(c.init.body);
  assert.equal(c.url, GQL); assert.equal(c.init.credentials, "include"); assert.equal(c.init.method, "POST");
  assert.equal(c.init.headers["x-api-key"], "key"); assert.equal(c.init.headers["csrf-token"], "tok");
  assert.equal(body.operationName, "QueueView"); assert.equal(body.variables.id, "Q1");
  assert.equal(body.variables.currentEntityReferenceId, "r0"); assert.equal(body.variables.direction, "FORWARD");
  assert.ok(body.extensions.persistedQuery.sha256Hash);
  await sleep(350);
  assert.equal(states(w).at(-1).queue.length, 2);
  const json = JSON.stringify(w.messages); // nothing sensitive in anything posted to Swift
  for (const secret of ["tok", "key", "csrf", "x-api-key"]) assert.ok(!json.includes(secret), secret);
  w.__amzBridge.refreshQueue(); await sleep(20); assert.equal(calls.length, 2); // throttled
});

await t("queue: other-origin fetches are never observed", async () => {
  const calls = []; const w = queuePage({ refs: ["r0", "r1"], activeRef: "r0", calls }); w.load();
  await w.fetch("https://evil.example/", { headers: { "csrf-token": "x" }, body: qBody });
  w.__amzBridge.refreshQueue(); await sleep(20);
  assert.equal(calls.length, 1);
});

await t("queue: failing request hides the section", async () => {
  const calls = []; const w = queuePage({ refs: ["r0", "r1"], activeRef: "r0", calls });
  const good = w.fetch; let fail = false;
  w.fetch = (u, i) => (fail ? Promise.reject(new Error("net")) : good(u, i));
  w.load();
  await w.fetch(GQL, { headers: { a: "b" }, body: "{}" });
  fail = true;
  w.__amzBridge.refreshQueue(); await sleep(350);
  assert.equal(states(w).at(-1).queue, null);
});

await t("queue: replaced queue with the SAME active ref never shows the old queue's songs; refetches", async () => {
  const calls = []; const w = queuePage({ refs: ["r0", "r1", "r2"], activeRef: "r0", calls });
  w.navigator.mediaSession.metadata.title = "Old 0";
  let next = fakeQueue(["r0", "r1", "r2"], "Q1", "Old ");
  w.fetch = function (url, init) { calls.push({ url, init }); const r = next; return Promise.resolve({ ok: true, clone() { return this; }, json: () => Promise.resolve(r) }); };
  w.load();
  await w.fetch(GQL, { headers: { a: "b" }, body: qBody }); await sleep(350);
  assert.equal(states(w).at(-1).queue[0].title, "Old 1");
  // user starts another queue: new queue id, entity ref happens to be identical
  w.store.data._currentQueueId = "Q2"; next = fakeQueue(["r0", "r1", "r2"], "Q2", "New "); w.navigator.mediaSession.metadata.title = "New 0";
  assert.equal(w.__amzBridge.getState().queue, null); // old songs are not shown for the new queue
  await sleep(4000); // interval tick (2s) -> debounce (1.2s) -> replay
  assert.equal(calls.at(-1).init && JSON.parse(calls.at(-1).init.body).variables.id, "Q2");
  assert.equal(w.__amzBridge.getState().queue[0].title, "New 1");
});

await t("queue: responses arriving out of order never overwrite a newer snapshot", async () => {
  const w = queuePage({ refs: [], activeRef: "r0", calls: [] });
  const pending = []; w.navigator.mediaSession.metadata.title = "cur";
  w.fetch = function () { return new Promise((res) => pending.push(res)); };
  w.load();
  const mk = (title) => ({ ok: true, clone() { return this; }, json: () => Promise.resolve({ data: { queue: { id: "Q1", view: { edges: [fakeEdge("r0", "cur", "a"), fakeEdge("r1", title, "a")], pageInfo: {} } } } }) });
  w.fetch(GQL, { headers: { a: "b" }, body: qBody });   // request #1 (older)
  w.fetch(GQL, { headers: { a: "b" }, body: qBody });   // request #2 (newer)
  pending[1](mk("NEWER")); await sleep(350);
  assert.equal(w.__amzBridge.getState().queue[0].title, "NEWER");
  pending[0](mk("OLDER")); await sleep(350);              // older response resolves last
  assert.equal(w.__amzBridge.getState().queue[0].title, "NEWER");
});

await t("queue: response for a queue that is no longer current is ignored", async () => {
  const calls = []; const w = queuePage({ refs: ["r0", "r1"], activeRef: "r0", calls }); w.load();
  w.store.data._currentQueueId = "Q9"; // store moved on before the (Q1) response arrives
  await w.fetch(GQL, { headers: { a: "b" }, body: qBody }); await sleep(350);
  assert.equal(w.__amzBridge.getState().queue, null);
});

await t("queue: transient failure (503) keeps the snapshot, then a later refresh succeeds", async () => {
  const calls = []; const w = queuePage({ refs: ["r0", "r1", "r2"], activeRef: "r0", calls });
  const good = w.fetch; let mode = "ok";
  w.fetch = (u, i) => (mode === "503" ? Promise.resolve({ ok: false, status: 503, json: () => Promise.reject(new Error("x")) })
    : mode === "net" ? Promise.reject(new Error("net")) : good(u, i));
  w.load();
  await w.fetch(GQL, { headers: { a: "b" }, body: qBody }); await sleep(350);
  assert.equal(states(w).at(-1).queue.length, 2);
  mode = "503"; const n = calls.length;
  w.__amzBridge.refreshQueue(); await sleep(50);
  assert.equal(w.__amzBridge.getState().queue.length, 2); // snapshot kept
  mode = "net"; await sleep(4100); w.__amzBridge.refreshQueue(); await sleep(50);
  assert.equal(w.__amzBridge.getState().queue.length, 2); // still kept after a network error
  mode = "ok"; await sleep(4100); w.__amzBridge.refreshQueue(); await sleep(100);
  assert.ok(calls.length > n); // retry went through (not blocked by in-flight / lastFetchKey)
});

await t("queue: hung replay times out, releases in-flight, and later replays work", async () => {
  const calls = []; const w = queuePage({ refs: ["r0", "r1", "r2"], activeRef: "r0", calls });
  const good = w.fetch; let hang = false;
  w.fetch = (u, i) => (hang ? new Promise(() => {}) : good(u, i));
  w.load();
  await w.fetch(GQL, { headers: { a: "b" }, body: qBody }); await sleep(350);
  hang = true; calls.length = 0;
  w.__amzBridge.refreshQueue(); await sleep(50);
  w.__amzBridge.refreshQueue(); // blocked while in flight (also throttled)
  hang = false;
  await sleep(10600); // > timeoutMs
  w.__amzBridge.refreshQueue(); await sleep(100);
  assert.equal(calls.length, 1, "replay possible again after the timeout");
  assert.equal(w.__amzBridge.getState().queue.length, 2);
});

// --- Loaded-but-paused track right after launch: mediaSession has no metadata, the DOM player bar does ---
const PLAYBTN = 'button[data-testid="IconButton,MiniPlayer_Play"]';
function barPage({ playing = false, playbackStore = true, appConfig, pathname = "/", entityType = "Track" } = {}) {
  const w = makePage({ mediaSession: false });
  const link = (label) => ({ getAttribute: (n) => (n === "aria-label" ? label : null), textContent: "" });
  const block = { parentElement: null, querySelector: (sel) => (sel === 'a[href^="/artists/"]' ? link("Example Artist") : sel === 'a[href^="/albums/"]' ? link("Example Album") : null) };
  const title = { textContent: "Example Title", parentElement: { parentElement: block, querySelector: () => null }, getAttribute: (n) => (n === "aria-label" ? "Example Title" : null) };
  const img = { currentSrc: "https://m.media-amazon.com/images/I/ABC123._UR128,128_.jpg" };
  const clicks = w.clicked;
  const btn = (sel) => ({ textContent: "", click: () => clicks.push(sel), getAttribute: () => null });
  w.document.querySelector = (s) => s === 'a[data-testid="MiniPlayer_Title"]' ? title
    : s === '[data-testid="ListItemImage,MiniPlayer_Image"] img' ? img
    : s === PLAYBTN && !playing ? btn(PLAYBTN)
    : s === 'button[data-testid="IconButton,MiniPlayer_Pause"]' && playing ? btn("pause") : null;
  w.location = { href: "https://music.amazon.com" + pathname, pathname };
  if (appConfig) w.amznMusic = { appConfig };
  const store = { data: { currentTimeInSeconds: 96.5, duration: 137.1, currentEntity: { __typename: entityType, mediaType: entityType === "Track" ? "AUDIO" : "VIDEO" } } };
  w.localStorage = playbackStore ? { getItem: () => JSON.stringify(store), "1.playback-controller.1": "" } : { getItem: () => null };
  return w;
}

await t("DOM fallback: mediaSession empty -> loaded paused track from the player bar (title/artist/album/art/progress, paused)", async () => {
  const w = barPage({ appConfig: { customerId: "C1", isCirrusAuthExpired: false } }); w.load();
  const s = states(w)[0];
  assert.equal(s.title, "Example Title"); assert.equal(s.artist, "Example Artist"); assert.equal(s.album, "Example Album");
  assert.equal(s.artworkURL, "https://m.media-amazon.com/images/I/ABC123._UR512,512_.jpg"); // upsized from the 128px thumbnail
  assert.equal(s.isPlaying, false); assert.equal(s.duration, 137.1); assert.equal(s.position, 96.5);
  assert.equal(s.trackId, "Example Title|Example Artist|Example Album");
  assert.equal(s.signedIn, true);
  // Play via the existing command path clicks the page's play button
  assert.deepEqual({ ...w.__amzBridge.toggle() }, { ok: true, via: "dom" });
  assert.deepEqual(w.clicked, [PLAYBTN]);
});

await t("DOM fallback: pause button visible without a media element -> playing; no player bar -> no track; no store -> null progress", async () => {
  const w = barPage({ playing: true, playbackStore: false }); w.load();
  const s = states(w)[0]; assert.equal(s.isPlaying, true); assert.equal(s.duration, null); assert.equal(s.position, null);
  const none = makePage({ mediaSession: false }); none.load();
  assert.equal(states(none)[0].title, null); assert.equal(states(none)[0].queue, null);
});

await t("mediaSession metadata still wins over the DOM fallback (identity stays stable when playback starts)", async () => {
  const w = barPage({}); w.navigator = { mediaSession: { metadata: { title: "Example Title", artist: "Example Artist", album: "Example Album", artwork: [] }, setActionHandler() {} } };
  w.load(); const s = states(w)[0];
  assert.equal(s.trackId, "Example Title|Example Artist|Example Album");
});

await t("signed-in detection: customer present = true; expired auth / sign-in URL = false; no customer / unknown config = null", async () => {
  const si = (o) => { const w = barPage(o); w.load(); return states(w)[0].signedIn; };
  assert.equal(si({ appConfig: { customerId: "C1" } }), true);
  assert.equal(si({ appConfig: { customerId: "" } }), null); // valid-looking config without a customer: unknown, not "signed out"
  assert.equal(si({ appConfig: {} }), null);
  assert.equal(si({ appConfig: { customerId: "C1", isCirrusAuthExpired: true } }), false);
  assert.equal(si({ pathname: "/ap/signin", appConfig: { customerId: "C1" } }), false);
  assert.equal(si({ pathname: "/ap/register" }), false);
  assert.equal(si({}), null); // config not loaded yet: unknown, never guessed
});

// --- Next / Previous refresh (bridge 1.5.1): the persisted store lags a track change by ~3-5 s, so match the playing track instead ---
const ALL = Array.from({ length: 30 }, (_, i) => ({ ref: "r" + i, title: "Song " + i }));
function serverPage({ start = 5, current = 5, storeRef, calls, serve }) {
  const w = makePage();
  const setPlaying = (i) => { w.navigator.mediaSession.metadata.title = "Song " + i; w.navigator.mediaSession.metadata.artist = "Artist"; };
  setPlaying(current);
  const store = { data: { _currentQueueId: "Q1", activeEntityReferenceId: storeRef || "r" + start } };
  w.localStorage = { getItem: () => JSON.stringify(store), "x.cloud-queue-store.2": "" };
  w.store = store; w.setPlaying = setPlaying;
  w.fetch = function (url, init) {
    const v = init && typeof init.body === "string" ? JSON.parse(init.body).variables : null;
    if (v) calls.push(v);
    const resp = !v ? { data: {} } : serve ? serve(v) : defaultServe(v);
    return Promise.resolve({ ok: true, clone() { return this; }, json: () => Promise.resolve(resp) });
  };
  w.amznMusic = { appConfig: { csrf: { token: "t", rnd: "r", ts: 1 } } };
  return w;
}
function defaultServe(v) {
  const i = Math.max(0, ALL.findIndex((x) => x.ref === v.currentEntityReferenceId));
  const slice = v.direction === "BACKWARD" ? ALL.slice(Math.max(0, i - v.limit + 1), i + 1) : ALL.slice(i, i + v.limit);
  return { data: { queue: { id: "Q1", view: { edges: slice.map((x) => fakeEdge(x.ref, x.title, "Artist")), pageInfo: { hasNextPage: i + v.limit < ALL.length } } } } };
}
const seed = (w, ref) => w.fetch(GQL, { method: "POST", headers: { a: "b" }, body: JSON.stringify({ operationName: "QueueView", variables: { id: "Q1", currentEntityReferenceId: ref, limit: 20, direction: "FORWARD" } }) });
const titles = (w) => JSON.parse(JSON.stringify((w.__amzBridge.getState().queue || []).map((x) => x.title)));

await t("next: the upcoming list shifts right away although the persisted store still points at the old track (no request)", async () => {
  const calls = []; const w = serverPage({ start: 5, current: 5, calls }); w.load();
  await seed(w, "r5"); await sleep(350);
  assert.deepEqual(titles(w).slice(0, 2), ["Song 6", "Song 7"]);
  const n = calls.length;
  w.setPlaying(6); await w.__amzBridge.next(); // no player-bar button in this fake page: the command fails but still re-derives
  await sleep(400);
  assert.deepEqual(titles(w).slice(0, 2), ["Song 7", "Song 8"]); // store ref is still r5
  assert.equal(w.store.data.activeEntityReferenceId, "r5");
  assert.equal(calls.length, n); // served from the cache
});

await t("previous past the cached start: BACKWARD from the first cached entry, merged, within ~1s", async () => {
  const calls = []; const w = serverPage({ start: 5, current: 5, calls }); w.load();
  await seed(w, "r5"); await sleep(350);
  calls.length = 0;
  w.setPlaying(4); await w.__amzBridge.previous(); // store still says r5 (stale)
  await sleep(1100);
  assert.deepEqual(titles(w).slice(0, 2), ["Song 5", "Song 6"]);
  const back = calls.find((c) => c.direction === "BACKWARD");
  assert.ok(back, "BACKWARD request made"); assert.equal(back.currentEntityReferenceId, "r5");
  // and one more step back reuses the merged cache
  const n = calls.length; w.setPlaying(3); await sleep(400);
  assert.equal(titles(w)[0], "Song 4"); assert.ok(calls.length <= n + 2);
});

await t("rapid repeated next clicks beyond the cache coalesce (not one request per click) and end correct", async () => {
  const calls = []; const w = serverPage({ start: 0, current: 0, calls, serve: (v) => defaultServe({ ...v, limit: Math.min(v.limit, 5) }) }); w.load();
  await seed(w, "r0"); await sleep(350);
  calls.length = 0;
  for (let i = 1; i <= 8; i++) { w.setPlaying(i + 5); w.__amzBridge.next(); await sleep(30); } // jumps beyond the 5-entry cache each time
  await sleep(1800);
  assert.ok(calls.length <= 6, "requests: " + calls.length); // 8 clicks, bounded (kick gap + in-flight guard)
  assert.equal(titles(w)[0], "Song 14"); // playing Song 13
});

await t("stale persisted store: first fetch (old ref) lacks the playing track -> retries until the store catches up", async () => {
  const calls = []; let ready = false;
  const serve = (v) => defaultServe({ ...v, currentEntityReferenceId: ready ? "r10" : "r20" });
  const w = serverPage({ start: 10, current: 10, storeRef: "r20", calls, serve }); w.load();
  await seed(w, "r20"); await sleep(350); // page's own snapshot built from the lagging ref
  assert.deepEqual(titles(w), []); // playing track not in it -> hidden, never wrong songs
  ready = true; w.store.data.activeEntityReferenceId = "r10"; // store caught up
  await sleep(4500);
  assert.deepEqual(titles(w).slice(0, 2), ["Song 11", "Song 12"]);
  assert.ok(calls.length <= 8, "bounded retries: " + calls.length);
});

await t("a snapshot that lacks the playing track never replaces one that has it", async () => {
  const calls = []; let lag = false;
  const serve = (v) => defaultServe(lag ? { ...v, currentEntityReferenceId: "r20" } : v);
  const w = serverPage({ start: 5, current: 5, calls, serve }); w.load();
  await seed(w, "r5"); await sleep(350);
  assert.equal(titles(w)[0], "Song 6");
  lag = true; await seed(w, "r20"); await sleep(350); // late/lagging passive response
  assert.equal(titles(w)[0], "Song 6");
});

// --- Play Similar Music (bridge 1.6.0/1.7.1): the player bar's "..." menu item, clicked while the menu is invisible ---
const MORE = 'button[data-testid="IconButton,MiniPlayer_ContextMenu"]';
const SIM_TID = '[data-testid="OverflowMenu_Option_PlaySimilar"]';
function similarPage({ hasButton = true, hasItem = true, entityType = "Track", label = "Play Similar Music", byTestId = true, preOpen = false, neverOpens = false, nested = false } = {}) {
  const w = barPage({ entityType });
  const base = w.document.querySelector;
  const body = { children: [] };
  const log = { itemClicks: 0, moreClicks: 0, visibleAtItemClick: null, wrongClicks: 0 };
  let open = preOpen;
  const item = { textContent: label, click: () => { log.itemClicks++; log.visibleAtItemClick = wrapper.style.visibility; open = false; body.children = []; } };
  const other = { textContent: "Share", click: () => { log.wrongClicks++; } };
  const wrapper = { nodeType: 1, position: "fixed", parentElement: body, style: { visibility: "", pointerEvents: "" }, querySelector: (sel) => (byTestId && hasItem && (sel === SIM_TID + ' [role="menuitem"]') ? item : null) };
  const inner = nested ? { nodeType: 1, position: "static", parentElement: wrapper, style: { visibility: "", pointerEvents: "" }, querySelector: (sel) => wrapper.querySelector(sel) } : wrapper;
  const menu = { role: "menu", position: "static", parentElement: inner, style: { visibility: "", pointerEvents: "" }, querySelectorAll: (sel) => (sel === '[role="menuitem"]' ? (hasItem ? [other, item] : [other]) : []) };
  if (preOpen) body.children = [wrapper];
  w.document.body = body;
  w.document.querySelector = (s) => {
    if (s === MORE) return hasButton ? { textContent: "", getAttribute: () => null, click: () => { log.moreClicks++; if (neverOpens) return; open = !open; body.children = open ? [wrapper] : []; } } : null;
    return base(s);
  };
  const qa = w.document.querySelectorAll;
  w.document.querySelectorAll = (s) => (s === '[role="menu"]' ? (open ? [menu] : []) : qa(s));
  w.log = log; w.portal = wrapper; w.menu = menu; w.inner = inner;
  return w;
}

await t("playSimilar availability: music track with the more button only; hidden for podcasts/no button; reported in state", async () => {
  const ok = similarPage(); ok.load(); assert.equal(states(ok)[0].canPlaySimilar, true);
  const pod = similarPage({ entityType: "PodcastEpisode" }); pod.load(); assert.equal(states(pod)[0].canPlaySimilar, false);
  const nob = similarPage({ hasButton: false }); nob.load(); assert.equal(states(nob)[0].canPlaySimilar, false);
  const none = makePage({ mediaSession: false }); none.load(); assert.equal(states(none)[0].canPlaySimilar, false); // nothing loaded
});

await t("playSimilar: opens the menu, finds the item by data-testid (any UI language), clicks it while hidden, restores, leaves no menu open", async () => {
  const w = similarPage({ label: "Ähnliche Musik abspielen" }); w.load();
  const r = await w.__amzBridge.playSimilar();
  assert.deepEqual({ ...r }, { ok: true, via: "dom" });
  assert.equal(w.log.moreClicks, 1); assert.equal(w.log.itemClicks, 1); assert.equal(w.log.wrongClicks, 0);
  assert.equal(w.log.visibleAtItemClick, "hidden"); // invisible by the time the item is clicked (no flash)
  await sleep(350);
  assert.equal(w.portal.style.visibility, ""); assert.equal(w.portal.style.pointerEvents, ""); // restored for the page's own use
});

await t("playSimilar: without a testid the localized label table is used (en/de/fr/es/it/pt/ja); other items are never clicked", async () => {
  for (const label of ["Play Similar Music", "Ähnliche Musik abspielen", "Musique similaire", "Reproducir música similar", "Riproduci musica simile", "Reproduzir música semelhante", "似た音楽を再生"]) {
    const w = similarPage({ label, byTestId: false }); w.load();
    assert.equal((await w.__amzBridge.playSimilar()).ok, true, label); assert.equal(w.log.wrongClicks, 0);
  }
  const x = similarPage({ label: "Something else", byTestId: false }); x.load();
  assert.equal((await x.__amzBridge.playSimilar()).reason, "no_similar_item");
});

await t("playSimilar: portal nested deeper than <body>: the fixed wrapper is hidden/restored, not just the menu", async () => {
  const w = similarPage({ nested: true }); w.load();
  assert.equal((await w.__amzBridge.playSimilar()).ok, true);
  assert.equal(w.log.visibleAtItemClick, "hidden"); await sleep(350);
  assert.equal(w.portal.style.visibility, ""); assert.equal(w.inner.style.visibility, "");
});

await t("playSimilar: a menu the user already has open is never touched (menu_open)", async () => {
  const w = similarPage({ preOpen: true }); w.load();
  assert.equal((await w.__amzBridge.playSimilar()).reason, "menu_open");
  assert.equal(w.log.moreClicks, 0); assert.equal(w.log.itemClicks, 0); assert.equal(w.portal.style.visibility, "");
});

await t("playSimilar: 'no item' blacklists the track only after 2 consecutive failures; timeouts never do; success resets", async () => {
  const w = similarPage({ hasItem: false }); w.load();
  const p1 = w.__amzBridge.playSimilar(); const busy = await w.__amzBridge.playSimilar();
  assert.deepEqual({ ...busy }, { ok: false, reason: "busy" });
  assert.deepEqual({ ...(await p1) }, { ok: false, reason: "no_similar_item" });
  assert.equal(w.log.moreClicks, 2); // opened, then toggled closed
  await sleep(300); assert.equal(w.__amzBridge.getState().canPlaySimilar, true); // one failure: still offered
  assert.equal((await w.__amzBridge.playSimilar()).reason, "no_similar_item");
  await sleep(300); assert.equal(w.__amzBridge.getState().canPlaySimilar, false); // second: hidden for this track
  const np = similarPage({ hasButton: false }); np.load(); assert.equal((await np.__amzBridge.playSimilar()).reason, "no_more_menu");
  const pod = similarPage({ entityType: "PodcastEpisode" }); pod.load(); assert.equal((await pod.__amzBridge.playSimilar()).reason, "unsupported_item");
  // menu never appears (page busy / slow): timeout, not a verdict about the track
  const slow = similarPage({ neverOpens: true }); slow.load();
  assert.equal((await slow.__amzBridge.playSimilar()).reason, "menu_timeout");
  assert.equal((await slow.__amzBridge.playSimilar()).reason, "menu_timeout");
  assert.equal(slow.__amzBridge.getState().canPlaySimilar, true);
});

// --- Jump to an Up Next entry (bridge 1.7.0/1.7.1): playbackController.playQueueEntity({entityPlaybackInstanceId, uri, duration, id}, t) ---
const PC_HINT = 3266;
// mode: "capture" (the page initialises the module through the wrapped __d), "scan" (hook unavailable: capped neighbour scan),
// "registry" (runtime exposes getModules), "none" (hook active but the module never initialises)
function jumpPage({ mode = "capture", current = 5, impl, scanAt = PC_HINT + 7 } = {}) {
  const calls = []; const fcalls = [];
  const w = serverPage({ start: 5, current, calls: fcalls });
  const pcalls = calls;
  const pc = { playQueueEntity: impl || ((p, t) => { pcalls.push({ p, t }); return Promise.resolve(); }) };
  w.pcalls = pcalls; w.pc = pc; w.rcalls = [];
  if (mode === "scan") {
    w.__d = function () {}; // bundle "already loaded": no hook
    w.__r = (id) => { w.rcalls.push(id); if (id === scanAt) return { playbackController: pc }; throw new Error("Requiring unknown module " + id); };
  }
  if (mode === "registry") {
    w.__d = function () {};
    w.__r = Object.assign((id) => { w.rcalls.push(id); throw new Error("must not execute modules"); }, { getModules: () => new Map([
      [1, { isInitialized: false, publicModule: { exports: { playbackController: { playQueueEntity() { throw new Error("uninitialised module used"); } } } } }],
      [2, { isInitialized: true, publicModule: { exports: { playbackController: pc } } }]]) });
  }
  w.initController = () => { // what the page does: define the module, later run its factory
    const stored = {}; w.__d = (factory, id) => { stored[id] = factory; };
    w.__d(function (g, r, ia, iall, module) { module.exports.playbackController = pc; }, PC_HINT + 900, []);
    const mod = { exports: {} }; stored[PC_HINT + 900](w, null, null, null, mod, mod.exports, []); return mod;
  };
  return w;
}
const seedAndSettle = async (w) => { await seed(w, "r5"); await sleep(350); };

await t("controller: captured when the PAGE initialises its module through the wrapped __d (no scanning, id-independent)", async () => {
  const w = jumpPage(); w.load(); await seedAndSettle(w);
  assert.equal(w.__amzBridge.getState().queue[0].id, "r6");
  assert.equal(w.__amzBridge.getState().canJumpToQueueItem, false); // module not initialised yet
  const mod = w.initController(); assert.ok(mod.exports.playbackController); // the page's own factory result is untouched
  await sleep(150);
  assert.equal(w.__amzBridge.getState().canJumpToQueueItem, true);
  assert.equal(w.rcalls.length, 0); // __r never called
});

await t("controller: runtime registry is used when exposed, inspecting only ALREADY-INITIALISED modules (never executing __r)", async () => {
  const w = jumpPage({ mode: "registry" }); w.load(); await seedAndSettle(w); await sleep(150);
  assert.equal(w.__amzBridge.getState().canJumpToQueueItem, true); assert.equal(w.rcalls.length, 0);
  assert.equal((await w.__amzBridge.playQueueItem("r6")).ok, true); assert.equal(w.pcalls.length, 1);
});

await t("controller: fallback scan is capped to +-200 around the hint, chunked, backed off (max 3 tries), never cached as a permanent null", async () => {
  const hit = jumpPage({ mode: "scan" }); hit.load(); await seedAndSettle(hit);
  hit.__amzBridge.getState(); await sleep(300);
  assert.equal(hit.__amzBridge.getState().canJumpToQueueItem, true);
  assert.ok(hit.rcalls.every((id) => Math.abs(id - PC_HINT) <= 200), "ids within the radius");
  const miss = jumpPage({ mode: "scan", scanAt: PC_HINT + 400 }); miss.load(); await seedAndSettle(miss);
  miss.__amzBridge.getState(); await sleep(500);
  assert.equal(miss.__amzBridge.getState().canJumpToQueueItem, false);
  assert.ok(miss.rcalls.length <= 401 && miss.rcalls.length >= 200, "one bounded scan: " + miss.rcalls.length);
  assert.ok(miss.rcalls.every((id) => Math.abs(id - PC_HINT) <= 200));
  const n = miss.rcalls.length; miss.__amzBridge.getState(); await sleep(300);
  assert.equal(miss.rcalls.length, n); // backoff: no immediate re-scan
});

await t("queue items carry ids; canJumpToQueueItem is false without a controller (never claims it can jump)", async () => {
  const w = jumpPage({ mode: "none" }); w.load(); await seedAndSettle(w);
  assert.equal(w.__amzBridge.getState().queue[1].id, "r7"); await sleep(150);
  assert.equal(w.__amzBridge.getState().canJumpToQueueItem, false);
});

await t("playQueueItem: calls the page's playQueueEntity with the entry's ids for the 2nd/3rd upcoming item", async () => {
  const w = jumpPage(); w.load(); await seedAndSettle(w); w.initController();
  const r = await w.__amzBridge.playQueueItem("r7"); // 2nd upcoming
  assert.deepEqual({ ...r }, { ok: true, via: "controller" });
  assert.equal(w.pcalls.length, 1);
  const p = w.pcalls[0].p; assert.equal(p.entityPlaybackInstanceId, "r7"); assert.equal(p.id, "Xr7"); assert.ok(typeof p.uri === "string"); assert.equal(typeof w.pcalls[0].t, "number");
  await sleep(700);
  w.setPlaying(7); await sleep(400); // page moved on; list follows the new current track
  assert.equal(titles(w)[0], "Song 8");
  const r3 = await w.__amzBridge.playQueueItem("r10"); assert.equal(r3.ok, true); assert.equal(w.pcalls.at(-1).p.entityPlaybackInstanceId, "r10");
});

await t("playQueueItem failures: stale/current/earlier id, unknown id, invalid argument, rapid repeat, no controller", async () => {
  const w = jumpPage(); w.load(); await seedAndSettle(w); w.initController();
  assert.equal((await w.__amzBridge.playQueueItem("r5")).reason, "stale_item");   // the playing track itself
  assert.equal((await w.__amzBridge.playQueueItem("r2")).reason, "unknown_item"); // not in the cache
  assert.equal((await w.__amzBridge.playQueueItem("nope")).reason, "unknown_item");
  assert.equal((await w.__amzBridge.playQueueItem("")).reason, "invalid_argument");
  assert.equal((await w.__amzBridge.playQueueItem(42)).reason, "invalid_argument");
  assert.equal((await w.__amzBridge.playQueueItem("x".repeat(300))).reason, "invalid_argument");
  assert.equal(w.pcalls.length, 0);
  assert.equal((await w.__amzBridge.playQueueItem("r6")).ok, true);
  assert.equal((await w.__amzBridge.playQueueItem("r7")).reason, "busy"); // rapid second click
  assert.equal(w.pcalls.length, 1);
  w.setPlaying(8); await sleep(700);
  assert.equal((await w.__amzBridge.playQueueItem("r6")).reason, "stale_item"); // r6 already played by now
  const nc = jumpPage({ mode: "none" }); nc.load(); await seedAndSettle(nc);
  assert.equal((await nc.__amzBridge.playQueueItem("r6")).reason, "no_controller");
});

await t("playQueueItem: a controller that throws or rejects reports jump_failed, never an exception", async () => {
  const th = jumpPage({ impl: () => { throw new Error("boom"); } }); th.load(); await seedAndSettle(th); th.initController();
  assert.deepEqual({ ...(await th.__amzBridge.playQueueItem("r6")) }, { ok: false, reason: "jump_failed" });
  const rj = jumpPage({ impl: () => Promise.reject(new Error("no")) }); rj.load(); await seedAndSettle(rj); rj.initController();
  assert.equal((await rj.__amzBridge.playQueueItem("r6")).ok, false);
});

console.log(`\n${pass} passed, ${failN} failed`);
process.exit(failN ? 1 : 0);
