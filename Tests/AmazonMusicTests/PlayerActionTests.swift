import Testing
import Foundation
import AppKit
@testable import AmazonMusic

@Suite struct PlayerActionTests {
    @Test func testRawValuesUnique() {
        let raws = PlayerAction.allCases.map(\.rawValue)
        #expect(Set(raws).count == raws.count)
        #expect(PlayerAction.repeatMode.rawValue == "repeat")
    }
    @Test func testCommandMapping() {
        let expected: [PlayerAction: PlayerCommand] = [
            .play: .play, .pause: .pause, .toggle: .toggle, .next: .next, .previous: .previous,
            .like: .toggleLike, .shuffle: .toggleShuffle, .repeatMode: .cycleRepeat, .similar: .playSimilar,
        ]
        #expect(Set(expected.keys) == Set(PlayerAction.allCases))
        for (a, c) in expected { #expect(a.command == c, "\(a.rawValue)") }
    }
    @Test func testSymbolsAndTitles() {
        for a in PlayerAction.allCases {
            #expect(!(a.title.isEmpty))
            #expect(!(a.systemImage.isEmpty))
            #expect(NSImage(systemSymbolName: a.systemImage, accessibilityDescription: nil) != nil, "\(a.systemImage)")
            #expect(a.urlName == a.rawValue)
        }
    }
}
