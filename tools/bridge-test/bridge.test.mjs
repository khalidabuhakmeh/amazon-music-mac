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
  w.URL = URL; w.setTimeout = setTimeout; w.clearTimeout = clearTimeout; w.setInterval = (f, ms) => setInterval(f, ms).unref(); w.Date = Date;
  w.getComputedStyle = (p) => ({ fill: p.fill });
  w.location = { href: "https://music.amazon.com/" };
  const observers = [];
  w.MutationObserver = class { constructor(cb) { this.cb = cb; observers.push(this); } observe() {} };
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
  assert.equal(ready.payload.bridgeVersion, "1.3.0"); assert.equal(ready.v, 1);
  assert.equal(ready.payload.sources.mediaSession, true);
  const s = states(w)[0];
  assert.deepEqual(s, { title: "Example Track", artist: "Example Artist", album: "Example Album",
    artworkURL: "https://music.amazon.com/big.jpg", duration: 136.8, position: 41, isPlaying: true,
    trackId: "Example Track|Example Artist|Example Album", liked: null, shuffle: null, repeat: null });
  assert.ok(w.messages.some((m) => m.type === "position"));
  assert.equal(w.__amzBridge.version, "1.3.0");
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

console.log(`\n${pass} passed, ${failN} failed`);
process.exit(failN ? 1 : 0);
