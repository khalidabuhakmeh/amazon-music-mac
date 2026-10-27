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
            bridgeVersion = version
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
            if isPlaying != s.isPlaying { isPlaying = s.isPlaying }
            position = s.position
            positionTimestamp = s.position == nil ? nil : now
        case .position(let p, let d):
            markHealthy()
            if let p { position = p; positionTimestamp = now }
            if let d, var t = track, t.duration != d { t.duration = d; track = t }
        case .error(let code, let msg):
            bridgeHealthy = false
            lastError = msg ?? code ?? "Unknown bridge error"
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
        bridgeHealthy = false
        lastError = reason
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
