import Foundation

/// Pure helpers that build the JavaScript for hideSections.js (sections: podcasts, audible, getApp, homeBanner).
enum HideSectionsScript {
    /// Prefixes the script with the initial per-section flags it reads at document start.
    static func source(base: String, podcasts: Bool, audible: Bool, getApp: Bool, homeBanner: Bool) -> String {
        "window.__amzHideSectionsInitial = {podcasts: \(podcasts), audible: \(audible), getApp: \(getApp), homeBanner: \(homeBanner)};\n" + base
    }

    /// Call for an already-loaded page. Never throws in the page; no-op if the script isn't present.
    static func applyCall(podcasts: Bool, audible: Bool, getApp: Bool, homeBanner: Bool) -> String {
        "try { var s = window.__amzHideSections; if (s) { s.setEnabled('podcasts', \(podcasts)); s.setEnabled('audible', \(audible)); s.setEnabled('getApp', \(getApp)); s.setEnabled('homeBanner', \(homeBanner)); } } catch (e) {}"
    }
}
