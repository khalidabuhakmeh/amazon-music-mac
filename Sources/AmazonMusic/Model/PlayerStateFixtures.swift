import Foundation

/// Canned player states shared by `#Preview`s, `--snapshot` and `--selftest`. Never touches the network:
/// artwork URLs are nil, so views show their local SF Symbol placeholder.
@MainActor
enum PlayerStateFixtures: String, CaseIterable {
    case playing, paused, liked, likedUnknownLongTitle, shuffleRepeatAll, repeatOne
    case upNextCollapsed, upNextExpanded, noTrack, bridgeUnhealthy

    static let longTitle = "A Fairly Long Track Title That Wraps To Two Lines"

    /// Up Next expansion to force when rendering this fixture (nil = leave to the user's stored preference).
    var upNextExpanded: Bool? {
        switch self {
        case .upNextExpanded: true
        default: false
        }
    }

    func make() -> (PlayerState, PlayerBridge) {
        switch self {
        case .playing: Self.model(playing: true)
        case .paused: Self.model(playing: false, liked: false, shuffle: false, repeatMode: .off)
        case .liked: Self.model(playing: true, liked: true)
        case .likedUnknownLongTitle: Self.model(playing: true, liked: nil)
        case .shuffleRepeatAll: Self.model(playing: true, liked: false, shuffle: true, repeatMode: .all)
        case .repeatOne: Self.model(playing: true, liked: true, shuffle: false, repeatMode: .one, title: "Short Title")
        case .upNextCollapsed: Self.model(playing: true, liked: false, shuffle: false, repeatMode: .off, queue: Self.queue(3))
        case .upNextExpanded: Self.model(playing: true, liked: false, shuffle: false, repeatMode: .off, queue: Self.queue(10))
        case .noTrack:
            Self.finish({ _ in })
        case .bridgeUnhealthy:
            Self.finish { $0.markUnhealthy("Bridge did not report ready") }
        }
    }

    static func queue(_ n: Int) -> [BridgeMessage.QueueItem] {
        (1...n).map { .init(id: "q\($0)", title: "Upcoming song \($0)", artist: "Artist \($0)", artworkURL: nil) }
    }

    private static func finish(_ configure: (PlayerState) -> Void) -> (PlayerState, PlayerBridge) {
        let s = PlayerState()
        configure(s)
        return (s, PlayerBridge(state: s))
    }

    static func model(playing: Bool, liked: Bool? = nil, shuffle: Bool? = nil, repeatMode: RepeatMode? = nil,
                      title: String = longTitle, queue: [BridgeMessage.QueueItem]? = nil) -> (PlayerState, PlayerBridge) {
        finish { s in
            s.apply(.state(.init(trackId: "t1", title: title, artist: "Some Artist", album: "Album", artworkURL: nil,
                                 duration: 245, position: 83, isPlaying: playing, liked: liked, shuffle: shuffle,
                                 repeatMode: repeatMode, queue: queue, signedIn: true, canPlaySimilar: true,
                                 canJumpToQueueItem: queue == nil ? nil : true)))
        }
    }
}
