import XCTest
@testable import AmazonMusic

@MainActor
final class PlayerStateTests: XCTestCase {
    func st(title: String? = "T", artist: String? = "A", id: String? = nil, playing: Bool = true,
            pos: Double? = 10, dur: Double? = 100) -> BridgeMessage {
        .state(.init(trackId: id, title: title, artist: artist, album: title == nil ? nil : "Al", artworkURL: nil,
                     duration: dur, position: pos, isPlaying: playing))
    }

    func testReducer() {
        let s = PlayerState(); let t0 = Date(timeIntervalSince1970: 1000)
        s.apply(st(), at: t0)
        XCTAssertEqual(s.track?.title, "T"); XCTAssertTrue(s.isPlaying)
        XCTAssertEqual(s.position, 10); XCTAssertEqual(s.positionTimestamp, t0)
        s.apply(.position(position: 20, duration: nil), at: t0 + 5)
        XCTAssertEqual(s.position, 20)
        s.apply(st(title: nil, artist: nil), at: t0)
        XCTAssertNil(s.track)
    }

    func testPopoverModeSignedOutVsNothingLoadedVsPausedTrack() {
        let s = PlayerState()
        func msg(title: String?, playing: Bool, signedIn: Bool?, pos: Double? = 96) -> BridgeMessage {
            .state(.init(trackId: nil, title: title, artist: title == nil ? nil : "A", album: title == nil ? nil : "Al", artworkURL: nil,
                         duration: title == nil ? nil : 137, position: title == nil ? nil : pos, isPlaying: playing, signedIn: signedIn))
        }
        XCTAssertEqual(s.popoverMode, .nothingLoaded)                       // before any message
        s.apply(msg(title: nil, playing: false, signedIn: nil)); XCTAssertEqual(s.popoverMode, .nothingLoaded) // unknown: no sign-in wording
        s.apply(msg(title: nil, playing: false, signedIn: true)); XCTAssertEqual(s.popoverMode, .nothingLoaded)
        s.apply(msg(title: nil, playing: false, signedIn: false)); XCTAssertEqual(s.popoverMode, .signedOut)
        // loaded-but-paused track (right after launch): shown with progress, not playing
        s.apply(msg(title: "T", playing: false, signedIn: true))
        XCTAssertEqual(s.popoverMode, .track); XCTAssertEqual(s.track?.title, "T"); XCTAssertFalse(s.isPlaying)
        XCTAssertEqual(s.track?.duration, 137); XCTAssertEqual(s.position, 96)
        s.apply(msg(title: "T", playing: true, signedIn: true)); XCTAssertTrue(s.isPlaying); XCTAssertEqual(s.popoverMode, .track)
        // a track wins even if the sign-in flag is momentarily false; an unhealthy bridge never claims "signed out"
        s.apply(msg(title: "T", playing: false, signedIn: false)); XCTAssertEqual(s.popoverMode, .track)
        s.apply(msg(title: nil, playing: false, signedIn: false)); s.markUnhealthy("x")
        XCTAssertEqual(s.popoverMode, .nothingLoaded)
    }

    func testPlaySimilarAvailabilityAndPending() {
        let s = PlayerState(); let t0 = Date(timeIntervalSince1970: 1000)
        func msg(_ title: String?, similar: Bool?, signedIn: Bool? = true) -> BridgeMessage {
            .state(.init(trackId: nil, title: title, artist: title == nil ? nil : "A", album: title == nil ? nil : "Al", artworkURL: nil,
                         duration: 100, position: 1, isPlaying: true, signedIn: signedIn, canPlaySimilar: similar))
        }
        XCTAssertFalse(s.canPlaySimilar)
        s.apply(msg(nil, similar: true), at: t0); XCTAssertFalse(s.canPlaySimilar)       // nothing loaded: never offered
        s.apply(msg("T", similar: nil), at: t0); XCTAssertFalse(s.canPlaySimilar)        // unknown (older bridge)
        s.apply(msg("T", similar: false), at: t0); XCTAssertFalse(s.canPlaySimilar)      // podcast / unsupported
        s.apply(msg("T", similar: true), at: t0); XCTAssertTrue(s.canPlaySimilar)
        s.markUnhealthy("x"); XCTAssertFalse(s.canPlaySimilar)                           // unhealthy bridge: hidden
        s.apply(msg("T", similar: true), at: t0); XCTAssertTrue(s.canPlaySimilar)
        // pending spinner: set, expires, cleared by a track change
        XCTAssertFalse(s.isSimilarInProgress(at: t0))
        s.beginSimilar(at: t0); XCTAssertTrue(s.isSimilarInProgress(at: t0 + 1)); XCTAssertFalse(s.isSimilarInProgress(at: t0 + 7))
        s.apply(msg("T", similar: true), at: t0 + 1); XCTAssertNotNil(s.similarPending)  // same track: still pending
        s.apply(msg("Other", similar: true), at: t0 + 2); XCTAssertNil(s.similarPending) // new track: spinner ends
    }

    func testJumpAvailabilityAndPending() {
        let s = PlayerState(); let t0 = Date(timeIntervalSince1970: 1000)
        func msg(_ title: String?, jump: Bool?) -> BridgeMessage {
            .state(.init(trackId: nil, title: title, artist: title == nil ? nil : "A", album: title == nil ? nil : "Al", artworkURL: nil,
                         duration: 100, position: 1, isPlaying: true, canJumpToQueueItem: jump))
        }
        XCTAssertFalse(s.canJumpToQueueItem)
        s.apply(msg("T", jump: nil), at: t0); XCTAssertFalse(s.canJumpToQueueItem)   // older bridge
        s.apply(msg("T", jump: false), at: t0); XCTAssertFalse(s.canJumpToQueueItem)
        s.apply(msg(nil, jump: true), at: t0); XCTAssertFalse(s.canJumpToQueueItem)  // nothing loaded
        s.apply(msg("T", jump: true), at: t0); XCTAssertTrue(s.canJumpToQueueItem)
        s.markUnhealthy("x"); XCTAssertFalse(s.canJumpToQueueItem)
        s.apply(msg("T", jump: true), at: t0)
        // pending: per entry, expires, cleared by a track change
        s.beginJump(to: "id1", at: t0)
        XCTAssertTrue(s.isJumpPending("id1", at: t0 + 1)); XCTAssertFalse(s.isJumpPending("id2", at: t0 + 1))
        XCTAssertFalse(s.isJumpPending("id1", at: t0 + 7)); XCTAssertFalse(s.isJumpPending(nil, at: t0))
        s.apply(msg("T", jump: true), at: t0 + 1); XCTAssertNotNil(s.jumpPending)   // same track: still pending
        s.apply(msg("Next song", jump: true), at: t0 + 2); XCTAssertNil(s.jumpPending)
    }

    func testUpNextQueueHandling() {
        let s = PlayerState()
        func msg(title: String?, queue: [BridgeMessage.QueueItem]?) -> BridgeMessage {
            .state(.init(trackId: nil, title: title, artist: title == nil ? nil : "A", album: title == nil ? nil : "Al", artworkURL: nil,
                         duration: 100, position: 1, isPlaying: true, queue: queue))
        }
        XCTAssertTrue(s.upNext.isEmpty)
        let items = [BridgeMessage.QueueItem(title: "N1", artist: "X", artworkURL: nil), .init(title: "N2", artist: nil, artworkURL: nil)]
        s.apply(msg(title: "T", queue: items)); XCTAssertEqual(s.upNext, items)
        s.apply(msg(title: "T", queue: nil)); XCTAssertTrue(s.upNext.isEmpty)           // unknown -> hidden
        s.apply(msg(title: "T", queue: items)); s.apply(msg(title: nil, queue: items))   // nothing playing -> hidden
        XCTAssertTrue(s.upNext.isEmpty)
    }

    func stl(_ liked: Bool?, title: String = "T") -> BridgeMessage {
        .state(.init(trackId: nil, title: title, artist: "A", album: "Al", artworkURL: nil,
                     duration: 100, position: 1, isPlaying: true, liked: liked))
    }

    func testLikedReducerAndOptimisticReconciliation() {
        let s = PlayerState(); let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertNil(s.isLiked)
        XCTAssertNil(s.beginOptimisticLike(at: t0))              // unknown: no optimistic flip
        s.apply(stl(nil), at: t0); XCTAssertNil(s.isLiked)
        s.apply(stl(false), at: t0); XCTAssertEqual(s.isLiked, false)
        XCTAssertEqual(s.beginOptimisticLike(at: t0), true); XCTAssertEqual(s.isLiked, true)
        s.apply(stl(false), at: t0 + 1); XCTAssertEqual(s.isLiked, true)   // stale report inside window
        s.apply(stl(true), at: t0 + 2); XCTAssertEqual(s.isLiked, true); XCTAssertNil(s.pendingLike)
        // never confirmed: falls back to page value after the window
        XCTAssertEqual(s.beginOptimisticLike(at: t0 + 10), false)
        s.apply(stl(true), at: t0 + 14); XCTAssertEqual(s.isLiked, true)
        // explicit clear (command failed)
        s.beginOptimisticLike(at: t0 + 20); s.clearOptimisticLike(); XCTAssertEqual(s.isLiked, true)
        // track change drops pending and takes the new value
        s.beginOptimisticLike(at: t0 + 30)
        s.apply(stl(false, title: "Other"), at: t0 + 30.5); XCTAssertEqual(s.isLiked, false)
        // control disappears
        s.apply(stl(nil, title: "Other"), at: t0 + 31); XCTAssertNil(s.isLiked)
        // no track: unknown
        s.apply(stl(true), at: t0 + 32); s.apply(st(title: nil, artist: nil), at: t0 + 33); XCTAssertNil(s.isLiked)
    }

    func stsr(_ shuffle: Bool?, _ rep: RepeatMode?, title: String = "T") -> BridgeMessage {
        .state(.init(trackId: nil, title: title, artist: "A", album: "Al", artworkURL: nil,
                     duration: 100, position: 1, isPlaying: true, shuffle: shuffle, repeatMode: rep))
    }

    func testShuffleReducerAndOptimisticReconciliation() {
        let s = PlayerState(); let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertNil(s.isShuffled); XCTAssertNil(s.beginOptimisticShuffle(at: t0))
        s.apply(stsr(nil, nil), at: t0); XCTAssertNil(s.isShuffled)
        s.apply(stsr(false, .off), at: t0); XCTAssertEqual(s.isShuffled, false)
        XCTAssertEqual(s.beginOptimisticShuffle(at: t0), true); XCTAssertEqual(s.isShuffled, true)
        s.apply(stsr(false, .off), at: t0 + 1); XCTAssertEqual(s.isShuffled, true)      // stale inside window
        s.apply(stsr(true, .off), at: t0 + 2); XCTAssertEqual(s.isShuffled, true); XCTAssertNil(s.pendingShuffle)
        s.beginOptimisticShuffle(at: t0 + 10)                                           // never confirmed
        s.apply(stsr(true, .off), at: t0 + 14); XCTAssertEqual(s.isShuffled, true)
        s.beginOptimisticShuffle(at: t0 + 20); s.clearOptimisticShuffle(); XCTAssertEqual(s.isShuffled, true)
        s.beginOptimisticShuffle(at: t0 + 30)                                           // track change drops pending
        s.apply(stsr(false, .off, title: "Other"), at: t0 + 30.5); XCTAssertEqual(s.isShuffled, false)
        s.apply(stsr(nil, .off, title: "Other"), at: t0 + 31); XCTAssertNil(s.isShuffled)
        s.apply(stsr(true, .off), at: t0 + 32); s.apply(st(title: nil, artist: nil), at: t0 + 33); XCTAssertNil(s.isShuffled)
    }

    func testRepeatCycleAndReconciliation() {
        XCTAssertEqual(RepeatMode.off.next, .all); XCTAssertEqual(RepeatMode.all.next, .one); XCTAssertEqual(RepeatMode.one.next, .off)
        let s = PlayerState(); let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertNil(s.beginOptimisticRepeat(at: t0))
        s.apply(stsr(false, .off), at: t0); XCTAssertEqual(s.repeatMode, .off)
        XCTAssertEqual(s.beginOptimisticRepeat(at: t0), .all); XCTAssertEqual(s.repeatMode, .all)
        s.apply(stsr(false, .off), at: t0 + 1); XCTAssertEqual(s.repeatMode, .all)       // stale
        s.apply(stsr(false, .all), at: t0 + 2); XCTAssertNil(s.pendingRepeat); XCTAssertEqual(s.repeatMode, .all)
        XCTAssertEqual(s.beginOptimisticRepeat(at: t0 + 5), .one)
        s.apply(stsr(false, .all), at: t0 + 9); XCTAssertEqual(s.repeatMode, .all)       // window expired: page wins
        s.beginOptimisticRepeat(at: t0 + 10); s.clearOptimisticRepeat(); XCTAssertEqual(s.repeatMode, .all)
        s.apply(stsr(false, nil), at: t0 + 11); XCTAssertNil(s.repeatMode)
    }

    func testLikeDoesNotAffectTrackIdentity() {
        let s = PlayerState()
        s.apply(stl(false)); let a = s.track
        s.apply(stl(true)); XCTAssertEqual(s.track, a)
    }

    func testTrackIdentity() {
        XCTAssertEqual(TrackInfo(trackId: "x", title: "a").identity, TrackInfo(trackId: "x", title: "b").identity)
        XCTAssertEqual(TrackInfo(title: "a", artist: "b").identity, TrackInfo(title: "a", artist: "b", duration: 5).identity)
        XCTAssertNotEqual(TrackInfo(title: "a", artist: "b").identity, TrackInfo(title: "a", artist: "c").identity)
        XCTAssertNil(TrackInfo().identity)
    }

    func testTrackChangedOnlyOnIdentityChange() async {
        let s = PlayerState()
        s.apply(st(title: nil, artist: nil))          // nil track: no emit
        s.apply(st(title: "A1")); s.apply(st(title: "A1", playing: false)) // duplicate
        s.apply(st(title: "A1", dur: 99))             // same identity
        s.apply(st(title: "B"))
        var got: [String?] = []
        for await t in s.trackChanged { got.append(t.title); if got.count == 2 { break } }
        XCTAssertEqual(got, ["A1", "B"])
    }

    func testInterpolation() {
        let s = PlayerState(); let t0 = Date(timeIntervalSince1970: 1000)
        s.apply(st(playing: true, pos: 10, dur: 100), at: t0)
        XCTAssertEqual(s.interpolatedPosition(at: t0 + 5), 15, accuracy: 0.001)
        XCTAssertEqual(s.interpolatedPosition(at: t0 + 500), 100, accuracy: 0.001)
        XCTAssertEqual(s.interpolatedPosition(at: t0 - 50), 10, accuracy: 0.001)
        s.apply(st(playing: false, pos: 10, dur: 100), at: t0)
        XCTAssertEqual(s.interpolatedPosition(at: t0 + 5), 10, accuracy: 0.001)
        XCTAssertEqual(PlayerState().interpolatedPosition(at: t0), 0)
    }

    func testBridgeVersionFromReady() {
        let s = PlayerState()
        XCTAssertNil(s.bridgeVersion)
        s.apply(.ready(bridgeVersion: "3"))
        XCTAssertEqual(s.bridgeVersion, "3")
    }

    func testHealth() {
        let s = PlayerState()
        s.apply(.error(code: "c", message: "boom"))
        XCTAssertFalse(s.bridgeHealthy); XCTAssertEqual(s.lastError, "boom")
        s.apply(.ready(bridgeVersion: "1"))
        XCTAssertTrue(s.bridgeHealthy); XCTAssertNil(s.lastError)
        s.apply(.error(code: "c", message: nil)); XCTAssertFalse(s.bridgeHealthy)
        s.apply(st()); XCTAssertTrue(s.bridgeHealthy)
    }

    func testCommandScripts() {
        XCTAssertEqual(PlayerCommand.seek(12.5).script, "window.__amzBridge.seek(12.5)")
        XCTAssertNil(PlayerCommand.seek(.nan).script)
    }

    func testSkipCommandScriptsAwaitAndReturnJSON() {
        XCTAssertEqual(PlayerCommand.next.asyncBody, "return JSON.stringify(await window.__amzBridge.next());")
        XCTAssertEqual(PlayerCommand.previous.asyncBody, "return JSON.stringify(await window.__amzBridge.previous());")
        XCTAssertNil(PlayerCommand.seek(.infinity).asyncBody)
    }

    func testCommandResultParsing() {
        let ok = CommandResult.parse(#"{"ok":true,"via":"mediaSession","changed":true}"#)
        XCTAssertEqual(ok, CommandResult(ok: true, via: "mediaSession", reason: nil, changed: true))
        let bad = CommandResult.parse(#"{"ok":false,"reason":"no_nexttrack_control"}"#)
        XCTAssertFalse(bad.ok); XCTAssertEqual(bad.reason, "no_nexttrack_control")
        // Anything that is not the expected JSON string is a failure, never a silent success.
        XCTAssertFalse(CommandResult.parse(nil).ok)
        XCTAssertFalse(CommandResult.parse(["ok": true]).ok)
        XCTAssertFalse(CommandResult.parse("garbage").ok)
        XCTAssertEqual(CommandResult.parse("garbage").reason, "unparseable_result")
    }
}
