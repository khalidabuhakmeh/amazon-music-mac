import Testing
import Foundation
@testable import AmazonMusic

@Suite struct DockMenuModelTests {
    @Test func testNotPlaying() {
        let m = DockMenuModel.build(track: nil, isPlaying: false)
        #expect(m[0].title == "Not playing"); #expect(!(m[0].enabled))
        #expect(m[1].isSeparator)
        #expect(m.map(\.title).suffix(3) == ["Play", "Next", "Previous"])
        #expect(m.suffix(3).allSatisfy { $0.enabled })
    }
    @Test func testPlayingShowsPause() {
        let m = DockMenuModel.build(track: TrackInfo(title: "T", artist: "A"), isPlaying: true)
        #expect(m[0].title == "T — A"); #expect(!(m[0].enabled))
        #expect(m[2].title == "Pause"); #expect(m[2].action == .playPause)
        #expect(m[3].action == .next); #expect(m[4].action == .previous)
    }
    @Test func testTitleOnly() {
        #expect(DockMenuModel.build(track: TrackInfo(title: "T"), isPlaying: false)[0].title == "T")
    }
}
