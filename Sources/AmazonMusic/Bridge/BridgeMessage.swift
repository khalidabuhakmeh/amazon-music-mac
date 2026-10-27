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
        (try? JSONDecoder().decode(BridgeMessage.self, from: data)) ?? .unknown
    }

    /// Validates a WKScriptMessage body (Any) via JSONSerialization.
    static func decode(body: Any) -> BridgeMessage {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return .unknown }
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
            return s
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
                                       repeatMode: str(.repeatMode).flatMap(RepeatMode.init(rawValue:))))
        case "position": self = .position(position: num(.position), duration: num(.duration))
        case "error": self = .error(code: str(.code), message: str(.message))
        case "log": self = .log(message: str(.message))
        default: self = .unknown
        }
    }

    private enum PKeys: String, CodingKey {
        case bridgeVersion, trackId, title, artist, album, artworkURL, duration, position, isPlaying, liked, shuffle, code, message
        case repeatMode = "repeat"
    }

    /// Only absolute http(s) URLs with a host are accepted; relative/missing -> nil.
    static func safeURL(_ s: String?) -> URL? {
        guard let s, let u = URL(string: s), let scheme = u.scheme?.lowercased(),
              scheme == "http" || scheme == "https", u.host != nil else { return nil }
        return u
    }
}
