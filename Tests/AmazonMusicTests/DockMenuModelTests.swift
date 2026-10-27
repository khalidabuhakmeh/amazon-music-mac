import XCTest
@testable import AmazonMusic

final class DockMenuModelTests: XCTestCase {
    func testNotPlaying() {
        let m = DockMenuModel.build(track: nil, isPlaying: false)
        XCTAssertEqual(m[0].title, "Not playing"); XCTAssertFalse(m[0].enabled)
        XCTAssertTrue(m[1].isSeparator)
        XCTAssertEqual(m.map(\.title).suffix(3), ["Play", "Next", "Previous"])
        XCTAssertTrue(m.suffix(3).allSatisfy(\.enabled))
    }
    func testPlayingShowsPause() {
        let m = DockMenuModel.build(track: TrackInfo(title: "T", artist: "A"), isPlaying: true)
        XCTAssertEqual(m[0].title, "T — A"); XCTAssertFalse(m[0].enabled)
        XCTAssertEqual(m[2].title, "Pause"); XCTAssertEqual(m[2].action, .playPause)
        XCTAssertEqual(m[3].action, .next); XCTAssertEqual(m[4].action, .previous)
    }
    func testTitleOnly() {
        XCTAssertEqual(DockMenuModel.build(track: TrackInfo(title: "T"), isPlaying: false)[0].title, "T")
    }
}
