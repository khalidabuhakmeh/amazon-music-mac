import Testing
import Foundation
@testable import AmazonMusic

struct NowPlayingSnapshotTests {
    let track = TrackInfo(trackId: "t1", title: "Song", artist: "Artist", album: "Album",
                          artworkURL: URL(string: "https://example.com/a.jpg"), duration: 200)

    @Test func playing() {
        let s = NowPlayingSnapshot.make(track: track, isPlaying: true, bridgeHealthy: true, position: 42)
        #expect(s.playbackState == .playing)
        #expect(s.rate == 1)
        #expect(s.elapsed == 42)
        #expect(s.duration == 200)
        #expect(s.title == "Song" && s.artist == "Artist" && s.album == "Album")
    }

    @Test func paused() {
        let s = NowPlayingSnapshot.make(track: track, isPlaying: false, bridgeHealthy: true, position: 10)
        #expect(s.playbackState == .paused)
        #expect(s.rate == 0)
    }

    @Test func noTrackIsStopped() {
        let s = NowPlayingSnapshot.make(track: nil, isPlaying: true, bridgeHealthy: true, position: 5)
        #expect(s.playbackState == .stopped && s.isEmpty && s.title == nil)
    }

    @Test func unhealthyIsStopped() {
        let s = NowPlayingSnapshot.make(track: track, isPlaying: true, bridgeHealthy: false, position: 5)
        #expect(s.playbackState == .stopped && s.isEmpty)
    }

    @Test func clampsElapsedAndDuration() {
        var t = track; t.duration = 100
        #expect(NowPlayingSnapshot.make(track: t, isPlaying: true, bridgeHealthy: true, position: 500).elapsed == 100)
        #expect(NowPlayingSnapshot.make(track: t, isPlaying: true, bridgeHealthy: true, position: -3).elapsed == 0)
        t.duration = .infinity
        #expect(NowPlayingSnapshot.make(track: t, isPlaying: true, bridgeHealthy: true, position: 3).duration == nil)
    }

    @Test func modeDefaultIsOverride() {
        #expect(NowPlayingMode.default == .override)
    }
}
