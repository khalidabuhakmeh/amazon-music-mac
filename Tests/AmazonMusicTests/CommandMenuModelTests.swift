import Testing
@testable import AmazonMusic

struct CommandMenuModelTests {
    typealias M = ControlsMenuModel
    func input(track: Bool = true, playing: Bool = false, healthy: Bool = true, liked: Bool? = false,
               shuffle: Bool? = false, rep: RepeatMode? = .off, similar: Bool = true) -> M.PlayerInput {
        .init(hasTrack: track, isPlaying: playing, bridgeHealthy: healthy, liked: liked, shuffled: shuffle, repeatMode: rep, canPlaySimilar: similar)
    }
    func item(_ a: M.Action, _ i: M.PlayerInput) -> M.Item { M.controls(i).first { $0.action == a }! }

    @Test func noTrackDisablesEverything() {
        let items = M.controls(input(track: false, liked: nil, shuffle: nil, rep: nil, similar: false))
        #expect(items.allSatisfy { !$0.enabled })
        #expect(items[0].title == "Play")
    }
    @Test func unhealthyBridgeDisables() {
        #expect(M.controls(input(healthy: false)).allSatisfy { !$0.enabled })
    }
    @Test func playingAndPaused() {
        #expect(item(.playPause, input(playing: true)).title == "Pause")
        #expect(item(.playPause, input(playing: false)).title == "Play")
        #expect(item(.playPause, input()).enabled)
    }
    @Test func likedTitle() {
        #expect(item(.like, input(liked: true)).title == "Unlike")
        #expect(item(.like, input(liked: false)).title == "Like")
        #expect(!item(.like, input(liked: nil)).enabled)
    }
    @Test func repeatTitles() {
        #expect(item(.cycleRepeat, input(rep: .off)).title == "Repeat: Off")
        #expect(item(.cycleRepeat, input(rep: .all)).title == "Repeat: All")
        #expect(item(.cycleRepeat, input(rep: .one)).title == "Repeat: One")
        #expect(item(.cycleRepeat, input(rep: .one)).checked)
    }
    @Test func shuffleChecked() {
        #expect(item(.shuffle, input(shuffle: true)).checked)
        #expect(!item(.shuffle, input(shuffle: false)).checked)
    }
    @Test func shortcuts() {
        let d = M.controls(input()).map(\.shortcut.display)
        #expect(d == ["⌘P", "⌘→", "⌘←", "⌘L", "⌥⌘S", "⌥⌘R", "⇧⌘S"])
        #expect(M.navigation(canGoBack: true, canGoForward: true).map(\.shortcut.display) == ["⌘[", "⌘]", "⌘R", "⇧⌘H"])
    }
    @Test func navigationEnablement() {
        let n = M.navigation(canGoBack: false, canGoForward: true)
        #expect(!n[0].enabled && n[1].enabled && n[2].enabled && n[3].enabled)
    }
    @Test func noDuplicateShortcuts() {
        let all = M.controls(input()) + M.navigation(canGoBack: true, canGoForward: true)
        #expect(Set(all.map(\.shortcut.display)).count == all.count)
    }
}
