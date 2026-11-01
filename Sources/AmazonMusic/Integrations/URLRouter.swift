import Foundation
import OSLog

/// Pure, strict validation of externally supplied URLs (`amazonmusic://…` and `https://music.amazon.com/…`).
/// Anything that doesn't match exactly is rejected (nil). Contents are never interpolated into JS and
/// rejections are logged by reason code only, never echoing the URL.
enum URLRouter {
    enum Route: Equatable, Sendable {
        case action(PlayerAction)
        case open(path: String)
    }

    struct Reason: Error { let code: String; init(_ c: String) { code = c } }

    static let scheme = "amazonmusic"
    static let allowedHost = "music.amazon.com"
    static let maxPathLength = 512
    private static let log = Logger(subsystem: "com.khalidabuhakmeh.amazonmusic", category: "urlrouter")

    static func route(_ url: URL) -> Route? {
        switch evaluate(url) {
        case .success(let r): return r
        case .failure(let reason):
            log.notice("rejected url: \(reason.code, privacy: .public)")
            return nil
        }
    }

    private static func evaluate(_ url: URL) -> Result<Route, Reason> {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return .failure(Reason("unparseable")) }
        guard c.user == nil, c.password == nil, c.port == nil else { return .failure(Reason("authority")) }
        switch c.scheme?.lowercased() {
        case scheme: return evaluateCustom(c)
        case "https": return evaluateHTTPS(c)
        default: return .failure(Reason("scheme"))
        }
    }

    private static func evaluateCustom(_ c: URLComponents) -> Result<Route, Reason> {
        guard c.fragment == nil else { return .failure(Reason("fragment")) }
        guard let host = c.host?.lowercased(), !host.isEmpty else { return .failure(Reason("host")) }
        if host == "open" {
            guard c.path.isEmpty || c.path == "/" else { return .failure(Reason("extra-path")) }
            let items = (c.queryItems ?? []).filter { $0.name == "path" }
            guard items.count == 1, let raw = items[0].value else { return .failure(Reason("open-missing-path")) }
            guard let path = validate(path: raw) else { return .failure(Reason("open-bad-path")) }
            return .success(.open(path: path))
        }
        guard let action = PlayerAction.allCases.first(where: { $0.urlName == host }) else { return .failure(Reason("unknown-host")) }
        guard c.path.isEmpty || c.path == "/", c.query == nil else { return .failure(Reason("extra-path")) }
        return .success(.action(action))
    }

    private static func evaluateHTTPS(_ c: URLComponents) -> Result<Route, Reason> {
        guard c.host?.lowercased() == allowedHost else { return .failure(Reason("https-host")) }
        guard c.fragment == nil else { return .failure(Reason("fragment")) }
        var path = c.percentEncodedPath
        if path.isEmpty { path = "/" }
        if let q = c.percentEncodedQuery { path += "?" + q }
        guard let valid = validate(path: path) else { return .failure(Reason("https-bad-path")) }
        return .success(.open(path: valid))
    }

    /// Returns the path (with optional query) if it is safe to append to https://music.amazon.com.
    static func validate(path raw: String) -> String? {
        guard !raw.isEmpty, raw.count <= maxPathLength, raw.hasPrefix("/") else { return nil }
        // Decode repeatedly (up to a fixed depth) and re-check every layer, so double-encoded variants can't slip through.
        var layer = raw
        for _ in 0..<4 {
            guard isSafeLayer(layer) else { return nil }
            guard let next = layer.removingPercentEncoding else { return nil }
            if next == layer { break }
            layer = next
        }
        guard isSafeLayer(layer), layer.removingPercentEncoding == layer else { return nil } // still encoded after 4 passes → reject
        // Raw text must only use URL path/query charset.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,;=:@/%?")
        guard raw.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard let url = URL(string: "https://" + allowedHost + raw),
              url.scheme == "https", url.host == allowedHost, url.user == nil, url.port == nil,
              WebNavigationPolicy.shouldLoadInApp(url) else { return nil }
        return raw
    }

    private static func isSafeLayer(_ s: String) -> Bool {
        guard s.hasPrefix("/"), !s.hasPrefix("//") else { return false }
        for u in s.unicodeScalars where u.value < 0x20 || u.value == 0x7F || u == "\\" { return false }
        if s.contains("//") || s.contains("\\") { return false }
        let pathPart = s.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? s
        if pathPart.split(separator: "/", omittingEmptySubsequences: false).contains("..") { return false }
        if s.contains("..") { return false }
        // No scheme smuggling: a ':' before the first '/' can't occur given the leading '/', but reject "://" anywhere.
        if s.contains("://") { return false }
        return true
    }
}
