// Theme helper: injects/removes one <style> (id amz-theme-style) in the document and every shadow root.
// window.__amzTheme.set(css|null, scheme). Injected at document start, main frame. Never throws.
// All DOM knowledge lives in the theme CSS files; this file only plumbs CSS in.
(function () {
  "use strict";
  if (window.__amzTheme) return;
  const ID = "amz-theme-style";
  let css = null, scheme = "dark";
  const roots = new Set(); // shadow roots seen (weak-ish: pruned when disconnected)

  function applyTo(root) {
    try {
      const host = root === document ? document.head || document.documentElement : root;
      if (!host) return;
      let el = root === document ? document.getElementById(ID) : root.querySelector("#" + ID);
      if (css == null) { if (el) el.remove(); return; }
      if (!el) { el = document.createElement("style"); el.id = ID; host.appendChild(el); }
      if (el.textContent !== css) el.textContent = css;
    } catch (e) {}
  }
  function applyAll() {
    applyTo(document);
    for (const r of Array.from(roots)) { if (!r.host || !r.host.isConnected) roots.delete(r); else applyTo(r); }
    try {
      const de = document.documentElement;
      if (de) {
        if (css == null) { de.removeAttribute("data-amz-theme"); de.style.removeProperty("color-scheme"); }
        else { de.setAttribute("data-amz-theme", scheme); de.style.setProperty("color-scheme", scheme); }
      }
    } catch (e) {}
  }
  // Catch shadow roots (open or closed) as they are created.
  try {
    const orig = Element.prototype.attachShadow;
    Element.prototype.attachShadow = function (init) {
      const r = orig.call(this, init);
      try { roots.add(r); if (css != null) applyTo(r); } catch (e) {}
      return r;
    };
  } catch (e) {}
  // <head> / <html> may not exist yet at document start: re-apply when they appear.
  const mo = new MutationObserver(function () {
    if (css != null && !document.getElementById(ID)) applyAll();
  });
  try { mo.observe(document, { childList: true, subtree: true }); } catch (e) {}
  window.__amzTheme = {
    version: "1.0.0",
    set: function (c, s) { css = c; scheme = s || "dark"; applyAll(); },
    state: function () { return { active: css != null, scheme: scheme, roots: roots.size, styleNodes: document.querySelectorAll("#" + ID).length }; }
  };
})();
