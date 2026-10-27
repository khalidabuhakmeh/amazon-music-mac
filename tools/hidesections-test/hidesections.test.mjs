// Run: node tools/hidesections-test/hidesections.test.mjs  (no deps). Mock DOM with a tiny selector engine
// (comma lists, ` i` flag, tag, #id, [attr], [attr=v|*=|^=|$=|~=]; no combinators / :has).
import vm from "node:vm";
import fs from "node:fs";
import assert from "node:assert/strict";
import path from "node:path";
import { fileURLToPath } from "node:url";

const src = fs.readFileSync(path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../Sources/AmazonMusic/Resources/hideSections.js"), "utf8");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function parseSimple(sel) {
  sel = sel.trim();
  const m = /^([a-zA-Z][\w-]*|\*)?(#[\w-]+)?((?:\[[^\]]+\])*)$/.exec(sel);
  if (!m) throw new Error("unsupported selector: " + sel); // like an invalid selector in a browser
  const attrs = [...m[3].matchAll(/\[([\w-]+)(?:([*^$~]?=)"?([^"\]]*)"?(?:\s+(i))?)?\]/g)].map((a) => ({ n: a[1], op: a[2], v: a[3], ci: !!a[4] }));
  return { tag: m[1] && m[1] !== "*" ? m[1].toLowerCase() : null, id: m[2] && m[2].slice(1), attrs };
}
function splitTop(sel) { return sel.split(",").map((s) => s.trim()).filter(Boolean); }

class El {
  constructor(tag, attrs = {}, children = [], text = "") {
    this.tagName = tag.toUpperCase(); this.attrs = { ...attrs }; this.children = []; this.parentElement = null; this.parentNode = null;
    this.ownText = text; this.isConnected = true; this.paused = true; this.ended = false;
    children.forEach((c) => this.appendChild(c));
  }
  get id() { return this.attrs.id || ""; }
  set id(v) { this.attrs.id = v; }
  get textContent() { return this.ownText + this.children.map((c) => c.textContent).join(""); }
  set textContent(v) { this.ownText = String(v); this.children = []; }
  appendChild(c) { c.parentElement = this; c.parentNode = this; this.children.push(c); return c; }
  removeChild(c) { this.children = this.children.filter((x) => x !== c); c.parentElement = c.parentNode = null; c.isConnected = false; return c; }
  getAttribute(n) { return n in this.attrs ? this.attrs[n] : null; }
  setAttribute(n, v) { this.attrs[n] = String(v); }
  removeAttribute(n) { delete this.attrs[n]; }
  hasAttribute(n) { return n in this.attrs; }
  matches(sel) {
    return splitTop(sel).some((s) => {
      const p = parseSimple(s);
      if (p.tag && this.tagName.toLowerCase() !== p.tag) return false;
      if (p.id && this.attrs.id !== p.id) return false;
      return p.attrs.every(({ n, op, v, ci }) => {
        if (!(n in this.attrs)) return false;
        let a = this.attrs[n]; if (ci) { a = a.toLowerCase(); v = v.toLowerCase(); }
        switch (op) { case undefined: return true; case "=": return a === v; case "*=": return a.includes(v); case "^=": return a.startsWith(v); case "$=": return a.endsWith(v); case "~=": return a.split(/\s+/).includes(v); }
        return false;
      });
    });
  }
  closest(sel) { for (let e = this; e; e = e.parentElement) if (e.matches(sel)) return e; return null; }
  querySelectorAll(sel) { const out = []; const walk = (e) => e.children.forEach((c) => { if (c.matches(sel)) out.push(c); walk(c); }); walk(this); return out; }
  querySelector(sel) { return this.querySelectorAll(sel)[0] || null; }
}

function makePage(build, { pathname = "/home", throwing = false } = {}) {
  const html = new El("html"); const head = new El("head"); const body = new El("body");
  html.appendChild(head); html.appendChild(body); body.appendChild(build());
  const observers = [];
  const doc = {
    documentElement: html, head, body,
    createElement: (t) => new El(t),
    getElementById: (id) => { let f = null; const w = (e) => { if (e.attrs.id === id) f = f || e; e.children.forEach(w); }; w(html); return f; },
    querySelectorAll: (s) => (throwing ? (() => { throw new Error("boom"); })() : html.querySelectorAll(s)),
    addEventListener() {},
  };
  const history = { pushState() {}, replaceState() {} };
  const w = { document: doc, location: { pathname }, history, setTimeout, clearTimeout };
  w.window = w; w.top = w;
  w.MutationObserver = class { constructor(cb) { this.cb = cb; observers.push(this); this.on = false; } observe() { this.on = true; } disconnect() { this.on = false; } };
  w.fire = () => observers.filter((o) => o.on).forEach((o) => o.cb([]));
  w.observers = observers;
  vm.createContext(w);
  return { w, doc, html, body, head };
}
const run = (w, flag, audible, getApp, homeBanner) => vm.runInContext((flag === undefined && audible === undefined && getApp === undefined && homeBanner === undefined ? "" : `window.__amzHideSectionsInitial=${JSON.stringify({ podcasts: flag === true, audible: audible === true, getApp: getApp === true, homeBanner: homeBanner === true })};`) + src, w);
const hidden = (root) => root.querySelectorAll("[data-amz-hide-podcasts]");
const A = "data-amz-hide-podcasts";
const AA = "data-amz-hide-audible";

// Realistic structure (from docs/PODCASTS.md): top nav tab, search pills, search widgets, home shelves.
function homeDom() {
  const h = (t) => new El("h1", { role: "heading", "aria-label": t }, [new El("h4", { role: "heading" }, [], t)]);
  const shelf = (title, hrefs) => new El("div", { "data-testid": "Shelf" }, [h(title), new El("div", {}, hrefs.map((hr) => new El("div", { "data-testid": "CarouselItem" }, [new El("a", { href: hr, role: "link" })])))]);
  return new El("div", { id: "root" }, [
    new El("header", {}, [new El("nav", {}, [
      new El("button", { "data-testid": "TopNavBar_HomeTab" }),
      new El("button", { "data-testid": "TopNavBar_PodcastTab", "aria-label": "Podcasts" }),
    ])]),
    new El("div", { "data-testid": "page" }, [
      shelf("Albums for You", ["/albums/AAAAAAAAAA"]),
      shelf("Podcasts for you", ["/podcasts/BBBBBBBBBB/CCCCCCCCCC"]),
      shelf("Podcasten", ["/albums/x"]),
      shelf("Playlists for You", ["/playlists/DDDDDDDDDD", "/podcasts/EEEEEEEEEE/FFFFFFFFFF"]),
      new El("div", { "data-testid": "SearchResultsTypeFilter_Pill_podcast" }),
      new El("div", { "data-testid": "SearchResultsWidget_PodcastShow" }, [new El("h4", {}, [], "Podcasts")]),
      new El("h4", {}, [], 'Search results for "podcast"'),
    ]),
  ]);
}

let passed = 0;
async function t(name, fn) { await fn(); passed++; console.log("ok -", name); }

await t("disabled by default: nothing hidden, no style", () => {
  const p = makePage(homeDom); run(p.w);
  assert.equal(hidden(p.html).length, 0); assert.equal(p.doc.getElementById("amz-hide-sections-style"), null);
  assert.equal(p.w.__amzHideSections.isEnabled("podcasts"), false);
});

await t("enable hides nav tab, pills, widgets, shelves by heading (incl. localized), and cards; leaves others", () => {
  const p = makePage(homeDom); run(p.w); p.w.__amzHideSections.setEnabled("podcasts", true);
  const q = (sel) => p.html.querySelectorAll(sel);
  assert.ok(q('[data-testid="TopNavBar_PodcastTab"]')[0].hasAttribute(A), "nav tab");
  assert.ok(!q('[data-testid="TopNavBar_HomeTab"]')[0].hasAttribute(A), "home tab untouched");
  assert.ok(q('[data-testid*="SearchResultsTypeFilter_Pill_podcast"]')[0].hasAttribute(A), "pill");
  assert.ok(q('[data-testid="SearchResultsWidget_PodcastShow"]')[0].hasAttribute(A), "widget");
  const shelves = q('[data-testid="Shelf"]');
  assert.ok(!shelves[0].hasAttribute(A), "Albums shelf visible");
  assert.ok(shelves[1].hasAttribute(A), "Podcasts for you shelf hidden");
  assert.ok(shelves[2].hasAttribute(A), "Podcasten shelf hidden");
  assert.ok(!shelves[3].hasAttribute(A), "mixed shelf container stays");
  const cards = shelves[3].querySelectorAll('[data-testid="CarouselItem"]');
  assert.ok(!cards[0].hasAttribute(A) && cards[1].hasAttribute(A), "only the podcast card hidden");
  assert.ok(!q("h4").find((h) => h.textContent.startsWith("Search results")).hasAttribute(A), "quoted heading untouched");
  assert.ok(!q("header")[0].hasAttribute(A) && !q("nav")[0].hasAttribute(A) && !q("#root")[0].hasAttribute(A), "chrome untouched");
  assert.ok(p.doc.getElementById("amz-hide-sections-style").textContent.includes("display:none"));
});

await t("disable fully restores and removes style/observer", () => {
  const p = makePage(homeDom); run(p.w); const api = p.w.__amzHideSections;
  api.setEnabled("podcasts", true); assert.ok(hidden(p.html).length > 0);
  api.setEnabled("podcasts", false);
  assert.equal(hidden(p.html).length, 0); assert.equal(p.doc.getElementById("amz-hide-sections-style"), null);
  assert.ok(p.w.observers.every((o) => !o.on)); assert.equal(api.isEnabled("podcasts"), false);
});

await t("initial flag enables at load", () => {
  const p = makePage(homeDom); run(p.w, true);
  assert.equal(p.w.__amzHideSections.isEnabled("podcasts"), true); assert.ok(hidden(p.html).length > 0);
});

await t("idempotent: double injection keeps first instance; repeated enable adds one style/observer", () => {
  const p = makePage(homeDom); run(p.w, true); const first = p.w.__amzHideSections; const n = hidden(p.html).length;
  run(p.w, false); assert.equal(p.w.__amzHideSections, first); assert.equal(first.isEnabled("podcasts"), true);
  first.setEnabled("podcasts", true); first.setEnabled("podcasts", true);
  assert.equal(hidden(p.html).length, n);
  assert.equal(p.head.children.filter((c) => c.attrs.id === "amz-hide-sections-style").length + p.html.children.filter((c) => c.attrs.id === "amz-hide-sections-style").length, 1);
  assert.equal(p.w.observers.length, 1);
});

await t("observer picks up dynamically added podcast content (debounced)", async () => {
  const p = makePage(homeDom); run(p.w, true);
  const page = p.html.querySelector('[data-testid="page"]');
  const late = new El("a", { href: "/podcasts/ZZZZZZZZZZ/YYYYYYYYYY" }); page.appendChild(late);
  p.w.fire(); p.w.fire(); assert.ok(!late.hasAttribute(A), "debounced, not immediate");
  await sleep(250); assert.ok(late.hasAttribute(A));
});

await t("never hides the player or a container with playing media", () => {
  const playing = new El("video"); playing.paused = false;
  const p = makePage(() => new El("div", { id: "root" }, [
    new El("footer", {}, [new El("a", { href: "/podcasts/AAAAAAAAAA/BBBBBBBBBB", id: "pl" })]),
    new El("div", { "data-testid": "CarouselItem", id: "card" }, [new El("a", { href: "/podcasts/CCCCCCCCCC/DDDDDDDDDD" }), playing]),
  ]));
  run(p.w, true);
  assert.equal(hidden(p.html).length, 0);
  playing.paused = true; p.w.__amzHideSections.rescan();
  assert.ok(p.html.querySelector("#card").hasAttribute(A), "hidden once not playing");
  playing.paused = false; p.w.__amzHideSections.rescan();
  assert.ok(!p.html.querySelector("#card").hasAttribute(A), "released when playback starts");
});

await t("on /podcasts pages only nav/filter entries are hidden, content stays", () => {
  const p = makePage(homeDom, { pathname: "/podcasts" }); run(p.w, true);
  const shelves = p.html.querySelectorAll('[data-testid="Shelf"]');
  assert.ok(shelves.every((s) => !s.hasAttribute(A)));
  assert.ok(p.html.querySelector('[data-testid="TopNavBar_PodcastTab"]').hasAttribute(A));
});

await t("never hides a container holding the search box or the whole page", () => {
  const p = makePage(() => new El("div", { id: "root" }, [new El("main", {}, [
    new El("h4", {}, [], "Podcasts"), new El("input", { role: "search" }),
  ])]));
  run(p.w, true);
  assert.equal(p.html.querySelector("main").hasAttribute(A), false);
  assert.equal(p.html.querySelector("#root").hasAttribute(A), false);
});

await t("odd DOM: no throw (throwing querySelectorAll, empty doc, missing MutationObserver, subframe)", () => {
  const p = makePage(homeDom, { throwing: true });
  assert.doesNotThrow(() => { run(p.w, true); p.w.__amzHideSections.setEnabled("podcasts", true); p.w.__amzHideSections.rescan(); p.w.__amzHideSections.setEnabled("podcasts", false); });
  const e = makePage(() => new El("div")); delete e.w.MutationObserver;
  assert.doesNotThrow(() => { run(e.w, true); e.w.__amzHideSections.setEnabled("podcasts", false); });
  const f = makePage(homeDom); f.w.top = {}; // subframe: not installed
  assert.doesNotThrow(() => run(f.w, true)); assert.equal(f.w.__amzHideSections, undefined);
  const g = makePage(homeDom); g.w.document = {}; // totally broken document
  assert.doesNotThrow(() => { run(g.w, true); g.w.__amzHideSections.setEnabled("podcasts", true); });
});

// Audible: nav tab is TopNavBar_AudiobooksTab; audiobook cards have opaque hrefs (docs/PODCASTS.md).
function audibleDom() {
  const h = (t) => new El("h1", { role: "heading", "aria-label": t }, [new El("h4", { role: "heading" }, [], t)]);
  const shelf = (title, hrefs) => new El("div", { "data-testid": "Shelf" }, [h(title), new El("div", {}, hrefs.map((hr) => new El("div", { "data-testid": "CarouselItem" }, [new El("a", { href: hr, role: "link" })])))]);
  return new El("div", { id: "root" }, [
    new El("header", {}, [new El("nav", {}, [
      new El("button", { "data-testid": "TopNavBar_HomeTab" }),
      new El("button", { "data-testid": "TopNavBar_AudiobooksTab", "aria-label": "Audiobook" }),
      new El("button", { "data-testid": "TopNavBar_PodcastTab", "aria-label": "Podcasts" }),
    ])]),
    new El("div", { "data-testid": "page" }, [
      shelf("Albums for You", ["/albums/AAAAAAAAAA"]),
      shelf("Only From Audible", ["/B0AAAAAAAA/CCCCCCCCCC"]),
      shelf("Podcasts for you", ["/podcasts/BBBBBBBBBB/CCCCCCCCCC"]),
      shelf("Playlists for You", ["/playlists/DDDDDDDDDD"]),
      new El("div", { "data-testid": "Mixed" }, [new El("div", { "data-testid": "CarouselItem", id: "book" }, [new El("div", { "data-testid": "ItemMetadata_Label_Audiobook" })]),
        new El("div", { "data-testid": "CarouselItem", id: "song" }, [new El("a", { href: "/albums/x" })])]),
      new El("div", { "data-testid": "Button,ButtonNavigator_Button,SearchResultsTypeFilter_Pill_audiobook" }),
      new El("div", { "data-testid": "SearchResultsWidget_Audiobook" }, [new El("h4", {}, [], "Audiobooks")]),
      new El("div", { "data-testid": "HorizontalItem,SearchResultsWidget_TopResults_AudiobookItem" }),
      new El("a", { "aria-label": "Audible", "data-testid": "SearchResultsWidget_TopResults_ArtistItem_Metadata_ArtistName", href: "/artists/ZZZZZZZZZZ" }),
    ]),
  ]);
}
const hiddenA = (root) => root.querySelectorAll("[" + AA + "]");

await t("audible: hides Audiobooks tab, pill, widget, top result, label card, Audible shelf; keeps podcasts and others", () => {
  const p = makePage(audibleDom); run(p.w); const api = p.w.__amzHideSections;
  assert.equal(api.setEnabled("audible", true), true);
  const q = (sel) => p.html.querySelectorAll(sel);
  assert.ok(q('[data-testid="TopNavBar_AudiobooksTab"]')[0].hasAttribute(AA), "tab");
  assert.ok(!q('[data-testid="TopNavBar_PodcastTab"]')[0].hasAttribute(AA) && !q('[data-testid="TopNavBar_PodcastTab"]')[0].hasAttribute(A), "podcast tab untouched");
  assert.ok(!q('[data-testid="TopNavBar_HomeTab"]')[0].hasAttribute(AA));
  assert.ok(q('[data-testid*="SearchResultsTypeFilter_Pill_audiobook"]')[0].hasAttribute(AA), "pill");
  assert.ok(q('[data-testid="SearchResultsWidget_Audiobook"]')[0].hasAttribute(AA), "widget");
  assert.ok(q('[data-testid*="TopResults_AudiobookItem"]')[0].hasAttribute(AA), "top result");
  const shelves = q('[data-testid="Shelf"]');
  assert.ok(!shelves[0].hasAttribute(AA) && shelves[1].hasAttribute(AA) && !shelves[2].hasAttribute(AA) && !shelves[3].hasAttribute(AA), "only Audible shelf");
  assert.ok(q("#book")[0].hasAttribute(AA) && !q("#song")[0].hasAttribute(AA), "audiobook card only");
  assert.ok(!q('[data-testid*="ArtistName"]')[0].hasAttribute(AA), "artist named Audible untouched");
  assert.equal(hidden(p.html).length, 0, "no podcast marks");
  assert.ok(p.doc.getElementById("amz-hide-sections-style").textContent.includes("TopNavBar_Audiobook"));
  assert.ok(!p.doc.getElementById("amz-hide-sections-style").textContent.includes("TopNavBar_Podcast"));
});

await t("toggles are independent: each restores only its own marks; style shrinks, then removed", () => {
  const p = makePage(audibleDom); run(p.w); const api = p.w.__amzHideSections;
  api.setEnabled("podcasts", true); api.setEnabled("audible", true);
  assert.ok(hidden(p.html).length > 0 && hiddenA(p.html).length > 0);
  const nA = hiddenA(p.html).length, nP = hidden(p.html).length;
  api.setEnabled("audible", false);
  assert.equal(hiddenA(p.html).length, 0); assert.equal(hidden(p.html).length, nP);
  assert.ok(!p.doc.getElementById("amz-hide-sections-style").textContent.includes("Audiobook"));
  assert.ok(p.doc.getElementById("amz-hide-sections-style").textContent.includes("Podcast"));
  api.setEnabled("audible", true); assert.equal(hiddenA(p.html).length, nA);
  api.setEnabled("podcasts", false);
  assert.equal(hidden(p.html).length, 0); assert.equal(hiddenA(p.html).length, nA);
  assert.ok(p.w.observers.some((o) => o.on), "observer still on for audible");
  api.setEnabled("audible", false);
  assert.equal(p.doc.getElementById("amz-hide-sections-style"), null); assert.ok(p.w.observers.every((o) => !o.on));
});

await t("initial flags per section; unknown section ignored", () => {
  const p = makePage(audibleDom); run(p.w, false, true); const api = p.w.__amzHideSections;
  assert.equal(api.isEnabled("audible"), true); assert.equal(api.isEnabled("podcasts"), false);
  assert.ok(hiddenA(p.html).length > 0); assert.equal(hidden(p.html).length, 0);
  assert.equal(api.setEnabled("nope", true), false);
});

await t("audible: on /audiobooks only nav/filters hidden; playing media / player never hidden", () => {
  const p = makePage(audibleDom, { pathname: "/audiobooks" }); run(p.w, false, true);
  const shelves = p.html.querySelectorAll('[data-testid="Shelf"]');
  assert.ok(shelves.every((s) => !s.hasAttribute(AA)));
  assert.ok(p.html.querySelector('[data-testid="TopNavBar_AudiobooksTab"]').hasAttribute(AA));
  const playing = new El("video"); playing.paused = false;
  const q = makePage(() => new El("div", { id: "root" }, [
    new El("footer", {}, [new El("div", { "data-testid": "SearchResultsWidget_Audiobook" })]),
    new El("div", { "data-testid": "CarouselItem", id: "c" }, [new El("div", { "data-testid": "ItemMetadata_Label_Audiobook" }), playing]),
  ]));
  run(q.w, false, true);
  assert.equal(hiddenA(q.html).length, 0);
});

// Audible: robust to a changed testid (aria-label / svg title / href) and late-rendered nav.
await t("audible: icon-only tab found via aria-label, svg title, href even with an unknown testid; late render re-hidden", async () => {
  const mk = () => new El("div", { id: "root" }, [new El("header", {}, [new El("nav", {}, [
    new El("button", { "data-testid": "TopNavBar_HomeTab", "aria-label": "Amazon Music Home" }),
    new El("button", { "data-testid": "X1", "aria-label": "Audiobook" }),
    new El("button", { "data-testid": "X2" }, [new El("svg", {}, [new El("title", {}, [], "Audible")])]),
    new El("a", { "data-testid": "X3", href: "/audible" }),
    new El("button", { "data-testid": "TopNavBar_AUDIBLETab" }),
    new El("button", { "data-testid": "TopNavBar_PodcastTab", "aria-label": "Podcasts" }),
  ])]), new El("div", {}, [new El("a", { "aria-label": "Audible", href: "/artists/ZZZZZZZZZZ" })])]);
  const p = makePage(mk); run(p.w, false, true);
  const nav = p.html.querySelectorAll("button,a");
  const byT = (t) => nav.find((e) => e.attrs["data-testid"] === t);
  for (const id of ["X1", "X2", "X3", "TopNavBar_AUDIBLETab"]) assert.ok(byT(id).hasAttribute(AA), id);
  assert.ok(!byT("TopNavBar_HomeTab").hasAttribute(AA) && !byT("TopNavBar_PodcastTab").hasAttribute(AA));
  assert.ok(!nav.find((e) => e.attrs.href === "/artists/ZZZZZZZZZZ").hasAttribute(AA), "non-nav Audible artist link untouched");
  const late = new El("button", { "aria-label": "Audiobooks" });
  p.html.querySelector("nav").appendChild(late); p.w.fire(); await sleep(250);
  assert.ok(late.hasAttribute(AA), "late-rendered nav item hidden by observer");
});

// getApp
function getAppDom() {
  return new El("div", { id: "root" }, [
    new El("header", {}, [new El("nav", {}, [new El("button", { "data-testid": "TopNavBar_HomeTab" })]),
      new El("button", { "data-testid": "Button,GetAppButton", "aria-label": "Get App" }, [], "Get App"),
      new El("button", { "data-testid": "SearchButton", "aria-label": "Search" }),
      new El("button", { "data-testid": "AccountMenu", "aria-label": "Account" })]),
    new El("div", { "data-testid": "banner" }, [new El("button", { }, [], "Get the app"), new El("a", { href: "/x" }, [], "Get the app for the best experience on all your devices today")]),
    new El("footer", {}, [new El("button", { "data-testid": "PlayerPlay", "aria-label": "Play" })]),
  ]);
}
await t("getApp: hides Get App button by testid and short localised text; player/search/account/long text untouched; restore; persists on rescan", () => {
  const p = makePage(getAppDom); run(p.w); const api = p.w.__amzHideSections;
  assert.ok(api.sections.includes("getApp"));
  assert.equal(api.setEnabled("getApp", true), true);
  const G = "data-amz-hide-getApp".toLowerCase();
  const all = p.html.querySelectorAll("button,a");
  const hid = all.filter((e) => e.hasAttribute("data-amz-hide-getApp"));
  assert.deepEqual(hid.map((e) => e.attrs["data-testid"] || e.textContent), ["Button,GetAppButton", "Get the app"]);
  assert.ok(!hid.some((e) => ["SearchButton", "AccountMenu", "PlayerPlay"].includes(e.attrs["data-testid"])));
  assert.ok(p.head.querySelector("style") || p.html.querySelector("style"), "css style present");
  assert.ok(/GetApp/.test(p.doc.getElementById("amz-hide-sections-style").textContent));
  api.setEnabled("getApp", false);
  assert.equal(p.html.querySelectorAll("[data-amz-hide-getApp]").length, 0);
  assert.equal(p.doc.getElementById("amz-hide-sections-style"), null);
  api.setEnabled("getApp", true); api.rescan();
  assert.equal(p.html.querySelectorAll("[data-amz-hide-getApp]").length, 2);
});
await t("getApp: initial flag applies at document start; independent of podcasts/audible", () => {
  const p = makePage(getAppDom); run(p.w, false, false, true); const api = p.w.__amzHideSections;
  assert.equal(api.isEnabled("getApp"), true); assert.equal(api.isEnabled("audible"), false); assert.equal(api.isEnabled("podcasts"), false);
  assert.equal(p.html.querySelectorAll("[" + AA + "]").length + p.html.querySelectorAll("[" + A + "]").length, 0);
});


// homeBanner
function bannerDom() {
  const banner = new El("div", {}, [new El("div", {}, [new El("div", { "data-testid": "BrowseHome_Top_Recommender" }, [new El("div", { "data-testid": "BrowseHome_TopRecommender_Artwork" })])])]);
  return new El("div", { "data-testid": "Page" }, [new El("div", { "data-testid": "BrowseHome_RecommendationsList" }, [
    banner,
    new El("div", {}, [new El("div", { "data-testid": "Box,WidgetHeader,Albums_for_You" }, [], "Albums for You"), new El("div", { "data-testid": "Carousel" })]),
    new El("div", { "data-testid": "NowPlayingBar" }),
  ]), new El("nav", {}, [new El("a", { "data-testid": "TopNavBar_HomeTab" })])]);
}
await t("homeBanner: hides banner wrapper chain only on home route; shelves/nav/player untouched; unhides on leaving; re-hides on return", () => {
  const p = makePage(bannerDom, { pathname: "/" }); run(p.w, false, false, false, true); const api = p.w.__amzHideSections;
  assert.ok(api.sections.includes("homeBanner")); assert.equal(api.isEnabled("homeBanner"), true);
  const H = () => p.html.querySelectorAll("[data-amz-hide-homebanner]".replace("homebanner", "homeBanner"));
  assert.equal(H().length, 1);
  assert.equal(H()[0].children[0].children[0].attrs["data-testid"], "BrowseHome_Top_Recommender"); // wrapper hidden, root inside
  assert.equal(H()[0].parentElement.attrs["data-testid"], "BrowseHome_RecommendationsList");
  assert.ok(/data-amz-hide-homeBanner/.test(p.doc.getElementById("amz-hide-sections-style").textContent));
  p.w.location.pathname = "/search"; api.rescan(); assert.equal(H().length, 0);
  p.w.location.pathname = "/home"; api.rescan(); assert.equal(H().length, 1);
  api.setEnabled("homeBanner", false); assert.equal(H().length, 0);
});
await t("homeBanner: no match on non-home route, off by default, independent, history hook schedules rescan", async () => {
  const p = makePage(bannerDom, { pathname: "/library" }); run(p.w, false, false, false, true);
  assert.equal(p.html.querySelectorAll("[data-amz-hide-homeBanner]").length, 0);
  const q = makePage(bannerDom, { pathname: "/" }); run(q.w); assert.equal(q.w.__amzHideSections.isEnabled("homeBanner"), false);
  const r = makePage(bannerDom, { pathname: "/" }); run(r.w, false, false, false, true);
  r.w.location.pathname = "/library"; r.w.history.pushState({}, "", "/library"); await sleep(250);
  assert.equal(r.html.querySelectorAll("[data-amz-hide-homeBanner]").length, 0);
  r.w.location.pathname = "/home"; r.w.history.pushState({}, "", "/home"); await sleep(250);
  assert.equal(r.html.querySelectorAll("[data-amz-hide-homeBanner]").length, 1);
});
console.log(`\n${passed} tests passed`);
