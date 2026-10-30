import Foundation
import Observation

@MainActor @Observable
final class PlayerState {
    private(set) var track: TrackInfo?
    private(set) var isPlaying = false
    private(set) var bridgeHealthy = true
    private(set) var lastError: String?
    private(set) var bridgeVersion: String?

    /// Like state last reported by the page (nil = unknown / no control).
    private(set) var confirmedLiked: Bool?
    private(set) var pendingLike: PendingLike?

    /// Upcoming tracks (next first) as last reported by the page; empty = unknown/none, so the UI hides the section.
    private(set) var upNext: [BridgeMessage.QueueItem] = []

    /// Sign-in state last reported by the page (nil = unknown).
    private(set) var signedIn: Bool?

    /// What the popover shows: a track (playing OR loaded-but-paused), the signed-out prompt, or "nothing loaded" (signed in / unknown).
    enum PopoverMode: Equatable, Sendable { case track, signedOut, nothingLoaded }
    var popoverMode: PopoverMode {
        guard bridgeHealthy else { return .nothingLoaded }
        if track != nil { return .track }
        return signedIn == false ? .signedOut : .nothingLoaded
    }

    /// The page reported that "Play Similar Music" is available for the current item.
    private(set) var reportedCanPlaySimilar = false
    /// The page can start a queue entry (Up Next rows clickable).
    private(set) var reportedCanJump = false
    /// The Up Next entry we asked the page to jump to (row shows pending); cleared when the track changes or after a short deadline.
    private(set) var jumpPending: (id: String, deadline: Date)?
    static let jumpWindow: TimeInterval = 6
    var canJumpToQueueItem: Bool { popoverMode == .track && reportedCanJump }
    func beginJump(to id: String, at now: Date = Date()) { jumpPending = (id, now.addingTimeInterval(Self.jumpWindow)) }
    func endJump() { if jumpPending != nil { jumpPending = nil } }
    /// True while a jump to this entry is pending (and not expired).
    func isJumpPending(_ id: String?, at now: Date = Date()) -> Bool { id != nil && jumpPending?.id == id && now < (jumpPending?.deadline ?? .distantPast) }

    /// True while a Play Similar action is running (badge shows a spinner); cleared when the track changes or after a short deadline.
    private(set) var similarPending: Date?
    static let similarWindow: TimeInterval = 6
    /// Whether the popover offers the action: a loaded track and the page says it is supported.
    var canPlaySimilar: Bool { popoverMode == .track && reportedCanPlaySimilar }
    func isSimilarInProgress(at now: Date = Date()) -> Bool { similarPending.map { now < $0 } ?? false }
    func beginSimilar(at now: Date = Date()) { similarPending = now.addingTimeInterval(Self.similarWindow) }
    func endSimilar() { if similarPending != nil { similarPending = nil } }

    struct PendingLike: Equatable, Sendable { var value: Bool; var deadline: Date }
    static let optimisticWindow: TimeInterval = 3

    /// What the UI should show: optimistic value while a toggle is in flight, else the page's value.
    /// nil when the page doesn't expose a like control (heart hidden/disabled).
    var isLiked: Bool? { confirmedLiked == nil ? nil : (pendingLike?.value ?? confirmedLiked) }

    /// Shuffle / repeat as last reported by the page (nil = unknown / no control), plus in-flight optimistic values.
    private(set) var confirmedShuffle: Bool?
    private(set) var pendingShuffle: PendingValue<Bool>?
    private(set) var confirmedRepeat: RepeatMode?
    private(set) var pendingRepeat: PendingValue<RepeatMode>?

    struct PendingValue<T: Equatable & Sendable>: Equatable, Sendable { var value: T; var deadline: Date }

    var isShuffled: Bool? { confirmedShuffle == nil ? nil : (pendingShuffle?.value ?? confirmedShuffle) }
    var repeatMode: RepeatMode? { confirmedRepeat == nil ? nil : (pendingRepeat?.value ?? confirmedRepeat) }

    // Position ticks must not invalidate SwiftUI views; views interpolate via interpolatedPosition(at:).
    @ObservationIgnored private(set) var position: Double?
    @ObservationIgnored private(set) var positionTimestamp: Date?

    @ObservationIgnored let trackChanged: AsyncStream<TrackInfo>
    @ObservationIgnored private let continuation: AsyncStream<TrackInfo>.Continuation

    init() {
        (trackChanged, continuation) = AsyncStream.makeStream(of: TrackInfo.self, bufferingPolicy: .bufferingNewest(8))
    }
    deinit { continuation.finish() }

    func apply(_ message: BridgeMessage, at now: Date = Date()) {
        switch message {
        case .ready(let version):
            if bridgeVersion != version { bridgeVersion = version }
            markHealthy()
        case .state(let s):
            markHealthy()
            let newTrack = TrackInfo(trackId: s.trackId, title: s.title, artist: s.artist, album: s.album,
                                     artworkURL: s.artworkURL, duration: s.duration)
            let old = track
            if newTrack.identity == nil {
                if track != nil { track = nil }
            } else {
                if newTrack != track { track = newTrack }
                if old?.identity != newTrack.identity { continuation.yield(newTrack) }
            }
            reconcileLike(reported: newTrack.identity == nil ? nil : s.liked, trackChanged: old?.identity != newTrack.identity, now: now)
            let changedTrack = old?.identity != newTrack.identity
            let hasTrack = newTrack.identity != nil
            let sh = Self.reconcile(&pendingShuffle, reported: hasTrack ? s.shuffle : nil, trackChanged: changedTrack, now: now)
            if confirmedShuffle != sh { confirmedShuffle = sh }
            let rp = Self.reconcile(&pendingRepeat, reported: hasTrack ? s.repeatMode : nil, trackChanged: changedTrack, now: now)
            if confirmedRepeat != rp { confirmedRepeat = rp }
            let q = hasTrack ? (s.queue ?? []) : []
            if upNext != q { upNext = q }
            if signedIn != s.signedIn { signedIn = s.signedIn }
            let canSimilar = hasTrack && (s.canPlaySimilar ?? false)
            if reportedCanPlaySimilar != canSimilar { reportedCanPlaySimilar = canSimilar }
            if changedTrack { endSimilar(); endJump() }
            let canJump = hasTrack && (s.canJumpToQueueItem ?? false)
            if reportedCanJump != canJump { reportedCanJump = canJump }
            if isPlaying != s.isPlaying { isPlaying = s.isPlaying }
            position = s.position
            positionTimestamp = s.position == nil ? nil : now
        case .position(let p, let d):
            markHealthy()
            if let p { position = p; positionTimestamp = now }
            if let d, var t = track, t.duration != d { t.duration = d; track = t }
        case .error(let code, let msg):
            markUnhealthy(msg ?? code ?? "Unknown bridge error")
        case .log, .unknown:
            break
        }
    }

    /// Flips the shown like state immediately. Returns the new value, or nil if like is unavailable.
    @discardableResult
    func beginOptimisticLike(at now: Date = Date()) -> Bool? {
        guard let current = isLiked else { return nil }
        pendingLike = PendingLike(value: !current, deadline: now.addingTimeInterval(Self.optimisticWindow))
        return !current
    }

    /// Drops the optimistic value (command failed or timed out); the page's value shows again.
    func clearOptimisticLike() { if pendingLike != nil { pendingLike = nil } }

    private func reconcileLike(reported: Bool?, trackChanged: Bool, now: Date) {
        if trackChanged { pendingLike = nil }
        if let pending = pendingLike {
            if reported == pending.value || reported == nil || now >= pending.deadline { pendingLike = nil }
            // else: stale report that predates the toggle taking effect; keep the optimistic value until the deadline.
        }
        if confirmedLiked != reported { confirmedLiked = reported }
    }

    /// Flips the shown shuffle state immediately. Returns the new value, or nil if shuffle is unavailable.
    @discardableResult
    func beginOptimisticShuffle(at now: Date = Date()) -> Bool? {
        guard let current = isShuffled else { return nil }
        pendingShuffle = PendingValue(value: !current, deadline: now.addingTimeInterval(Self.optimisticWindow))
        return !current
    }
    func clearOptimisticShuffle() { if pendingShuffle != nil { pendingShuffle = nil } }

    /// Advances the shown repeat mode (off -> all -> one -> off) immediately; nil if repeat is unavailable.
    @discardableResult
    func beginOptimisticRepeat(at now: Date = Date()) -> RepeatMode? {
        guard let current = repeatMode else { return nil }
        pendingRepeat = PendingValue(value: current.next, deadline: now.addingTimeInterval(Self.optimisticWindow))
        return current.next
    }
    func clearOptimisticRepeat() { if pendingRepeat != nil { pendingRepeat = nil } }

    /// Same rules as like: pending clears on confirmation, unknown report, track change or deadline; stale reports are ignored until then.
    private static func reconcile<T: Equatable>(_ pending: inout PendingValue<T>?, reported: T?, trackChanged: Bool, now: Date) -> T? {
        if trackChanged { pending = nil }
        if let p = pending, reported == p.value || reported == nil || now >= p.deadline { pending = nil }
        return reported
    }

    func markUnhealthy(_ reason: String) {
        if bridgeHealthy { bridgeHealthy = false }
        if lastError != reason { lastError = reason }
    }

    private func markHealthy() {
        if !bridgeHealthy { bridgeHealthy = true }
        if lastError != nil { lastError = nil }
    }

    func interpolatedPosition(at date: Date) -> Double {
        var p = position ?? 0
        if isPlaying, let ts = positionTimestamp { p += max(0, date.timeIntervalSince(ts)) }
        if let d = track?.duration, d.isFinite, d >= 0 { p = min(p, d) }
        return max(0, p)
    }
}
