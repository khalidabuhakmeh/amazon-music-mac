import AppKit
import SwiftUI

struct MiniPlayerView: View {
    /// Test/preview seams (default off): inject a cover image and force the hover state.
    var coverOverride: NSImage?
    var forceHover = false
    /// Forces Up Next expanded/collapsed (snapshots/previews) instead of the stored preference.
    var upNextExpanded: Bool?
    @Environment(PlayerState.self) private var player
    @Environment(PlayerBridge.self) private var bridge

    static let width: CGFloat = 340
    private static let padding: CGFloat = Space.l

    var body: some View {
        let track = player.popoverMode == .track ? player.track : nil
        VStack(spacing: 0) {
        HStack(alignment: .center, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 0) {
                if let track {
                    MiniTitleBlock(track: track)
                } else {
                    MiniPlaceholderText(signedOut: player.popoverMode == .signedOut)
                }
                Spacer(minLength: 4)
                if let track {
                    MiniProgress(track: track)
                } else {
                    Button("Open Amazon Music") { MainWindowCoordinator.shared.open() }
                        .buttonStyle(.link).font(.callout)
                        .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
                }
                Spacer(minLength: 4)
                controls(enabled: track != nil)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(height: CoverView.size)

            CoverArt(track: track, imageOverride: coverOverride, forceHover: forceHover)
        }
        .padding(.horizontal, Self.padding)
        .padding(.vertical, Self.padding)
        if track != nil, !player.upNext.isEmpty {
            UpNextSection(items: player.upNext, expandedOverride: upNextExpanded)
        }
        }
        .frame(width: Self.width)
        .onAppear { Task { await bridge.send(.refreshQueue) } }
        .background {
            // MenuBarExtra's own material is very translucent; add an opaque-ish layer so text behind doesn't bleed through.
            ZStack {
                Rectangle().fill(.thickMaterial)
                Color(nsColor: .windowBackgroundColor).opacity(Surface.dim)
            }
            .ignoresSafeArea()
        }
    }

    /// One row of five evenly spread slots, like Amazon Music's own player bar:
    /// repeat, previous, play/pause, next, shuffle. Solid glyphs, semibold.
    private func controls(enabled: Bool) -> some View {
        let shuffled = player.isShuffled
        let mode = player.repeatMode
        return HStack(spacing: 0) {
            ControlSlot(symbol: mode == .one ? "repeat.1" : "repeat", size: Glyph.control,
                        tint: Self.toggleTint(on: mode.map { $0 != .off }), isOn: mode.map { $0 != .off } == true,
                        label: "Repeat", value: Self.repeatValue(mode), help: Self.repeatHelp(mode),
                        enabled: enabled && mode != nil) { Task { await bridge.cycleRepeat() } }
            ControlSlot(symbol: "backward.end.fill", size: Glyph.skip, label: "Previous track", help: "Previous track",
                        enabled: enabled) { Task { await bridge.send(.previous) } }
            ControlSlot(symbol: player.isPlaying ? "pause.fill" : "play.fill", size: Glyph.play,
                        label: player.isPlaying ? "Pause" : "Play", help: player.isPlaying ? "Pause" : "Play",
                        enabled: enabled) { Task { await bridge.send(.toggle) } }
            ControlSlot(symbol: "forward.end.fill", size: Glyph.skip, label: "Next track", help: "Next track",
                        enabled: enabled) { Task { await bridge.send(.next) } }
            ControlSlot(symbol: "shuffle", size: Glyph.control, tint: Self.toggleTint(on: shuffled), isOn: shuffled == true,
                        label: "Shuffle", value: shuffled.map { $0 ? "On" : "Off" },
                        help: shuffled == true ? "Shuffle: on (click to turn off)" : "Shuffle: off (click to turn on)",
                        enabled: enabled && shuffled != nil) { Task { await bridge.toggleShuffle() } }
        }
        .frame(maxWidth: .infinity)
    }

    /// On = accent at full opacity; off = primary at ~62%; unknown/disabled is dimmed further by ControlSlot.
    private static func toggleTint(on: Bool?) -> Color { on == true ? .accentColor : Color.primary.opacity(Surface.secondaryText) }
    private static func repeatValue(_ m: RepeatMode?) -> String? { m.map { ["off": "Off", "all": "All", "one": "One"][$0.rawValue] ?? "" } }
    private static func repeatHelp(_ m: RepeatMode?) -> String {
        switch m {
        case .some(.off), .none: "Repeat: off (click to repeat all)"
        case .some(.all): "Repeat: all (click to repeat one)"
        case .some(.one): "Repeat: one (click to turn off)"
        }
    }
}

/// Collapsible "Up Next" queue at the bottom of the popover. Collapsed: the very next song in one row with a chevron.
/// Expanded: header + up to 10 upcoming songs (scrolls past ~5 rows). Expanded state persists (UserDefaults). Not shown without data.
/// Row identity for Up Next: the queue entry id (so a pending spinner stays with its song when the list shifts); position only as a fallback.
enum UpNextRowKeys {
    static func keyed(_ items: [BridgeMessage.QueueItem]) -> [(key: String, item: BridgeMessage.QueueItem)] {
        var seen = Set<String>()
        return items.prefix(10).enumerated().map { offset, item in
            var key = item.id ?? "pos-\(offset)"
            if !seen.insert(key).inserted { key = "pos-\(offset)-dup"; seen.insert(key) }
            return (key, item)
        }
    }
}

#if DEBUG
#Preview("Up Next expanded") { fixturePreview(.upNextExpanded) }
#Preview("Up Next collapsed") { fixturePreview(.upNextCollapsed) }
#Preview("Playing, shuffle on, repeat all") { fixturePreview(.shuffleRepeatAll) }
#Preview("Repeat one") { fixturePreview(.repeatOne) }
#Preview("Playing") { fixturePreview(.playing) }
#Preview("Liked unknown / long title") { fixturePreview(.likedUnknownLongTitle) }
#Preview("Liked") { fixturePreview(.liked) }
#Preview("Paused") { fixturePreview(.paused) }
#Preview("Heart overlay: liked / not liked") {
    let a = PlayerStateFixtures.liked.make()
    let b = PlayerStateFixtures.paused.make()
    VStack(spacing: 0) {
        MiniPlayerView().environment(a.0).environment(a.1)
        MiniPlayerView(forceHover: true).environment(b.0).environment(b.1)
        MiniPlayerView().environment(b.0).environment(b.1)
    }
}
#Preview("No track") { fixturePreview(.noTrack) }
#Preview("Bridge unhealthy") { fixturePreview(.bridgeUnhealthy) }

@MainActor private func fixturePreview(_ f: PlayerStateFixtures) -> some View {
    let (s, b) = f.make()
    return MiniPlayerView(upNextExpanded: f.upNextExpanded).environment(s).environment(b)
}
#endif
