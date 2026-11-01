import XCTest
import AppKit
@testable import AmazonMusic

final class PlayerActionTests: XCTestCase {
    func testRawValuesUnique() {
        let raws = PlayerAction.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count)
        XCTAssertEqual(PlayerAction.repeatMode.rawValue, "repeat")
    }
    func testCommandMapping() {
        let expected: [PlayerAction: PlayerCommand] = [
            .play: .play, .pause: .pause, .toggle: .toggle, .next: .next, .previous: .previous,
            .like: .toggleLike, .shuffle: .toggleShuffle, .repeatMode: .cycleRepeat, .similar: .playSimilar,
        ]
        XCTAssertEqual(Set(expected.keys), Set(PlayerAction.allCases))
        for (a, c) in expected { XCTAssertEqual(a.command, c, a.rawValue) }
    }
    func testSymbolsAndTitles() {
        for a in PlayerAction.allCases {
            XCTAssertFalse(a.title.isEmpty)
            XCTAssertFalse(a.systemImage.isEmpty)
            XCTAssertNotNil(NSImage(systemSymbolName: a.systemImage, accessibilityDescription: nil), a.systemImage)
            XCTAssertEqual(a.urlName, a.rawValue)
        }
    }
}
