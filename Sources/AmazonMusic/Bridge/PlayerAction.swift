import Foundation

/// Single source of truth for user-facing player actions (menus, URL scheme, intents, CLI, self-test).
enum PlayerAction: String, CaseIterable, Sendable {
    case play, pause, toggle, next, previous, like, shuffle
    case repeatMode = "repeat"
    case similar

    /// Static (state-independent) title; dynamic variants (Pause/Play, Like/Unlike) live in the menu models.
    var title: String {
        switch self {
        case .play: "Play"
        case .pause: "Pause"
        case .toggle: "Play/Pause"
        case .next: "Next"
        case .previous: "Previous"
        case .like: "Like"
        case .shuffle: "Shuffle"
        case .repeatMode: "Repeat"
        case .similar: "Play Similar"
        }
    }

    var systemImage: String {
        switch self {
        case .play: "play.fill"
        case .pause: "pause.fill"
        case .toggle: "playpause.fill"
        case .next: "forward.end.fill"
        case .previous: "backward.end.fill"
        case .like: "heart"
        case .shuffle: "shuffle"
        case .repeatMode: "repeat"
        case .similar: "dot.radiowaves.left.and.right"
        }
    }

    var command: PlayerCommand {
        switch self {
        case .play: .play
        case .pause: .pause
        case .toggle: .toggle
        case .next: .next
        case .previous: .previous
        case .like: .toggleLike
        case .shuffle: .toggleShuffle
        case .repeatMode: .cycleRepeat
        case .similar: .playSimilar
        }
    }

    var urlName: String { rawValue }
}
