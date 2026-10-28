import AppKit

enum StatusMenuAction: String, Sendable, Equatable {
    case playPause, next, previous, toggleLike, toggleShuffle, cycleRepeat, playSimilar, openApp, settings, quit
}

struct StatusMenuItemModel: Equatable, Sendable {
    var title: String
    var action: StatusMenuAction?   // nil => separator
    var keyEquivalent: String = ""
    var isSeparator: Bool { action == nil }
    static let separator = StatusMenuItemModel(title: "", action: nil)
}

/// Pure builder for the menu bar item's right-click menu.
enum StatusMenuModel {
    static func build(isPlaying: Bool, isLiked: Bool? = nil, isShuffled: Bool? = nil, repeatMode: RepeatMode? = nil, canPlaySimilar: Bool = false) -> [StatusMenuItemModel] {
        var items: [StatusMenuItemModel] = [
            .init(title: isPlaying ? "Pause" : "Play", action: .playPause),
            .init(title: "Next", action: .next),
            .init(title: "Previous", action: .previous),
        ]
        if let isLiked { items.append(.init(title: isLiked ? "Unlike" : "Like", action: .toggleLike)) }
        // Titles name what the click does (like Like/Unlike); items are absent when the page exposes no control.
        if let isShuffled { items.append(.init(title: isShuffled ? "Turn Shuffle Off" : "Turn Shuffle On", action: .toggleShuffle)) }
        if let repeatMode {
            let title = switch repeatMode.next { case .all: "Repeat All"; case .one: "Repeat One"; case .off: "Turn Repeat Off" }
            items.append(.init(title: title, action: .cycleRepeat))
        }
        if canPlaySimilar { items.append(.init(title: "Play Similar Music", action: .playSimilar)) }
        items += [
            .separator,
            .init(title: "Open Amazon Music", action: .openApp),
            .init(title: "Settings…", action: .settings, keyEquivalent: ","),
            .separator,
            .init(title: "Quit Amazon Music", action: .quit, keyEquivalent: "q"),
        ]
        return items
    }
}

/// Right-click menu for the MenuBarExtra (.window style) status item, public API only.
/// A local NSEvent monitor watches right-mouse-down events delivered to a window that hosts an
/// NSStatusBarButton, consumes them, and pops up a freshly built NSMenu. Left click is untouched.
@MainActor
final class StatusItemMenuController: NSObject {
    private var monitor: Any?
    private let isPlaying: () -> Bool
    private let isLiked: () -> Bool?
    private let isShuffled: () -> Bool?
    private let repeatMode: () -> RepeatMode?
    private let canPlaySimilar: () -> Bool
    private let perform: (StatusMenuAction) -> Void

    init(isPlaying: @escaping () -> Bool, isLiked: @escaping () -> Bool? = { nil },
         isShuffled: @escaping () -> Bool? = { nil }, repeatMode: @escaping () -> RepeatMode? = { nil }, canPlaySimilar: @escaping () -> Bool = { false }, perform: @escaping (StatusMenuAction) -> Void) {
        self.isPlaying = isPlaying
        self.isLiked = isLiked
        self.isShuffled = isShuffled
        self.repeatMode = repeatMode
        self.canPlaySimilar = canPlaySimilar
        self.perform = perform
        super.init()
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            // Local monitors run on the main thread.
            nonisolated(unsafe) let ev = event
            let handled: Bool = MainActor.assumeIsolated {
                guard let self, let button = Self.statusButton(in: ev.window) else { return false }
                self.popUp(from: button, event: ev)
                return true
            }
            return handled ? nil : event
        }
    }

    private static func statusButton(in window: NSWindow?) -> NSStatusBarButton? {
        guard let root = window?.contentView?.superview ?? window?.contentView else { return nil }
        return find(in: root)
    }
    private static func find(in view: NSView) -> NSStatusBarButton? {
        if let b = view as? NSStatusBarButton { return b }
        for s in view.subviews { if let b = find(in: s) { return b } }
        return nil
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for m in StatusMenuModel.build(isPlaying: isPlaying(), isLiked: isLiked(),
                                           isShuffled: isShuffled(), repeatMode: repeatMode(), canPlaySimilar: canPlaySimilar()) {
            guard let a = m.action else { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: m.title, action: #selector(invoke(_:)), keyEquivalent: m.keyEquivalent)
            item.target = self
            item.representedObject = a.rawValue
            menu.addItem(item)
        }
        return menu
    }

    private func popUp(from button: NSStatusBarButton, event: NSEvent) {
        NSMenu.popUpContextMenu(makeMenu(), with: event, for: button)
    }

    @objc private func invoke(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let a = StatusMenuAction(rawValue: raw) else { return }
        perform(a)
    }
}
