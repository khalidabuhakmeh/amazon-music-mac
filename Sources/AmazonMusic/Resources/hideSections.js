// Amazon Music "Hide sections": hides podcast / Audible (audiobook) UI in the web page via CSS + a debounced MutationObserver.
// Sections are enabled independently: window.__amzHideSections.setEnabled('podcasts' | 'audible' | 'getApp' | 'homeBanner', bool).
// Injected at document start, main frame only. Never throws. Separate from bridge.js.
// DOM findings behind these selectors: docs/PODCASTS.md.
(function () {
  "use strict";
  const HIDE_SECTIONS_VERSION = "4.1.0";

  // The ONLY place DOM knowledge lives. Prefer data-testid / href / aria-label over class names
  // (classes are hashed react-native-web atoms and change between builds).
  // Selectors used from JS must be simple (no combinators) so they work with closest()/matches().
  const RULES = {
    attrPrefix: "data-amz-hide-", // + section id, e.g. data-amz-hide-podcasts
    styleId: "amz-hide-sections-style",
    debounceMs: 150,
    maxClimb: 14,
    cardContainers: ['[data-testid="CarouselItem"]', '[role="listitem"]', "li"],
    headingSelector: 'h1,h2,h3,h4,h5,h6,[role="heading"]',
    headingExcludeRx: /["“”„「」'‘’]/, // e.g. Search results for "podcast"
    headingMaxLen: 40,
    // Never hide these, or anything containing them / actively playing.
    protectedSelectors: ["footer", '[role="contentinfo"]', '[data-testid*="Player"]', '[data-testid*="NowPlaying"]'],
    neverHide: ["html", "body", "main", "#root", '[role="main"]', "header", "nav"],
    stopIfContains: "input,textarea", // never hide a container holding the search box
    mediaSelector: "audio,video",
    controlSelector: 'button,a,[role="button"],[role="link"]',
    navScopeSelector: '[data-testid^="TopNavBar"],header,nav,[role="navigation"],[role="banner"]',
    controlTextMaxLen: 20,
    sections: {
      podcasts: {
        // Hidden directly (also by pre-hydration CSS), on every page.
        direct: [
          '[data-testid*="TopNavBar_Podcast"]', // top nav "Podcasts" tab
          '[data-testid*="SearchResultsTypeFilter_Pill_podcast"]', // search filter pills (podcast, podcastEpisode)
          '[data-testid*="SearchResultsWidget_Podcast"]', // search result shelves (PodcastShow / PodcastEpisode)
        ],
        // Hidden directly but not on the section's own pages (keepContentPathRx).
        contentDirect: [],
        // Elements whose closest matching ancestor (cardContainers) is hidden, else the element itself.
        cards: [
          '[data-testid*="TopResults_Podcast"]', // podcast item inside "Top Results"
          'a[href^="/podcasts"]', // podcast show/episode links (nav, shelves, cards)
          'a[href^="/podcast/"]',
          'a[href*="/podcasts/"]',
        ],
        // Pre-hydration CSS only (may use :has; each rule is emitted separately so an unsupported one is dropped alone).
        cssOnly: ['[data-testid="CarouselItem"]:has([data-testid*="TopResults_Podcast"])'],
        // Shelves by heading text. Localised variants for the region presets (en/de/fr/es/it/pt/ja).
        headingTextRx: /(^|\s)(podcasts?|podcasten|podcast-shows?)(\s|$)|ポッドキャスト/i,
        // On the user's own podcast pages only the nav/filter entries are hidden, not the page content.
        keepContentPathRx: /^\/podcasts?(\/|$)/,
      },
      audible: {
        // The top nav tab is testid TopNavBar_AudiobooksTab (aria-label "Audiobook"); Audible is the audiobook service.
        direct: [
          '[data-testid*="TopNavBar_Audiobook" i]', // top nav tab (icon-only Audible-logo button, aria "Audiobook")
          '[data-testid*="TopNavBar_Audible" i]',
          '[data-testid*="SearchResultsTypeFilter_Pill_audiobook"]', // search filter pill
          '[data-testid*="SearchResultsWidget_Audiobook"]', // search result shelf
        ],
        // Audiobook browse page roots (hero, shovelers: testid "audiobook-...").
        contentDirect: ['[data-testid^="audiobook-browse"]', '[data-testid^="audiobook-editorial"]'],
        // Audiobook cards link to opaque /<id>/<id> paths, so they are only recognised by testid / shelf heading.
        cards: ['[data-testid*="TopResults_Audiobook"]', '[data-testid*="ItemMetadata_Label_Audiobook"]'],
        cssOnly: ['[data-testid="CarouselItem"]:has([data-testid*="TopResults_Audiobook"])'],
        headingTextRx: /(^|\s)(audible|audiobooks?|hörbücher|hörbuch|livres? audio|audiolibros?|audiolibri|audiolivros?)(\s|$)|オーディオブック/i,
        keepContentPathRx: /^\/audiobooks?(\/|$)/,
        // Nav controls recognised by aria-label / short text / svg title / href (robust if the testid changes).
        controlScope: "nav",
        controlLabelRx: /^(audible|audiobooks?|hörbücher|hörbuch|livres? audio|audiolibros?|audiolibri|audiolivros?|オーディオブック)$/i,
        controlHrefRx: /^(https?:\/\/[^/]*)?\/(audible|audiobooks?)(\/|\?|#|$)/i,
      },
      getApp: {
        // Header button "Get App": testid is literally "Button,GetAppButton" (aria-label "Get App", no svg). Never hides player/search/account.
        direct: ['[data-testid*="GetApp" i]', '[data-testid*="DownloadApp" i]', '[data-testid*="InstallApp" i]'],
        contentDirect: [],
        cards: [],
        cssOnly: [],
        headingTextRx: null,
        keepContentPathRx: null,
        controlScope: "any",
        controlLabelRx: /^(get app|get the app|download app|download the app|app holen|app herunterladen|obtenir l['’]app(lication)?|télécharger l['’]app(lication)?|obtener la app|descargar la app|scarica l['’]app|ottieni l['’]app|obter o app|baixar o app|アプリを入手|アプリをダウンロード)$/i,
        controlHrefRx: null,
      },
      homeBanner: {
        // Home page hero/promo banner (shows podcasts / ads). Only on the home route; see docs/PODCASTS.md.
        // Roots are hidden together with their single-child wrapper chain so no padding/gap is left.
        direct: [],
        contentDirect: [],
        cards: [],
        cssOnly: [],
        headingTextRx: null,
        keepContentPathRx: null,
        routeRx: /^\/(home)?\/?$/,
        bannerRoots: ['[data-testid="BrowseHome_Top_Recommender"]'],
      },
    },
  };
  const IDS = Object.keys(RULES.sections);

  try {
    if (window.top !== window) return;
    if (window.__amzHideSections && window.__amzHideSections.version) return; // idempotent
  } catch (e) { return; }

  const state = { enabled: {}, observer: null, timer: null };
  IDS.forEach((id) => { state.enabled[id] = false; });

  function safe(fn, fallback) { try { const r = fn(); return r === undefined ? fallback : r; } catch (e) { return fallback; } }
  function all(root, sel) { return safe(() => Array.from((root || document).querySelectorAll(sel)), []); }
  function matchesAny(el, sels) { return sels.some((s) => safe(() => el.matches(s), false)); }
  function isNever(el) { return !el || matchesAny(el, RULES.neverHide); }
  function attrOf(id) { return RULES.attrPrefix + id; }
  function anyEnabled() { return IDS.some((id) => state.enabled[id]); }

  function isPlayingMedia(el) {
    return all(el, RULES.mediaSelector).some((m) => safe(() => !m.paused && !m.ended, false));
  }
  // True if el is part of the player UI, contains it, or contains actively playing media.
  function isProtected(el) {
    return safe(() => {
      const prot = RULES.protectedSelectors.join(",");
      return !!(el.closest(prot) || el.querySelector(prot) || isPlayingMedia(el));
    }, false);
  }
  function onKeepContentPage(sec) { return safe(() => !!sec.keepContentPathRx && sec.keepContentPathRx.test(location.pathname || ""), false); }

  function mark(el, id) {
    safe(() => {
      if (!el || isNever(el) || el.hasAttribute(attrOf(id)) || isProtected(el)) return;
      el.setAttribute(attrOf(id), "1");
    });
  }

  function cardTarget(el) {
    return safe(() => {
      for (const s of RULES.cardContainers) {
        const c = el.closest(s);
        if (c && !isNever(c) && !c.querySelector(RULES.stopIfContains)) return c;
      }
      return el;
    }, el);
  }

  function leafHeadings(root) {
    return all(root, RULES.headingSelector).filter((h) => !safe(() => h.querySelector(RULES.headingSelector), null));
  }
  function headingText(h) {
    return safe(() => String(h.getAttribute("aria-label") || h.textContent || "").trim(), "");
  }
  // Climb from a heading while the parent still holds exactly that one heading (i.e. it is one shelf).
  function shelfFor(h) {
    let cur = h;
    for (let i = 0; i < RULES.maxClimb; i++) {
      const p = cur.parentElement;
      if (!p || isNever(p) || safe(() => p.querySelector(RULES.stopIfContains), null)) break;
      if (leafHeadings(p).length !== 1) break;
      cur = p;
    }
    return cur;
  }

  function svgText(el) {
    return safe(() => Array.from(el.querySelectorAll("svg")).map((v) =>
      String(v.getAttribute("aria-label") || "") + " " + String((v.querySelector("title") || {}).textContent || "")).join(" ").trim(), "");
  }
  // Controls matched by aria-label / short own text / svg title / href. Only the control itself is hidden.
  function scanControls(id, sec) {
    if (!sec.controlLabelRx && !sec.controlHrefRx) return;
    all(document, RULES.controlSelector).forEach((el) => {
      safe(() => {
        if (sec.controlScope === "nav" && !el.closest(RULES.navScopeSelector)) return;
        const texts = [el.getAttribute("aria-label"), el.getAttribute("title"), svgText(el)];
        const own = String(el.textContent || "").trim();
        if (own.length <= RULES.controlTextMaxLen) texts.push(own);
        const labelHit = sec.controlLabelRx && texts.some((t) => t && sec.controlLabelRx.test(String(t).trim()));
        const href = el.getAttribute("href");
        const hrefHit = sec.controlHrefRx && href && sec.controlHrefRx.test(href);
        if (labelHit || hrefHit) mark(el, id);
      });
    });
  }

  function onRoute(sec) { return !sec.routeRx || safe(() => sec.routeRx.test(location.pathname || ""), false); }
  // Climb while the parent has exactly this one element child (pure wrapper), stopping before the shared list.
  function wrapperTop(el) {
    let cur = el;
    for (let i = 0; i < RULES.maxClimb; i++) {
      const p = cur.parentElement;
      if (!p || isNever(p) || p.children.length !== 1 || safe(() => p.querySelector(RULES.stopIfContains), null)) break;
      cur = p;
    }
    return cur;
  }

  function scanSection(id) {
    const sec = RULES.sections[id];
    const attr = attrOf(id);
    if (!onRoute(sec)) { restore(id); return; } // left the route (SPA navigation): unhide
    // Release anything that became protected (e.g. user started playing from a hidden shelf).
    all(document, "[" + attr + "]").forEach((el) => {
      if (isProtected(el)) safe(() => el.removeAttribute(attr));
    });
    sec.direct.forEach((s) => all(document, s).forEach((el) => mark(el, id)));
    scanControls(id, sec);
    if (onKeepContentPage(sec)) return;
    sec.contentDirect.forEach((s) => all(document, s).forEach((el) => mark(el, id)));
    (sec.bannerRoots || []).forEach((s) => all(document, s).forEach((el) => mark(wrapperTop(el), id)));
    sec.cards.forEach((s) => all(document, s).forEach((el) => {
      // Nav/filter items are already handled; links inside protected UI are skipped by mark().
      mark(cardTarget(el), id);
    }));
    leafHeadings(document).forEach((h) => {
      const t = headingText(h);
      if (sec.headingTextRx && t && t.length <= RULES.headingMaxLen && !RULES.headingExcludeRx.test(t) && sec.headingTextRx.test(t)) {
        mark(shelfFor(h), id);
      }
    });
    hideEmptiedShelves(id);
  }

  // A shelf whose cards were ALL hidden (e.g. "True Crime Editor's Picks" on Home holding only podcasts) would remain as
  // an empty heading + "See More" row, so the whole shelf is hidden too. Mixed shelves (some visible cards) are kept.
  function isHiddenByAny(el) {
    return IDS.some((sid) => {
      const a = "[" + attrOf(sid) + "]";
      return safe(() => el.matches(a) || !!el.closest(a) || !!el.querySelector(a), false);
    });
  }
  function shelfCards(shelf) {
    for (const s of RULES.cardContainers) {
      const found = all(shelf, s).filter((c) => !safe(() => c.parentElement && c.parentElement.closest(s) && shelf.contains(c.parentElement.closest(s)), false));
      if (found.length) return found;
    }
    return [];
  }
  function hideEmptiedShelves(id) {
    const own = "[" + attrOf(id) + "]";
    leafHeadings(document).forEach((h) => safe(() => {
      const shelf = shelfFor(h);
      if (!shelf || shelf === h || shelf.hasAttribute(attrOf(id))) return;
      const cards = shelfCards(shelf);
      if (!cards.length || !cards.every(isHiddenByAny)) return;
      // Attribute the shelf to this section only if it hid at least one of the cards (so disabling it restores the shelf).
      if (!cards.some((c) => safe(() => c.matches(own) || !!c.closest(own) || !!c.querySelector(own), false))) return;
      mark(shelf, id);
    }));
  }

  function scan() {
    if (!anyEnabled()) return;
    safe(ensureStyle);
    IDS.forEach((id) => { if (state.enabled[id]) safe(() => scanSection(id)); });
  }

  function schedule() {
    safe(() => {
      if (state.timer) return;
      state.timer = window.setTimeout(() => { state.timer = null; scan(); }, RULES.debounceMs);
    });
  }

  function cssText() {
    const hide = "{display:none !important}";
    const sels = [];
    IDS.forEach((id) => {
      if (!state.enabled[id]) return;
      const sec = RULES.sections[id];
      sels.push("[" + attrOf(id) + "]");
      sec.direct.forEach((s) => sels.push(s));
      sec.cssOnly.forEach((s) => sels.push(s));
    });
    return sels.map((s) => s + hide).join("\n");
  }
  // (Re)writes the style for the currently enabled sections.
  function ensureStyle() {
    const css = cssText();
    const existing = document.getElementById(RULES.styleId);
    if (existing && existing.isConnected !== false) {
      if (existing.textContent !== css) existing.textContent = css;
      return;
    }
    const st = document.createElement("style");
    st.id = RULES.styleId;
    st.textContent = css;
    (document.head || document.documentElement).appendChild(st);
  }
  function removeStyle() {
    safe(() => { const st = document.getElementById(RULES.styleId); if (st && st.parentNode) st.parentNode.removeChild(st); });
  }
  function restore(id) {
    all(document, "[" + attrOf(id) + "]").forEach((el) => safe(() => el.removeAttribute(attrOf(id))));
  }

  function startObserver() {
    safe(() => {
      if (state.observer || typeof MutationObserver !== "function") return;
      const root = document.documentElement || document;
      state.observer = new MutationObserver(schedule);
      state.observer.observe(root, { childList: true, subtree: true });
    });
  }
  function stopObserver() {
    safe(() => { if (state.observer) state.observer.disconnect(); });
    state.observer = null;
    safe(() => { if (state.timer) window.clearTimeout(state.timer); });
    state.timer = null;
  }

  function setEnabled(id, on) {
    safe(() => {
      if (!RULES.sections[id]) return;
      on = !!on;
      if (on === state.enabled[id] && (!on || state.observer)) { if (on) scan(); return; }
      state.enabled[id] = on;
      if (!on) restore(id);
      if (anyEnabled()) { safe(ensureStyle); startObserver(); scan(); }
      else { stopObserver(); removeStyle(); }
    });
    return !!state.enabled[id];
  }

  window.__amzHideSections = {
    version: HIDE_SECTIONS_VERSION,
    sections: IDS.slice(),
    setEnabled: setEnabled,
    isEnabled: (id) => !!state.enabled[id],
    rescan: () => { scan(); return anyEnabled(); },
  };

  // Initial flags injected by the Swift side as a prefix to this script: {podcasts, audible, getApp, homeBanner: bool}.
  safe(() => {
    const init = window.__amzHideSectionsInitial || {};
    IDS.forEach((id) => { if (init[id] === true) setEnabled(id, true); });
  });
  // SPA route changes: re-scan (unhides when leaving the home route, hides on return).
  safe(() => {
    ["pushState", "replaceState"].forEach((m) => {
      const h = window.history; const orig = h && h[m];
      if (typeof orig !== "function") return;
      h[m] = function () { const r = orig.apply(this, arguments); schedule(); return r; };
    });
    if (window.addEventListener) { window.addEventListener("popstate", schedule); window.addEventListener("hashchange", schedule); }
  });
  // At document start the DOM is empty: scan again once it is parsed.
  safe(() => { document.addEventListener("DOMContentLoaded", () => { if (anyEnabled()) scan(); }); });
})();
