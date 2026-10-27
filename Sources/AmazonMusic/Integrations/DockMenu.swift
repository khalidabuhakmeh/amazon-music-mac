import AppKit

enum DockMenuAction: String, Sendable, Equatable {
    case playPause, next, previous
}

struct DockMenuItemModel: Equatable, Sendable {
    var id: String?          // nil for separators
    var title: String
    var enabled: Bool
    var action: DockMenuAction?
    var isSeparator: Bool { id == nil && title.isEmpty }

    static let separator = DockMenuItemModel(id: nil, title: "", enabled: false, action: nil)
}

enum DockMenuModel {
    static func build(track: TrackInfo?, isPlaying: Bool) -> [DockMenuItemModel] {
        let parts = [track?.title, track?.artist].compactMap { $0 }.filter { !$0.isEmpty }
        let header = parts.isEmpty ? "Not playing" : parts.joined(separator: " — ")
        return [
            .init(id: "nowPlaying", title: header, enabled: false, action: nil),
            .separator,
            .init(id: "playPause", title: isPlaying ? "Pause" : "Play", enabled: true, action: .playPause),
            .init(id: "next", title: "Next", enabled: true, action: .next),
            .init(id: "previous", title: "Previous", enabled: true, action: .previous),
        ]
    }
}

/// Target for menu items; forwards actions to a closure.
@MainActor
final class DockMenuTarget: NSObject {
    private let handler: (DockMenuAction) -> Void
    init(handler: @escaping (DockMenuAction) -> Void) { self.handler = handler }
    @objc func invoke(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let a = DockMenuAction(rawValue: raw) else { return }
        handler(a)
    }
}
