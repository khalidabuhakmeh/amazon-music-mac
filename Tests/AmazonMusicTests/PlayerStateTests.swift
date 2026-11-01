import Testing
import Foundation
@testable import AmazonMusic

@MainActor
@Suite struct PlayerStateTests {
    func st(title: String? = "T", artist: String? = "A", id: String? = nil, playing: Bool = true,
            pos: Double? = 10, dur: Double? = 100) -> BridgeMessage {
        .state(.init(trackId: id, title: title, artist: artist, album: title == nil ? nil : "Al", artworkURL: nil,
                     duration: dur, position: pos, isPlaying: playing))
    }

    @Test func testReducer() {
        let s = PlayerState(); let t0 = Date(timeIntervalSince1970: 1000)
        s.apply(st(), at: t0)
        #expect(s.track?.title == "T"); #expect(s.isPlaying)
        #expect(s.position == 10); #expect(s.positionTimestamp == t0)
        s.apply(.position(position: 20, duration: nil), at: t0 + 5)
        #expect(s.position == 20)
        s.apply(st(title: nil, artist: nil), at: t0)
        #expect(s.track == nil)
    }

    @Test func testPopoverModeSignedOutVsNothingLoadedVsPausedTrack() {
        let s = PlayerState()
        func msg(title: String?, playing: Bool, signedIn: Bool?, pos: Double? = 96) -> BridgeMessage {
            .state(.init(trackId: nil, title: title, artist: title == nil ? nil : "A", album: title == nil ? nil : "Al", artworkURL: nil,
                         duration: title == nil ? nil : 137, position: title == nil ? nil : pos, isPlaying: playing, signedIn: signedIn))
        }
        #expect(s.popoverMode == .nothingLoaded)                       // before any message
        s.apply(msg(title: nil, playing: false, signedIn: nil)); #expect(s.popoverMode == .nothingLoaded) // unknown: no sign-in wording
        s.apply(msg(title: nil, playing: false, signedIn: true)); #expect(s.popoverMode == .nothingLoaded)
        s.apply(msg(title: nil, playing: false, signedIn: false)); #expect(s.popoverMode == .signedOut)
        // loaded-but-paused track (right after launch): shown with progress, not playing
        s.apply(msg(title: "T", playing: false, signedIn: true))
        #expect(s.popoverMode == .track); #expect(s.track?.title == "T"); #expect(!(s.isPlaying))
        #expect(s.track?.duration == 137); #expect(s.position == 96)
        s.apply(msg(title: "T", playing: true, signedIn: true)); #expect(s.isPlaying); #expect(s.popoverMode == .track)
        // a track wins even if the sign-in flag is momentarily false; an unhealthy bridge never claims "signed out"
        s.apply(msg(title: "T", playing: false, signedIn: false)); #expect(s.popoverMode == .track)
        s.apply(msg(title: nil, playing: false, signedIn: false)); s.markUnhealthy("x")
        #expect(s.popoverMode == .nothingLoaded)
    }

    @Test func testPlaySimilarAvailabilityAndPending() {
        let s = PlayerState(); let t0 = Date(timeIntervalSince1970: 1000)
        func msg(_ title: String?, similar: Bool?, signedIn: Bool? = true) -> BridgeMessage {
            .state(.init(trackId: nil, title: title, artist: title == nil ? nil : "A", album: title == nil ? nil : "Al", artworkURL: nil,
                         duration: 100, position: 1, isPlaying: true, signedIn: signedIn, canPlaySimilar: similar))
        }
        #expect(!(s.canPlaySimilar))
        s.apply(msg(nil, similar: true), at: t0); #expect(!(s.canPlaySimilar))       // nothing loaded: never offered
        s.apply(msg("T", similar: nil), at: t0); #expect(!(s.canPlaySimilar))        // unknown (older bridge)
        s.apply(msg("T", similar: false), at: t0); #expect(!(s.canPlaySimilar))      // podcast / unsupported
        s.apply(msg("T", similar: true), at: t0); #expect(s.canPlaySimilar)
        s.markUnhealthy("x"); #expect(!(s.canPlaySimilar))                           // unhealthy bridge: hidden
        s.apply(msg("T", similar: true), at: t0); #expect(s.canPlaySimilar)
        // pending spinner: set, expires, cleared by a track change
        #expect(!(s.isSimilarInProgress(at: t0)))
        s.beginSimilar(at: t0); #expect(s.isSimilarInProgress(at: t0 + 1)); #expect(!(s.isSimilarInProgress(at: t0 + 7)))
        s.apply(msg("T", similar: true), at: t0 + 1); #expect(s.similarPending != nil)  // same track: still pending
        s.apply(msg("Other", similar: true), at: t0 + 2); #expect(s.similarPending == nil) // new track: spinner ends
    }

    @Test func testJumpAvailabilityAndPending() {
        let s = PlayerState(); let t0 = Date(timeIntervalSince1970: 1000)
        func msg(_ title: String?, jump: Bool?) -> BridgeMessage {
            .state(.init(trackId: nil, title: title, artist: title == nil ? nil : "A", album: title == nil ? nil : "Al", artworkURL: nil,
                         duration: 100, position: 1, isPlaying: true, canJumpToQueueItem: jump))
        }
        #expect(!(s.canJumpToQueueItem))
        s.apply(msg("T", jump: nil), at: t0); #expect(!(s.canJumpToQueueItem))   // older bridge
        s.apply(msg("T", jump: false), at: t0); #expect(!(s.canJumpToQueueItem))
        s.apply(msg(nil, jump: true), at: t0); #expect(!(s.canJumpToQueueItem))  // nothing loaded
        s.apply(msg("T", jump: true), at: t0); #expect(s.canJumpToQueueItem)
        s.markUnhealthy("x"); #expect(!(s.canJumpToQueueItem))
        s.apply(msg("T", jump: true), at: t0)
        // pending: per entry, expires, cleared by a track change
        s.beginJump(to: "id1", at: t0)
        #expect(s.isJumpPending("id1", at: t0 + 1)); #expect(!(s.isJumpPending("id2", at: t0 + 1)))
        #expect(!(s.isJumpPending("id1", at: t0 + 7))); #expect(!(s.isJumpPending(nil, at: t0)))
        s.apply(msg("T", jump: true), at: t0 + 1); #expect(s.jumpPending != nil)   // same track: still pending
        s.apply(msg("Next song", jump: true), at: t0 + 2); #expect(s.jumpPending == nil)
    }

    @Test func testUpNextQueueHandling() {
        let s = PlayerState()
        func msg(title: String?, queue: [BridgeMessage.QueueItem]?) -> BridgeMessage {
            .state(.init(trackId: nil, title: title, artist: title == nil ? nil : "A", album: title == nil ? nil : "Al", artworkURL: nil,
                         duration: 100, position: 1, isPlaying: true, queue: queue))
        }
        #expect(s.upNext.isEmpty)
        let items = [BridgeMessage.QueueItem(title: "N1", artist: "X", artworkURL: nil), .init(title: "N2", artist: nil, artworkURL: nil)]
        s.apply(msg(title: "T", queue: items)); #expect(s.upNext == items)
        s.apply(msg(title: "T", queue: nil)); #expect(s.upNext.isEmpty)           // unknown -> hidden
        s.apply(msg(title: "T", queue: items)); s.apply(msg(title: nil, queue: items))   // nothing playing -> hidden
        #expect(s.upNext.isEmpty)
    }

    func stl(_ liked: Bool?, title: String = "T") -> BridgeMessage {
        .state(.init(trackId: nil, title: title, artist: "A", album: "Al", artworkURL: nil,
                     duration: 100, position: 1, isPlaying: true, liked: liked))
    }

    @Test func testLikedReducerAndOptimisticReconciliation() {
        let s = PlayerState(); let t0 = Date(timeIntervalSince1970: 1000)
        #expect(s.isLiked == nil)
        #expect(s.beginOptimisticLike(at: t0) == nil)              // unknown: no optimistic flip
        s.apply(stl(nil), at: t0); #expect(s.isLiked == nil)
        s.apply(stl(false), at: t0); #expect(s.isLiked == false)
        #expect(s.beginOptimisticLike(at: t0) == true); #expect(s.isLiked == true)
        s.apply(stl(false), at: t0 + 1); #expect(s.isLiked == true)   // stale report inside window
        s.apply(stl(true), at: t0 + 2); #expect(s.isLiked == true); #expect(s.pendingLike == nil)
        // never confirmed: falls back to page value after the window
        #expect(s.beginOptimisticLike(at: t0 + 10) == false)
        s.apply(stl(true), at: t0 + 14); #expect(s.isLiked == true)
        // explicit clear (command failed)
        s.beginOptimisticLike(at: t0 + 20); s.clearOptimisticLike(); #expect(s.isLiked == true)
        // track change drops pending and takes the new value
        s.beginOptimisticLike(at: t0 + 30)
        s.apply(stl(false, title: "Other"), at: t0 + 30.5); #expect(s.isLiked == false)
        // control disappears
        s.apply(stl(nil, title: "Other"), at: t0 + 31); #expect(s.isLiked == nil)
        // no track: unknown
        s.apply(stl(true), at: t0 + 32); s.apply(st(title: nil, artist: nil), at: t0 + 33); #expect(s.isLiked == nil)
    }

    func stsr(_ shuffle: Bool?, _ rep: RepeatMode?, title: String = "T") -> BridgeMessage {
        .state(.init(trackId: nil, title: title, artist: "A", album: "Al", artworkURL: nil,
                     duration: 100, position: 1, isPlaying: true, shuffle: shuffle, repeatMode: rep))
    }

    @Test func testShuffleReducerAndOptimisticReconciliation() {
        let s = PlayerState(); let t0 = Date(timeIntervalSince1970: 1000)
        #expect(s.isShuffled == nil); #expect(s.beginOptimisticShuffle(at: t0) == nil)
        s.apply(stsr(nil, nil), at: t0); #expect(s.isShuffled == nil)
        s.apply(stsr(false, .off), at: t0); #expect(s.isShuffled == false)
        #expect(s.beginOptimisticShuffle(at: t0) == true); #expect(s.isShuffled == true)
        s.apply(stsr(false, .off), at: t0 + 1); #expect(s.isShuffled == true)      // stale inside window
        s.apply(stsr(true, .off), at: t0 + 2); #expect(s.isShuffled == true); #expect(s.pendingShuffle == nil)
        s.beginOptimisticShuffle(at: t0 + 10)                                           // never confirmed
        s.apply(stsr(true, .off), at: t0 + 14); #expect(s.isShuffled == true)
        s.beginOptimisticShuffle(at: t0 + 20); s.clearOptimisticShuffle(); #expect(s.isShuffled == true)
        s.beginOptimisticShuffle(at: t0 + 30)                                           // track change drops pending
        s.apply(stsr(false, .off, title: "Other"), at: t0 + 30.5); #expect(s.isShuffled == false)
        s.apply(stsr(nil, .off, title: "Other"), at: t0 + 31); #expect(s.isShuffled == nil)
        s.apply(stsr(true, .off), at: t0 + 32); s.apply(st(title: nil, artist: nil), at: t0 + 33); #expect(s.isShuffled == nil)
    }

    @Test func testRepeatCycleAndReconciliation() {
        #expect(RepeatMode.off.next == .all); #expect(RepeatMode.all.next == .one); #expect(RepeatMode.one.next == .off)
        let s = PlayerState(); let t0 = Date(timeIntervalSince1970: 1000)
        #expect(s.beginOptimisticRepeat(at: t0) == nil)
        s.apply(stsr(false, .off), at: t0); #expect(s.repeatMode == .off)
        #expect(s.beginOptimisticRepeat(at: t0) == .all); #expect(s.repeatMode == .all)
        s.apply(stsr(false, .off), at: t0 + 1); #expect(s.repeatMode == .all)       // stale
        s.apply(stsr(false, .all), at: t0 + 2); #expect(s.pendingRepeat == nil); #expect(s.repeatMode == .all)
        #expect(s.beginOptimisticRepeat(at: t0 + 5) == .one)
        s.apply(stsr(false, .all), at: t0 + 9); #expect(s.repeatMode == .all)       // window expired: page wins
        s.beginOptimisticRepeat(at: t0 + 10); s.clearOptimisticRepeat(); #expect(s.repeatMode == .all)
        s.apply(stsr(false, nil), at: t0 + 11); #expect(s.repeatMode == nil)
    }

    @Test func testLikeDoesNotAffectTrackIdentity() {
        let s = PlayerState()
        s.apply(stl(false)); let a = s.track
        s.apply(stl(true)); #expect(s.track == a)
    }

    @Test func testTrackIdentity() {
        #expect(TrackInfo(trackId: "x", title: "a").identity == TrackInfo(trackId: "x", title: "b").identity)
        #expect(TrackInfo(title: "a", artist: "b").identity == TrackInfo(title: "a", artist: "b", duration: 5).identity)
        #expect(TrackInfo(title: "a", artist: "b").identity != TrackInfo(title: "a", artist: "c").identity)
        #expect(TrackInfo().identity == nil)
    }

    @Test func testTrackChangedOnlyOnIdentityChange() async {
        let s = PlayerState()
        s.apply(st(title: nil, artist: nil))          // nil track: no emit
        s.apply(st(title: "A1")); s.apply(st(title: "A1", playing: false)) // duplicate
        s.apply(st(title: "A1", dur: 99))             // same identity
        s.apply(st(title: "B"))
        var got: [String?] = []
        for await t in s.trackChanged { got.append(t.title); if got.count == 2 { break } }
        #expect(got == ["A1", "B"])
    }

    @Test func testInterpolation() {
        let s = PlayerState(); let t0 = Date(timeIntervalSince1970: 1000)
        s.apply(st(playing: true, pos: 10, dur: 100), at: t0)
        #expect(abs((s.interpolatedPosition(at: t0 + 5)) - (15)) <= 0.001)
        #expect(abs((s.interpolatedPosition(at: t0 + 500)) - (100)) <= 0.001)
        #expect(abs((s.interpolatedPosition(at: t0 - 50)) - (10)) <= 0.001)
        s.apply(st(playing: false, pos: 10, dur: 100), at: t0)
        #expect(abs((s.interpolatedPosition(at: t0 + 5)) - (10)) <= 0.001)
        #expect(PlayerState().interpolatedPosition(at: t0) == 0)
    }

    @Test func testBridgeVersionFromReady() {
        let s = PlayerState()
        #expect(s.bridgeVersion == nil)
        s.apply(.ready(bridgeVersion: "3"))
        #expect(s.bridgeVersion == "3")
    }

    @Test func testHealth() {
        let s = PlayerState()
        s.apply(.error(code: "c", message: "boom"))
        #expect(!(s.bridgeHealthy)); #expect(s.lastError == "boom")
        s.apply(.ready(bridgeVersion: "1"))
        #expect(s.bridgeHealthy); #expect(s.lastError == nil)
        s.apply(.error(code: "c", message: nil)); #expect(!(s.bridgeHealthy))
        s.apply(st()); #expect(s.bridgeHealthy)
    }

    @Test func testCommandScripts() {
        #expect(PlayerCommand.seek(12.5).script == "window.__amzBridge.seek(12.5)")
        #expect(PlayerCommand.seek(.nan).script == nil)
    }

    @Test func testSkipCommandScriptsAwaitAndReturnJSON() {
        #expect(PlayerCommand.next.asyncBody == "return JSON.stringify(await window.__amzBridge.next());")
        #expect(PlayerCommand.previous.asyncBody == "return JSON.stringify(await window.__amzBridge.previous());")
        #expect(PlayerCommand.seek(.infinity).asyncBody == nil)
    }

    @Test func testCommandResultParsing() {
        let ok = CommandResult.parse(#"{"ok":true,"via":"mediaSession","changed":true}"#)
        #expect(ok == CommandResult(ok: true, via: "mediaSession", reason: nil, changed: true))
        let bad = CommandResult.parse(#"{"ok":false,"reason":"no_nexttrack_control"}"#)
        #expect(!(bad.ok)); #expect(bad.reason == "no_nexttrack_control")
        // Anything that is not the expected JSON string is a failure, never a silent success.
        #expect(!(CommandResult.parse(nil).ok))
        #expect(!(CommandResult.parse(["ok": true]).ok))
        #expect(!(CommandResult.parse("garbage").ok))
        #expect(CommandResult.parse("garbage").reason == "unparseable_result")
    }

    /// Repeated identical messages must not fire Observation (each set notifies even when equal).
    @Test func testRepeatedMessagesDoNotNotifyObservers() {
        let s = PlayerState(); let t0 = Date(timeIntervalSince1970: 1000)
        s.apply(.ready(bridgeVersion: "3")); s.apply(st(), at: t0)
        func fires(_ body: () -> Void) -> Bool {
            let fired = FiredFlag()
            withObservationTracking {
                _ = s.track; _ = s.isPlaying; _ = s.bridgeHealthy; _ = s.lastError; _ = s.bridgeVersion
                _ = s.upNext; _ = s.signedIn; _ = s.isLiked; _ = s.isShuffled; _ = s.repeatMode
            } onChange: { fired.value = true }
            body()
            return fired.value
        }
        #expect(!(fires { s.apply(.position(position: 30, duration: 100), at: t0 + 1) }))
        #expect(!(fires { s.apply(self.st(), at: t0 + 2) }))
        #expect(!(fires { s.apply(.ready(bridgeVersion: "3")) }))
        s.apply(.error(code: "x", message: "boom"))
        #expect(!(fires { s.apply(.error(code: "x", message: "boom")) }))
        #expect(!(fires { s.markUnhealthy("boom") }))
    }
}

final class FiredFlag: @unchecked Sendable { var value = false }
