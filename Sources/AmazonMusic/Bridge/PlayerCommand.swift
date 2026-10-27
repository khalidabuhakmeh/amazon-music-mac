import Foundation

enum PlayerCommand: Sendable, Equatable {
    case play, pause, toggle, next, previous
    case seek(Double)
    case toggleLike
    case toggleShuffle, cycleRepeat

    /// Async function body (awaits the command, returns a JSON string), or nil if arguments are invalid.
    var asyncBody: String? { script.map { "return JSON.stringify(await \($0));" } }

    /// JS expression, or nil if arguments are invalid (e.g. non-finite seek).
    var script: String? {
        switch self {
        case .play: "window.__amzBridge.play()"
        case .pause: "window.__amzBridge.pause()"
        case .toggle: "window.__amzBridge.toggle()"
        case .next: "window.__amzBridge.next()"
        case .previous: "window.__amzBridge.previous()"
        case .toggleLike: "window.__amzBridge.toggleLike()"
        case .toggleShuffle: "window.__amzBridge.toggleShuffle()"
        case .cycleRepeat: "window.__amzBridge.cycleRepeat()"
        case .seek(let s):
            s.isFinite ? "window.__amzBridge.seek(\(max(0, s)))" : nil
        }
    }
}

/// Outcome of a bridge command, decoded from the page's `{ok, via?, reason?, changed?}` JSON.
struct CommandResult: Sendable, Equatable {
    var ok: Bool
    var via: String?
    var reason: String?
    var changed: Bool?

    static func failure(_ reason: String) -> CommandResult { .init(ok: false, via: nil, reason: reason, changed: nil) }

    /// Decodes the JSON string returned by the page; anything unexpected is a failure (never a silent success).
    static func parse(_ value: Any?) -> CommandResult {
        guard let s = value as? String, let data = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure("unparseable_result")
        }
        return .init(ok: o["ok"] as? Bool ?? false, via: o["via"] as? String,
                     reason: o["reason"] as? String, changed: o["changed"] as? Bool)
    }
}
