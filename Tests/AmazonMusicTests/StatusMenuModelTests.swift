import XCTest
@testable import AmazonMusic

final class StatusMenuModelTests: XCTestCase {
    func testLayoutWhenPaused() {
        let m = StatusMenuModel.build(isPlaying: false)
        XCTAssertEqual(m.map(\.title), ["Play", "Next", "Previous", "", "Open Amazon Music", "Settings…", "", "Quit Amazon Music"])
        XCTAssertTrue(m[3].isSeparator); XCTAssertTrue(m[6].isSeparator)
        XCTAssertEqual(m.last?.action, .quit); XCTAssertEqual(m.last?.keyEquivalent, "q")
    }
    func testLikeItemTitleMatchesState() {
        let unliked = StatusMenuModel.build(isPlaying: false, isLiked: false)
        XCTAssertEqual(unliked[3].title, "Like"); XCTAssertEqual(unliked[3].action, .toggleLike)
        XCTAssertEqual(StatusMenuModel.build(isPlaying: false, isLiked: true)[3].title, "Unlike")
        XCTAssertFalse(StatusMenuModel.build(isPlaying: false, isLiked: nil).contains { $0.action == .toggleLike })
    }
    func testPlayingShowsPause() {
        XCTAssertEqual(StatusMenuModel.build(isPlaying: true)[0].title, "Pause")
        XCTAssertEqual(StatusMenuModel.build(isPlaying: true)[0].action, .playPause)
    }
    func testShuffleAndRepeatItemsMatchState() {
        let off = StatusMenuModel.build(isPlaying: false, isShuffled: false, repeatMode: .off)
        XCTAssertEqual(off[3].title, "Turn Shuffle On"); XCTAssertEqual(off[3].action, .toggleShuffle)
        XCTAssertEqual(off[4].title, "Repeat All"); XCTAssertEqual(off[4].action, .cycleRepeat)
        let on = StatusMenuModel.build(isPlaying: false, isLiked: true, isShuffled: true, repeatMode: .one)
        XCTAssertEqual(on.map(\.title).prefix(6), ["Play", "Next", "Previous", "Unlike", "Turn Shuffle Off", "Turn Repeat Off"])
        XCTAssertEqual(StatusMenuModel.build(isPlaying: false, repeatMode: .all)[3].title, "Repeat One")
        let none = StatusMenuModel.build(isPlaying: false)
        XCTAssertFalse(none.contains { $0.action == .toggleShuffle || $0.action == .cycleRepeat })
    }
}
