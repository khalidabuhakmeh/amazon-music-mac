import Foundation
import Observation

/// UserDefaults-backed settings. Task 11 extends this with UI.
@MainActor @Observable
final class AppSettings {
    static let defaultStartURL = "https://music.amazon.com"

    @ObservationIgnored private let defaults: UserDefaults

    var startURL: String { didSet { defaults.set(startURL, forKey: "startURL") } }
    /// nil => Safari UA derived at runtime.
    var customUserAgent: String? {
        didSet {
            if let v = customUserAgent { defaults.set(v, forKey: "customUserAgent") }
            else { defaults.removeObject(forKey: "customUserAgent") }
        }
    }
    var showMenuBar: Bool { didSet { defaults.set(showMenuBar, forKey: "showMenuBar") } }
    var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: "notificationsEnabled") } }
    var notifyWhenFrontmost: Bool { didSet { defaults.set(notifyWhenFrontmost, forKey: "notifyWhenFrontmost") } }
    /// Hides podcast UI in the web page (hideSections.js, section "podcasts"). Applied live by WebController.
    var hidePodcasts: Bool { didSet { defaults.set(hidePodcasts, forKey: Self.hidePodcastsKey) } }
    static let hidePodcastsKey = "hidePodcasts"
    /// Hides Audible / audiobook UI (hideSections.js, section "audible"). Independent of hidePodcasts. Default true if the user never set it.
    var hideAudible: Bool { didSet { defaults.set(hideAudible, forKey: Self.hideAudibleKey) } }
    static let hideAudibleKey = "hideAudible"
    /// Hides the header "Get App" promo button (hideSections.js, section "getApp"). Default true when never set.
    var hideGetApp: Bool { didSet { defaults.set(hideGetApp, forKey: Self.hideGetAppKey) } }
    static let hideGetAppKey = "hideGetApp"
    /// Hides the Home page hero banner (hideSections.js, section "homeBanner"). Default true when never set.
    var hideHomeBanner: Bool { didSet { defaults.set(hideHomeBanner, forKey: Self.hideHomeBannerKey) } }
    static let hideHomeBannerKey = "hideHomeBanner"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        startURL = defaults.string(forKey: "startURL") ?? Self.defaultStartURL
        customUserAgent = defaults.string(forKey: "customUserAgent")
        showMenuBar = defaults.object(forKey: "showMenuBar") as? Bool ?? true
        notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? false
        notifyWhenFrontmost = defaults.object(forKey: "notifyWhenFrontmost") as? Bool ?? false
        hidePodcasts = defaults.object(forKey: Self.hidePodcastsKey) as? Bool ?? false
        hideAudible = defaults.object(forKey: Self.hideAudibleKey) as? Bool ?? true // default ON only if never set
        hideGetApp = defaults.object(forKey: Self.hideGetAppKey) as? Bool ?? true
        hideHomeBanner = defaults.object(forKey: Self.hideHomeBannerKey) as? Bool ?? true
    }
}

/// Pure validation for user-entered settings.
enum SettingsValidation {
    enum URLError: Error, Equatable, LocalizedError {
        case empty, notAURL, notHTTPS, notAmazonHost
        var errorDescription: String? {
            switch self {
            case .empty: "Enter a URL."
            case .notAURL: "That doesn't look like a valid URL."
            case .notHTTPS: "The URL must start with https://."
            case .notAmazonHost: "The host must be an Amazon domain."
            }
        }
    }

    static let presetHosts = ["music.amazon.com", "music.amazon.co.uk", "music.amazon.de", "music.amazon.co.jp",
                              "music.amazon.fr", "music.amazon.in", "music.amazon.com.au", "music.amazon.ca",
                              "music.amazon.es", "music.amazon.it", "music.amazon.com.br", "music.amazon.com.mx"]

    /// Accepts https URLs on an Amazon host. A bare host (e.g. "music.amazon.de") is treated as https.
    static func validateStartURL(_ input: String) -> Result<URL, URLError> {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return .failure(.empty) }
        let full = t.contains("://") ? t : "https://" + t
        guard let c = URLComponents(string: full), let url = c.url, c.host != nil else { return .failure(.notAURL) }
        guard c.scheme?.lowercased() == "https" else { return .failure(.notHTTPS) }
        guard WebNavigationPolicy.isAmazonHost(c.host) else { return .failure(.notAmazonHost) }
        return .success(url)
    }

    /// Preset host for a stored start URL, if it is exactly a preset root.
    static func presetHost(for startURL: String) -> String? {
        guard let c = URLComponents(string: startURL), let h = c.host?.lowercased(), presetHosts.contains(h),
              c.path.isEmpty || c.path == "/" else { return nil }
        return h
    }
}
