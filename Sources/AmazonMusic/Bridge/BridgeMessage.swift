import Foundation

enum BridgeMessage: Sendable, Equatable {
    struct StatePayload: Sendable, Equatable {
        var trackId: String?
        var title: String?
        var artist: String?
        var album: String?
        var artworkURL: URL?
        var duration: Double?
        var position: Double?
        var isPlaying: Bool
        /// nil = unknown / no like control (older bridge or no player bar).
        var liked: Bool? = nil
        /// nil = unknown / no shuffle control (older bridge or no player bar).
        var shuffle: Bool? = nil
        /// nil = unknown / no repeat control (older bridge, no player bar, or an unrecognised value).
        var repeatMode: RepeatMode? = nil
        /// Upcoming tracks (next first). nil/empty = no queue information (section hidden).
        var queue: [QueueItem]? = nil
        /// true = signed in, false = signed out (sign-in page / no customer), nil = unknown (older bridge or page not ready).
        var signedIn: Bool? = nil
        /// true when the page can "Play Similar Music" for the current item (music track with the "..." menu); nil = unknown (older bridge).
        var canPlaySimilar: Bool? = nil
        /// true when the page lets us start a given queue entry (Up Next rows are clickable); nil = unknown/older bridge.
        var canJumpToQueueItem: Bool? = nil
    }
    /// One upcoming track as reported by the page (parsed fields only).
    struct QueueItem: Sendable, Equatable {
        /// The queue entry's stable id (entityReferenceId; not a credential). nil if absent/invalid. Used to jump to the entry.
        var id: String? = nil
        var title: String
        var artist: String?
        var artworkURL: URL?
    }
    case ready(bridgeVersion: String?)
    case state(StatePayload)
    case position(position: Double?, duration: Double?)
    case error(code: String?, message: String?)
    case log(message: String?)
    case unknown

    static let supportedVersion = 1

    /// Never throws: malformed input yields `.unknown`.
    static func decode(_ data: Data) -> BridgeMessage {
        guard data.count <= Limits.maxMessageBytes else { return .unknown }
        return (try? JSONDecoder().decode(BridgeMessage.self, from: data)) ?? .unknown
    }

    /// Size limits applied to untrusted page messages BEFORE they are serialized/decoded.
    enum Limits {
        static let maxMessageBytes = 64 * 1024
        static let maxQueueItems = 20
        static let maxArrayCount = 20          // any other array
        static let maxStringLength = 2048      // any string (URLs); title/artist are cut shorter at decode
        static let maxTextLength = 300         // title / artist / album / trackId / message
        static let maxDepth = 5
    }

    /// Copies a JSON-like value, truncating strings and arrays (never throws, drops non-JSON values).
    static func sanitize(_ value: Any, depth: Int = 0) -> Any? {
        guard depth <= Limits.maxDepth else { return nil }
        switch value {
        case let s as String: return String(s.prefix(Limits.maxStringLength))
        case let n as NSNumber: return n
        case is NSNull: return NSNull()
        case let a as [Any]:
            return a.prefix(depth == 2 ? Limits.maxQueueItems : Limits.maxArrayCount).compactMap { sanitize($0, depth: depth + 1) }
        case let d as [String: Any]:
            var out: [String: Any] = [:]
            for (k, v) in d.prefix(64) { if let c = sanitize(v, depth: depth + 1) { out[String(k.prefix(64))] = c } }
            return out
        default: return nil
        }
    }

    /// Validates a WKScriptMessage body (Any): truncates oversized arrays/strings, then enforces a byte cap, then decodes.
    static func decode(body: Any) -> BridgeMessage {
        guard let clean = sanitize(body), JSONSerialization.isValidJSONObject(clean),
              let data = try? JSONSerialization.data(withJSONObject: clean) else { return .unknown }
        return decode(data)
    }
}

/// Repeat state of the player bar (off -> all -> one -> off is the page's click order).
enum RepeatMode: String, Sendable, Equatable, CaseIterable {
    case off, all, one
    /// Mode after one click of the page's repeat button.
    var next: RepeatMode { switch self { case .off: .all; case .all: .one; case .one: .off } }
}

extension BridgeMessage: Decodable {
    private enum Keys: String, CodingKey { case v, type, payload }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        guard let v = try? c.decode(Int.self, forKey: .v), v == Self.supportedVersion,
              let type = try? c.decode(String.self, forKey: .type) else { self = .unknown; return }
        let p = try? c.nestedContainer(keyedBy: PKeys.self, forKey: .payload)
        func num(_ k: PKeys) -> Double? {
            guard let d = try? p?.decodeIfPresent(Double.self, forKey: k), d.isFinite else { return nil }
            return d
        }
        func str(_ k: PKeys) -> String? {
            guard let s = try? p?.decodeIfPresent(String.self, forKey: k) else { return nil }
            let limit = (k == .artworkURL) ? Limits.maxStringLength : Limits.maxTextLength
            return s.count > limit ? String(s.prefix(limit)) : s
        }
        switch type {
        case "ready": self = .ready(bridgeVersion: str(.bridgeVersion))
        case "state":
            guard p != nil else { self = .unknown; return }
            let playing = (try? p?.decodeIfPresent(Bool.self, forKey: .isPlaying)) ?? false
            self = .state(StatePayload(trackId: str(.trackId), title: str(.title), artist: str(.artist),
                                       album: str(.album), artworkURL: Self.safeURL(str(.artworkURL)),
                                       duration: num(.duration), position: num(.position), isPlaying: playing,
                                       liked: (try? p?.decodeIfPresent(Bool.self, forKey: .liked)) ?? nil,
                                       shuffle: (try? p?.decodeIfPresent(Bool.self, forKey: .shuffle)) ?? nil,
                                       repeatMode: str(.repeatMode).flatMap(RepeatMode.init(rawValue:)),
                                       queue: Self.queueItems(from: c),
                                       signedIn: (try? p?.decodeIfPresent(Bool.self, forKey: .signedIn)) ?? nil,
                                       canPlaySimilar: (try? p?.decodeIfPresent(Bool.self, forKey: .canPlaySimilar)) ?? nil,
                                       canJumpToQueueItem: (try? p?.decodeIfPresent(Bool.self, forKey: .canJumpToQueueItem)) ?? nil))
        case "position": self = .position(position: num(.position), duration: num(.duration))
        case "error": self = .error(code: str(.code), message: str(.message))
        case "log": self = .log(message: str(.message))
        default: self = .unknown
        }
    }

    private struct RawQueueItem: Decodable {
        var id: String?
        var title: String?
        var artist: String?
        var artworkURL: String?
        // Lengths are capped in queueItems (after decode of an already size-limited message).
    }

    /// Lenient: a malformed queue never breaks the rest of the state message. Items without a title are dropped; capped at 20.
    private static func queueItems(from c: KeyedDecodingContainer<Keys>) -> [QueueItem]? {
        guard let p = try? c.nestedContainer(keyedBy: PKeys.self, forKey: .payload),
              let raw = try? p.decodeIfPresent([RawQueueItem].self, forKey: .queue) else { return nil }
        return raw.compactMap { r in
            guard let t = r.title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return QueueItem(id: validQueueItemID(r.id), title: String(t.prefix(Limits.maxTextLength)),
                             artist: r.artist.flatMap { $0.isEmpty ? nil : String($0.prefix(Limits.maxTextLength)) },
                             artworkURL: safeURL(r.artworkURL))
        }.prefix(Limits.maxQueueItems).map { $0 }
    }

    /// Queue entry ids are short opaque tokens (UUIDs): <= 100 chars of [A-Za-z0-9_.:-]. Anything else is dropped (row not clickable).
    static func validQueueItemID(_ s: String?) -> String? {
        guard let s, !s.isEmpty, s.count <= 100,
              s.unicodeScalars.allSatisfy({ ($0.value < 128) && (CharacterSet.alphanumerics.contains($0) || "-_.:".unicodeScalars.contains($0)) }) else { return nil }
        return s
    }

    private enum PKeys: String, CodingKey {
        case bridgeVersion, trackId, title, artist, album, artworkURL, duration, position, isPlaying, liked, shuffle, queue, signedIn, canPlaySimilar, canJumpToQueueItem, code, message
        case repeatMode = "repeat"
    }

    /// Artwork URLs from the page: only https on trusted Amazon image hosts (see `ArtworkPolicy`); anything else -> nil.
    static func safeURL(_ s: String?) -> URL? {
        guard let s, s.count <= Limits.maxStringLength, let u = URL(string: s), ArtworkPolicy.isTrusted(u) else { return nil }
        return u
    }
}

/// Which artwork URLs the app will load (the page is untrusted input). https only; exact host or dot-boundary suffix match.
enum ArtworkPolicy {
    static let trustedDomains = ["media-amazon.com", "ssl-images-amazon.com"]

    static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              var h = url.host?.lowercased(), !h.isEmpty else { return false }
        if h.hasSuffix(".") { h.removeLast() }
        return trustedDomains.contains { h == $0 || h.hasSuffix("." + $0) }
    }
}

/// Which frames may talk to the bridge: the main frame, https, on a music.amazon.* host (preset regions) or the configured start host.
enum BridgeOriginPolicy {
    static func isAllowed(isMainFrame: Bool, scheme: String?, host: String?, configuredHost: String?) -> Bool {
        guard isMainFrame, scheme?.lowercased() == "https", var h = host?.lowercased(), !h.isEmpty else { return false }
        if h.hasSuffix(".") { h.removeLast() }
        if SettingsValidation.presetHosts.contains(h) { return true }
        if let c = configuredHost?.lowercased(), !c.isEmpty, h == c,
           h.hasPrefix("music.amazon."), WebNavigationPolicy.isAmazonHost(h) { return true }
        return false
    }
}
