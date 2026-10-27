import AppKit
import MediaPlayer
import Observation
import OSLog

// A/B TEST PROCEDURE (WebKit may publish its own Now Playing entry; no public API disables it):
//   Override (default):          open the app normally.
//   Rely+augment:                launch with env AMAZONMUSIC_NOWPLAYING=rely, e.g.
//     AMAZONMUSIC_NOWPLAYING=rely build/Build/Products/Debug/AmazonMusic.app/Contents/MacOS/AmazonMusic
//   In each mode, play a track and check: F7/F8/F9, Control Center entries (should be one),
//   AirPods. See docs/MEDIA_CONTROLS.md.

enum NowPlayingMode: Sendable {
    /// Native code owns MPNowPlayingInfoCenter + MPRemoteCommandCenter.
    case override
    /// Register nothing natively. WebKit's own session (driven by the page's navigator.mediaSession)
    /// remains the source of truth for media keys/Control Center. Registering our own handlers here
    /// could fight WebKit's for the single system Now Playing slot, and public API gives no way to
    /// disable WebKit's, so in this mode we deliberately stay out of the way.
    case rely

    static let `default`: NowPlayingMode = .override

    static var current: NowPlayingMode {
        switch ProcessInfo.processInfo.environment["AMAZONMUSIC_NOWPLAYING"]?.lowercased() {
        case "rely": .rely
        default: .default
        }
    }
}

enum NowPlayingPlaybackState: Sendable, Equatable { case playing, paused, stopped }

struct NowPlayingSnapshot: Sendable, Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var duration: Double?
    var elapsed: Double
    var rate: Double
    var playbackState: NowPlayingPlaybackState
    var artworkURL: URL?

    /// Unhealthy bridge or no track => stopped, with nothing to publish.
    var isEmpty: Bool { playbackState == .stopped }

    /// Pure mapping. `position` is the interpolated elapsed seconds at the time of the call.
    static func make(track: TrackInfo?, isPlaying: Bool, bridgeHealthy: Bool, position: Double) -> NowPlayingSnapshot {
        guard bridgeHealthy, let track, track.identity != nil else {
            return NowPlayingSnapshot(title: nil, artist: nil, album: nil, duration: nil, elapsed: 0, rate: 0,
                                      playbackState: .stopped, artworkURL: nil)
        }
        let duration = track.duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        var elapsed = position.isFinite ? max(0, position) : 0
        if let duration { elapsed = min(elapsed, duration) }
        return NowPlayingSnapshot(title: track.title, artist: track.artist, album: track.album,
                                  duration: duration, elapsed: elapsed, rate: isPlaying ? 1 : 0,
                                  playbackState: isPlaying ? .playing : .paused, artworkURL: track.artworkURL)
    }

    @MainActor
    static func make(from state: PlayerState, at date: Date = Date()) -> NowPlayingSnapshot {
        make(track: state.track, isPlaying: state.isPlaying, bridgeHealthy: state.bridgeHealthy,
             position: state.interpolatedPosition(at: date))
    }
}

private struct ImageBox: @unchecked Sendable { let image: NSImage }

@MainActor
final class NowPlayingController {
    private static let log = Logger(subsystem: "com.khalidabuhakmeh.amazonmusic", category: "nowplaying")

    private let state: PlayerState
    private let bridge: PlayerBridge
    private let mode: NowPlayingMode
    private let artwork: ArtworkCache
    private var observing: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var targets: [(MPRemoteCommand, Any)] = []
    private var artworkTask: Task<Void, Never>?
    private var publishedTrackID: String?
    private var cachedArtwork: MPMediaItemArtwork?

    init(state: PlayerState, bridge: PlayerBridge, mode: NowPlayingMode = .current, artwork: ArtworkCache = .shared) {
        self.state = state
        self.bridge = bridge
        self.mode = mode
        self.artwork = artwork
    }

    func start() {
        guard observing == nil else { return }
        guard mode == .override else {
            Self.log.info("NowPlaying mode=rely: registering nothing")
            return
        }
        registerHandlers()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.registerHandlers(); self?.publish(reason: .trackOrState) }
        }
        observing = Task { [weak self] in await self?.observeLoop() }
    }

    func stop() {
        observing?.cancel(); observing = nil
        artworkTask?.cancel(); artworkTask = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        unregisterHandlers()
        clear()
    }

    // MARK: Observation

    private func observeLoop() async {
        var lastHealthy = state.bridgeHealthy
        publish(reason: .trackOrState)
        while !Task.isCancelled {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                withObservationTracking {
                    _ = state.track; _ = state.isPlaying; _ = state.bridgeHealthy
                } onChange: {
                    c.resume()
                }
            }
            guard !Task.isCancelled else { return }
            if state.bridgeHealthy && !lastHealthy { registerHandlers() } // bridge recovered / page reloaded
            lastHealthy = state.bridgeHealthy
            publish(reason: .trackOrState)
        }
    }

    // MARK: Publishing

    enum PublishReason { case trackOrState, seek }

    /// Elapsed time is written ONLY here: called on play/pause/track change (observation fires only on
    /// those: track, isPlaying, bridgeHealthy), after a seek, and after wake. Never per position tick;
    /// the system extrapolates from elapsed + rate.
    private func publish(reason: PublishReason) {
        let snap = NowPlayingSnapshot.make(from: state)
        let center = MPNowPlayingInfoCenter.default()
        guard !snap.isEmpty else { clear(); return }

        var info: [String: Any] = [MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
                                   MPNowPlayingInfoPropertyElapsedPlaybackTime: snap.elapsed,
                                   MPNowPlayingInfoPropertyPlaybackRate: snap.rate,
                                   MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0]
        if let t = snap.title { info[MPMediaItemPropertyTitle] = t }
        if let a = snap.artist { info[MPMediaItemPropertyArtist] = a }
        if let a = snap.album { info[MPMediaItemPropertyAlbumTitle] = a }
        if let d = snap.duration { info[MPMediaItemPropertyPlaybackDuration] = d }

        let id = state.track?.identity
        if id != publishedTrackID {
            publishedTrackID = id
            cachedArtwork = nil
            loadArtwork(snap.artworkURL, forTrack: id)
        }
        if let cachedArtwork { info[MPMediaItemPropertyArtwork] = cachedArtwork }
        center.nowPlayingInfo = info
        center.playbackState = switch snap.playbackState {
        case .playing: .playing
        case .paused: .paused
        case .stopped: .stopped
        }
    }

    private func loadArtwork(_ url: URL?, forTrack id: String?) {
        artworkTask?.cancel()
        guard let url else { return }
        artworkTask = Task { [weak self, artwork] in
            guard let image = await artwork.image(for: url) else { return }
            let box = ImageBox(image: image)
            guard !Task.isCancelled, let self, self.publishedTrackID == id else { return }
            // Handler must be @Sendable; it may run off the main actor.
            let art = MPMediaItemArtwork(boundsSize: box.image.size) { @Sendable _ in box.image }
            self.cachedArtwork = art
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            guard !info.isEmpty else { return }
            info[MPMediaItemPropertyArtwork] = art // other keys (incl. elapsed) left untouched
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    private func clear() {
        publishedTrackID = nil
        cachedArtwork = nil
        artworkTask?.cancel()
        let center = MPNowPlayingInfoCenter.default()
        center.playbackState = .stopped
        center.nowPlayingInfo = nil
    }

    // MARK: Remote commands

    private func registerHandlers() {
        unregisterHandlers() // idempotent: never stack targets
        let cc = MPRemoteCommandCenter.shared()
        let bridge = self.bridge

        func add(_ cmd: MPRemoteCommand, _ send: @escaping @Sendable @MainActor () async -> Bool) {
            cmd.isEnabled = true
            let token = cmd.addTarget { _ in
                Task { @MainActor in _ = await send() }
                return .success
            }
            targets.append((cmd, token))
        }
        add(cc.playCommand) { await bridge.send(.play).ok }
        add(cc.pauseCommand) { await bridge.send(.pause).ok }
        add(cc.togglePlayPauseCommand) { await bridge.send(.toggle).ok }
        add(cc.nextTrackCommand) { await bridge.send(.next).ok }
        add(cc.previousTrackCommand) { await bridge.send(.previous).ok }

        cc.changePlaybackPositionCommand.isEnabled = true
        let seekToken = cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let pos = e.positionTime
            Task { @MainActor in
                if await bridge.send(.seek(pos)).ok { self?.didSeek(to: pos) }
            }
            return .success
        }
        targets.append((cc.changePlaybackPositionCommand, seekToken))

        for c in [cc.skipForwardCommand, cc.skipBackwardCommand, cc.seekForwardCommand, cc.seekBackwardCommand,
                  cc.changeRepeatModeCommand, cc.changeShuffleModeCommand, cc.changePlaybackRateCommand,
                  cc.likeCommand, cc.dislikeCommand, cc.bookmarkCommand, cc.stopCommand,
                  cc.enableLanguageOptionCommand, cc.disableLanguageOptionCommand, cc.ratingCommand] {
            c.isEnabled = false
        }
    }

    private func unregisterHandlers() {
        for (cmd, token) in targets { cmd.removeTarget(token) }
        targets.removeAll()
    }

    /// Seek: optimistic elapsed update (the page's position message arrives shortly after).
    private func didSeek(to position: Double) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPNowPlayingInfoPropertyPlaybackRate] = state.isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
