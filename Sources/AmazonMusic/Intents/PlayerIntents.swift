import AppIntents

// Titles are literals identical to PlayerAction.title (asserted in SelfTest).
struct PlayPauseIntent: AppIntent {
    static let title: LocalizedStringResource = "Play/Pause"
    static let description = IntentDescription("Toggles playback in Amazon Music.")
    static let openAppWhenRun = false
    @Dependency private var bridge: PlayerBridge
    @MainActor func perform() async throws -> some IntentResult {
        try await IntentSupport.send(.toggle, bridge: bridge); return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Next"
    static let description = IntentDescription("Skips to the next track.")
    static let openAppWhenRun = false
    @Dependency private var bridge: PlayerBridge
    @MainActor func perform() async throws -> some IntentResult {
        try await IntentSupport.send(.next, bridge: bridge); return .result()
    }
}

struct PreviousTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Previous"
    static let description = IntentDescription("Goes back to the previous track.")
    static let openAppWhenRun = false
    @Dependency private var bridge: PlayerBridge
    @MainActor func perform() async throws -> some IntentResult {
        try await IntentSupport.send(.previous, bridge: bridge); return .result()
    }
}

struct LikeTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Like"
    static let description = IntentDescription("Likes or unlikes the current track.")
    static let openAppWhenRun = false
    @Dependency private var bridge: PlayerBridge
    @MainActor func perform() async throws -> some IntentResult {
        try await IntentSupport.send(.like, bridge: bridge); return .result()
    }
}

struct PlaySimilarIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Similar"
    static let description = IntentDescription("Starts a station based on the current track.")
    static let openAppWhenRun = false
    @Dependency private var bridge: PlayerBridge
    @MainActor func perform() async throws -> some IntentResult {
        try await IntentSupport.send(.similar, bridge: bridge); return .result()
    }
}

struct NowPlayingIntent: AppIntent {
    static let title: LocalizedStringResource = "Now Playing"
    static let description = IntentDescription("Returns the current track and artist.")
    static let openAppWhenRun = false
    @Dependency private var player: PlayerState
    @Dependency private var bridge: PlayerBridge

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        try? await IntentSupport.waitUntilReady(bridge, timeout: .seconds(10))
        let text = Self.describe(player.track)
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }

    static func describe(_ t: TrackInfo?) -> String {
        guard let t, let title = t.title, !title.isEmpty else { return "Nothing playing" }
        if let a = t.artist, !a.isEmpty { return "\(title) — \(a)" }
        return title
    }
}
