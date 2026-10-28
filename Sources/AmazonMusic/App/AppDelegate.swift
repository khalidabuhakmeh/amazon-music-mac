import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// App.init runs before the delegate exists; it parks references here and the delegate picks them up.
    static var pending: (player: PlayerState, bridge: PlayerBridge)?
    var player: PlayerState? { Self.pending?.player }
    var bridge: PlayerBridge? { Self.pending?.bridge }

    private lazy var statusMenu = StatusItemMenuController(
        isPlaying: { [weak self] in self?.player?.isPlaying ?? false },
        isLiked: { [weak self] in self?.player?.isLiked },
        isShuffled: { [weak self] in self?.player?.isShuffled },
        repeatMode: { [weak self] in self?.player?.repeatMode },
        canPlaySimilar: { [weak self] in self?.player?.canPlaySimilar ?? false },
        perform: { [weak self] action in
            switch action {
            case .playPause: if let b = self?.bridge { Task { await b.send(.toggle) } }
            case .next: if let b = self?.bridge { Task { await b.send(.next) } }
            case .previous: if let b = self?.bridge { Task { await b.send(.previous) } }
            case .toggleLike: if let b = self?.bridge { Task { await b.toggleLike() } }
            case .toggleShuffle: if let b = self?.bridge { Task { await b.toggleShuffle() } }
            case .cycleRepeat: if let b = self?.bridge { Task { await b.cycleRepeat() } }
            case .playSimilar: if let b = self?.bridge { Task { await b.playSimilar() } }
            case .openApp: MainWindowCoordinator.shared.open()
            case .settings: NSApp.activate(); NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            case .quit: NSApp.terminate(nil)
            }
        })

    func applicationDidFinishLaunching(_ notification: Notification) { statusMenu.start() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // `flag` is unreliable: the invisible parking window counts as visible.
        _ = flag
        if !MainWindowCoordinator.shared.isMainWindowVisible { MainWindowCoordinator.shared.open() }
        return false // we handled it; suppress default (which could spawn a duplicate window)
    }

    // NSMenuItem.target is weak, so the delegate owns the target.
    private lazy var dockTarget = DockMenuTarget { [weak self] action in
        guard let bridge = self?.bridge else { return }
        let cmd: PlayerCommand = switch action {
        case .playPause: .toggle
        case .next: .next
        case .previous: .previous
        }
        Task { await bridge.send(cmd) }
    }

    /// Builds a fresh menu on every call.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let models = DockMenuModel.build(track: player?.track, isPlaying: player?.isPlaying ?? false)
        let menu = NSMenu()
        menu.autoenablesItems = false
        for m in models {
            if m.isSeparator { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: m.title, action: m.action == nil ? nil : #selector(DockMenuTarget.invoke(_:)), keyEquivalent: "")
            item.isEnabled = m.enabled
            if let a = m.action { item.target = dockTarget; item.representedObject = a.rawValue }
            menu.addItem(item)
        }
        return menu
    }
}
