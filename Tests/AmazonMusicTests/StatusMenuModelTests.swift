import Testing
import Foundation
@testable import AmazonMusic

@Suite struct StatusMenuModelTests {
    @Test func testLayoutWhenPaused() {
        let m = StatusMenuModel.build(isPlaying: false)
        #expect(m.map(\.title) == ["Play", "Next", "Previous", "", "Open Amazon Music", "Settings…", "", "Quit Amazon Music"])
        #expect(m[3].isSeparator); #expect(m[6].isSeparator)
        #expect(m.last?.action == .quit); #expect(m.last?.keyEquivalent == "q")
    }
    @Test func testLikeItemTitleMatchesState() {
        let unliked = StatusMenuModel.build(isPlaying: false, isLiked: false)
        #expect(unliked[3].title == "Like"); #expect(unliked[3].action == .toggleLike)
        #expect(StatusMenuModel.build(isPlaying: false, isLiked: true)[3].title == "Unlike")
        #expect(!(StatusMenuModel.build(isPlaying: false, isLiked: nil).contains { $0.action == .toggleLike }))
    }
    @Test func testPlayingShowsPause() {
        #expect(StatusMenuModel.build(isPlaying: true)[0].title == "Pause")
        #expect(StatusMenuModel.build(isPlaying: true)[0].action == .playPause)
    }
    @Test func testShuffleAndRepeatItemsMatchState() {
        let off = StatusMenuModel.build(isPlaying: false, isShuffled: false, repeatMode: .off)
        #expect(off[3].title == "Turn Shuffle On"); #expect(off[3].action == .toggleShuffle)
        #expect(off[4].title == "Repeat All"); #expect(off[4].action == .cycleRepeat)
        let on = StatusMenuModel.build(isPlaying: false, isLiked: true, isShuffled: true, repeatMode: .one)
        #expect(on.map(\.title).prefix(6) == ["Play", "Next", "Previous", "Unlike", "Turn Shuffle Off", "Turn Repeat Off"])
        #expect(StatusMenuModel.build(isPlaying: false, repeatMode: .all)[3].title == "Repeat One")
        let none = StatusMenuModel.build(isPlaying: false)
        #expect(!(none.contains { $0.action == .toggleShuffle || $0.action == .cycleRepeat }))
    }
    @Test func testPlaySimilarItemOnlyWhenAvailable() {
        #expect(!(StatusMenuModel.build(isPlaying: false).contains { $0.action == .playSimilar }))
        let m = StatusMenuModel.build(isPlaying: false, isLiked: true, isShuffled: false, repeatMode: .off, canPlaySimilar: true)
        #expect(m.map(\.title).prefix(7) == ["Play", "Next", "Previous", "Unlike", "Turn Shuffle On", "Repeat All", "Play Similar Music"])
        #expect(m[6].action == .playSimilar)
    }
}
