import SwiftUI

/// Pure description of the Controls and Navigation menus (plain values in/out, unit-testable).
enum ControlsMenuModel {
    enum Action: Equatable, Sendable {
        case playPause, next, previous, like, shuffle, cycleRepeat, playSimilar
        case back, forward, reload, home
    }
    enum Key: Equatable, Sendable { case char(Character), left, right }
    struct Shortcut: Equatable, Sendable {
        var key: Key
        var command = true, option = false, shift = false
        /// Human-readable, e.g. "⌥⌘S".
        var display: String {
            let k: String = switch key { case .char(let c): String(c).uppercased(); case .left: "←"; case .right: "→" }
            return (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + k
        }
    }
    struct Item: Equatable, Sendable {
        var action: Action
        var title: String
        var enabled: Bool
        var checked = false
        var shortcut: Shortcut
    }

    struct PlayerInput: Equatable, Sendable {
        var hasTrack: Bool, isPlaying: Bool, bridgeHealthy: Bool
        var liked: Bool?, shuffled: Bool?, repeatMode: RepeatMode?, canPlaySimilar: Bool
    }

    static func controls(_ i: PlayerInput) -> [Item] {
        let live = i.bridgeHealthy
        let track = live && i.hasTrack
        let rep: String = switch i.repeatMode { case .all: "Repeat: All"; case .one: "Repeat: One"; default: "Repeat: Off" }
        return [
            Item(action: .playPause, title: i.isPlaying ? "Pause" : "Play", enabled: track, shortcut: .init(key: .char("p"))),
            Item(action: .next, title: PlayerAction.next.title, enabled: track, shortcut: .init(key: .right)),
            Item(action: .previous, title: PlayerAction.previous.title, enabled: track, shortcut: .init(key: .left)),
            Item(action: .like, title: i.liked == true ? "Unlike" : "Like", enabled: track && i.liked != nil, shortcut: .init(key: .char("l"))),
            Item(action: .shuffle, title: PlayerAction.shuffle.title, enabled: track && i.shuffled != nil, checked: i.shuffled == true,
                 shortcut: .init(key: .char("s"), option: true)),
            Item(action: .cycleRepeat, title: rep, enabled: track && i.repeatMode != nil, checked: i.repeatMode.map { $0 != .off } ?? false,
                 shortcut: .init(key: .char("r"), option: true)),
            Item(action: .playSimilar, title: PlayerAction.similar.title, enabled: track && i.canPlaySimilar, shortcut: .init(key: .char("s"), shift: true)),
        ]
    }

    static func navigation(canGoBack: Bool, canGoForward: Bool) -> [Item] {
        [
            Item(action: .back, title: "Back", enabled: canGoBack, shortcut: .init(key: .char("["))),
            Item(action: .forward, title: "Forward", enabled: canGoForward, shortcut: .init(key: .char("]"))),
            Item(action: .reload, title: "Reload", enabled: true, shortcut: .init(key: .char("r"))),
            Item(action: .home, title: "Home", enabled: true, shortcut: .init(key: .char("h"), shift: true)),
        ]
    }
}

extension ControlsMenuModel.Shortcut {
    var keyEquivalent: KeyEquivalent {
        switch key { case .char(let c): KeyEquivalent(c); case .left: .leftArrow; case .right: .rightArrow }
    }
    var modifiers: EventModifiers {
        var m: EventModifiers = []
        if command { m.insert(.command) }; if option { m.insert(.option) }; if shift { m.insert(.shift) }
        return m
    }
}

struct PlayerCommands: Commands {
    let player: PlayerState
    let bridge: PlayerBridge
    let web: WebController

    private var input: ControlsMenuModel.PlayerInput {
        .init(hasTrack: player.track != nil, isPlaying: player.isPlaying, bridgeHealthy: player.bridgeHealthy,
              liked: player.isLiked, shuffled: player.isShuffled, repeatMode: player.repeatMode, canPlaySimilar: player.canPlaySimilar)
    }

    private func send(_ c: PlayerCommand) { Task { await bridge.send(c) } }

    private func perform(_ a: ControlsMenuModel.Action) {
        switch a {
        case .playPause: send(.toggle)
        case .next: send(.next)
        case .previous: send(.previous)
        case .like: send(.toggleLike)
        case .shuffle: send(.toggleShuffle)
        case .cycleRepeat: send(.cycleRepeat)
        case .playSimilar: send(.playSimilar)
        case .back: web.goBack()
        case .forward: web.goForward()
        case .reload: web.reload()
        case .home: web.goHome()
        }
    }

    @ViewBuilder private func button(_ item: ControlsMenuModel.Item) -> some View {
        let b = Button(item.title) { perform(item.action) }
            .keyboardShortcut(item.shortcut.keyEquivalent, modifiers: item.shortcut.modifiers)
            .disabled(!item.enabled)
        if item.checked { Toggle(item.title, isOn: .constant(true)).keyboardShortcut(item.shortcut.keyEquivalent, modifiers: item.shortcut.modifiers).disabled(!item.enabled) } else { b }
    }

    var body: some Commands {
        CommandGroup(replacing: .printItem) {} // frees ⌘P
        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(ControlsMenuModel.navigation(canGoBack: web.canGoBack, canGoForward: web.canGoForward), id: \.title) { button($0) }
        }
        CommandMenu("Controls") {
            let items = ControlsMenuModel.controls(input)
            ForEach(items.prefix(3), id: \.title) { button($0) }
            Divider()
            ForEach(items.dropFirst(3), id: \.title) { button($0) }
            #if DEBUG
            Divider()
            Button("Seek +10s") {
                Task { await bridge.send(.seek(player.interpolatedPosition(at: Date()) + 10)) }
            }
            #endif
        }
    }
}
