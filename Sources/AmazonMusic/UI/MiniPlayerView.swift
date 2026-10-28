import AppKit
import SwiftUI

struct MiniPlayerView: View {
    /// Test/preview seams (default off): inject a cover image and force the hover state.
    var coverOverride: NSImage?
    var forceHover = false
    @Environment(PlayerState.self) private var player
    @Environment(PlayerBridge.self) private var bridge

    static let width: CGFloat = 340
    private static let padding: CGFloat = 14

    var body: some View {
        let track = player.popoverMode == .track ? player.track : nil
        VStack(spacing: 0) {
        HStack(alignment: .center, spacing: 14) {
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
                        .buttonStyle(.link).font(.system(size: 12))
                        .frame(maxWidth: .infinity, minHeight: 14, alignment: .leading)
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
            UpNextSection(items: player.upNext)
        }
        }
        .frame(width: Self.width)
        .onAppear { Task { await bridge.send(.refreshQueue) } }
        .background {
            // MenuBarExtra's own material is very translucent; add an opaque-ish layer so text behind doesn't bleed through.
            ZStack {
                Rectangle().fill(.thickMaterial)
                Color(nsColor: .windowBackgroundColor).opacity(0.7)
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
            ControlSlot(symbol: mode == .one ? "repeat.1" : "repeat", size: 14,
                        tint: Self.toggleTint(on: mode.map { $0 != .off }), isOn: mode.map { $0 != .off } == true,
                        label: "Repeat", value: Self.repeatValue(mode), help: Self.repeatHelp(mode),
                        enabled: enabled && mode != nil) { Task { await bridge.cycleRepeat() } }
            ControlSlot(symbol: "backward.end.fill", size: 16, label: "Previous track", help: "Previous track",
                        enabled: enabled) { Task { await bridge.send(.previous) } }
            ControlSlot(symbol: player.isPlaying ? "pause.fill" : "play.fill", size: 20,
                        label: player.isPlaying ? "Pause" : "Play", help: player.isPlaying ? "Pause" : "Play",
                        enabled: enabled) { Task { await bridge.send(.toggle) } }
            ControlSlot(symbol: "forward.end.fill", size: 16, label: "Next track", help: "Next track",
                        enabled: enabled) { Task { await bridge.send(.next) } }
            ControlSlot(symbol: "shuffle", size: 14, tint: Self.toggleTint(on: shuffled), isOn: shuffled == true,
                        label: "Shuffle", value: shuffled.map { $0 ? "On" : "Off" },
                        help: shuffled == true ? "Shuffle: on (click to turn off)" : "Shuffle: off (click to turn on)",
                        enabled: enabled && shuffled != nil) { Task { await bridge.toggleShuffle() } }
        }
        .frame(maxWidth: .infinity)
    }

    /// On = accent at full opacity; off = primary at ~62%; unknown/disabled is dimmed further by ControlSlot.
    private static func toggleTint(on: Bool?) -> Color { on == true ? .accentColor : Color.primary.opacity(0.62) }
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

private struct UpNextSection: View {
    let items: [BridgeMessage.QueueItem]
    @AppStorage("upNextExpanded") private var expanded = false
    @Environment(PlayerState.self) private var player
    @Environment(PlayerBridge.self) private var bridge
    private static let rowHeight: CGFloat = 36
    private static let maxVisibleRows: CGFloat = 5.5

    /// Rows start their song when the page can jump to a queue entry; otherwise they behave as before (collapsed row toggles).
    private func playable(_ item: BridgeMessage.QueueItem) -> Bool { player.canJumpToQueueItem && item.id != nil }
    private func play(_ item: BridgeMessage.QueueItem) { if let id = item.id { Task { await bridge.playQueueItem(id) } } }

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.6)
            if expanded {
                header
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(UpNextRowKeys.keyed(items), id: \.key) { row in
                            UpNextRow(item: row.item, playable: playable(row.item), pending: player.isJumpPending(row.item.id)) { play(row.item) }
                                .frame(height: Self.rowHeight)
                        }
                    }
                }
                .frame(height: min(CGFloat(min(items.count, 10)) * Self.rowHeight, Self.rowHeight * Self.maxVisibleRows))
                .padding(.bottom, 6)
            } else if let first = items.first {
                // Collapsed: a preview of the next song; the whole row (song + chevron) only expands the list.
                Button { toggle() } label: {
                    HStack(spacing: 0) {
                        UpNextRow(item: first, showsLabel: true)
                        chevron.frame(width: 42, height: 44)
                    }
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show upcoming songs")
                .accessibilityLabel("Up next: \(first.title)\(first.artist.map { " by \($0)" } ?? "")")
                .accessibilityValue("Collapsed")
                .accessibilityHint("Shows the upcoming songs")
            }
        }
    }

    private var header: some View {
        Button { toggle() } label: {
            HStack {
                Text("Up Next").font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary.opacity(0.65))
                Spacer()
                chevron
            }
            .padding(.horizontal, 14).frame(height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Hide upcoming songs")
        .accessibilityLabel("Up Next")
        .accessibilityValue("Expanded")
        .accessibilityHint("Hides the upcoming songs")
    }

    private var chevron: some View {
        Image(systemName: expanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.primary.opacity(0.6))
    }

    private func toggle() { withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() } }
}

/// One upcoming song. When `playable` (expanded list), the whole row is a button that plays it (hover highlight + play icon
/// on the artwork, "Play <title>" tooltip, spinner on the artwork while `pending`). `showsLabel` marks the collapsed preview
/// row, which is never playable: its parent button only expands the list.
private struct UpNextRow: View {
    let item: BridgeMessage.QueueItem
    var showsLabel = false
    var playable = false
    var pending = false
    var onPlay: () -> Void = {}
    @State private var image: NSImage?
    @State private var hovering = false

    var body: some View {
        let content = HStack(spacing: 10) {
            ZStack {
                Group {
                    if let image { Image(nsImage: image).resizable().scaledToFill() }
                    else { ZStack { Rectangle().fill(.quaternary); Image(systemName: "music.note").font(.system(size: 11)).foregroundStyle(.secondary) } }
                }
                // Hover/pending feedback lives on the artwork (like Music.app), not as a trailing glyph next to the chevron.
                if pending {
                    Rectangle().fill(.black.opacity(0.5))
                    ProgressView().controlSize(.mini).tint(.white)
                } else if playable && hovering {
                    Rectangle().fill(.black.opacity(0.45))
                    Image(systemName: "play.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail)
                if let artist = item.artist {
                    Text(artist).font(.system(size: 11)).foregroundStyle(.primary.opacity(0.65)).lineLimit(1).truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Collapsed: artwork aligns with the title column above (14pt), chevron button supplies the trailing edge.
        .padding(.leading, 14)
        .padding(.trailing, showsLabel ? 0 : 14)
        .frame(maxHeight: .infinity)
        .background {
            // Expanded list rows get a subtle inset highlight; the collapsed row relies on the artwork overlay only.
            if !showsLabel {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(playable && hovering && !pending ? 0.07 : 0))
                    .padding(.horizontal, 6).padding(.vertical, 2)
            }
        }
        .opacity(pending ? 0.7 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .task(id: item.artworkURL) {
            // Keep the previous image until the new one loads (no flicker when the queue shifts); clear only if there is no artwork.
            guard let url = item.artworkURL else { image = nil; return }
            if let loaded = await ArtworkCache.shared.image(for: url) { image = loaded }
        }
        if playable {
            Button(action: onPlay) { content }
                .buttonStyle(.plain)
                .disabled(pending)
                .help("Play \(item.title)")
                .accessibilityLabel("Play \(item.title)")
                .accessibilityValue(pending ? "Starting" : "")
                .accessibilityHint("Skips to this song")
        } else {
            content
        }
    }
}

/// A fixed-size hit target that shares the row width equally with its siblings.
private struct ControlSlot: View {
    let symbol: String
    let size: CGFloat
    var tint: Color = .primary
    var isOn = false
    let label: String
    var value: String?
    let help: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, minHeight: 30)
                .overlay(alignment: .bottom) {
                    // State indicator that doesn't rely on colour alone.
                    Circle().fill(Color.accentColor).frame(width: 4, height: 4).opacity(isOn ? 1 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .help(help)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
    }
}

/// Heart badge overlaid on the cover's bottom-right corner. Hidden when the page exposes no like control (isLiked == nil).
/// Liked: always visible, red. Not liked: white outline at ~55% opacity, full on hover.
private struct LikeBadge: View {
    let liked: Bool
    let hovering: Bool
    @Environment(PlayerBridge.self) private var bridge

    var body: some View {
        Button { Task { await bridge.toggleLike() } } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(liked ? Color.red : Color.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.black.opacity(0.5)))
                .background(Circle().fill(.ultraThinMaterial))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(liked || hovering ? 1 : 0.7)
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .help(liked ? "Unlike" : "Like")
        .accessibilityLabel(liked ? "Unlike" : "Like")
        .accessibilityValue(liked ? "Liked" : "Not liked")
        .accessibilityAddTraits(.isButton)
    }
}

/// "Play Similar Music" badge on the cover's top-left corner, the mirror of `LikeBadge` (same size, backing, padding, hover treatment).
/// Shown only when a track is loaded and the page says the action is available. Spinner while it runs.
private struct SimilarBadge: View {
    let hovering: Bool
    @Environment(PlayerState.self) private var player
    @Environment(PlayerBridge.self) private var bridge

    var body: some View {
        let busy = player.similarPending != nil
        Button { Task { await bridge.playSimilar() } } label: {
            Group {
                if busy { ProgressView().controlSize(.small).tint(.white).colorScheme(.dark) }
                else { Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.white) }
            }
            .frame(width: 30, height: 30)
            .background(Circle().fill(.black.opacity(0.5)))
            .background(Circle().fill(.ultraThinMaterial))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy || hovering ? 1 : 0.7)
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .help("Play Similar Music")
        .accessibilityLabel("Play Similar Music")
        .accessibilityValue(busy ? "Starting" : "")
        .accessibilityAddTraits(.isButton)
    }
}

/// Rounded cover with subtle border/shadow; placeholder glyph when there is no image.
private struct CoverView: View {
    let image: NSImage?
    static let size: CGFloat = 120

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "music.note").font(.system(size: 30)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
        .accessibilityHidden(true)
    }
}

/// Loads artwork for the track (via ArtworkCache); placeholder when nil. Hosts the like badge.
private struct CoverArt: View {
    let track: TrackInfo?
    var imageOverride: NSImage?
    var forceHover = false
    @Environment(PlayerState.self) private var player
    @Environment(PlayerBridge.self) private var bridge
    @State private var image: NSImage?
    @State private var hovering = false

    var body: some View {
        let liked = track == nil ? nil : player.isLiked
        CoverView(image: imageOverride ?? image)
            .overlay(alignment: .bottomTrailing) {
                if let liked {
                    LikeBadge(liked: liked, hovering: hovering || forceHover)
                        .padding(.trailing, 3).padding(.bottom, 3)
                }
            }
            .overlay(alignment: .topLeading) {
                if track != nil, player.canPlaySimilar {
                    SimilarBadge(hovering: hovering || forceHover)
                        .padding(.leading, 3).padding(.top, 3)
                }
            }
            .onHover { hovering = $0 }
            .onTapGesture(count: 2) {
                if liked != nil { Task { await bridge.toggleLike() } }
            }
            .task(id: track?.artworkURL) {
                image = nil
                guard let url = track?.artworkURL else { return }
                image = await ArtworkCache.shared.image(for: url)
            }
    }
}

private struct MiniPlaceholderText: View {
    /// Sign-in wording only when the page says the user is signed out; otherwise a hint to pick something to play.
    var signedOut = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Nothing playing").font(.system(size: 19, weight: .semibold))
                .lineLimit(2)
            Text(signedOut ? "Open the main window to sign in" : "Pick something to play in Amazon Music").font(.system(size: 14)).foregroundStyle(.primary.opacity(0.65))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct MiniTitleBlock: View {
    let track: TrackInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track.title ?? "Unknown title")
                .font(.system(size: 19, weight: .semibold))
                .lineLimit(2).truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            Text(track.artist ?? "")
                .font(.system(size: 14)).foregroundStyle(.primary.opacity(0.65))
                .lineLimit(1).truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Custom scrubber (6pt track, knob on hover/drag). Only this view re-renders on the timeline;
/// the schedule is paused while not playing or while scrubbing.
private struct MiniProgress: View {
    let track: TrackInfo
    @Environment(PlayerState.self) private var player
    @Environment(PlayerBridge.self) private var bridge
    @State private var scrub: Double?
    @State private var barHover = false

    var body: some View {
        let duration = max(track.duration ?? 0, 0)
        TimelineView(.animation(minimumInterval: 0.5, paused: !player.isPlaying || scrub != nil)) { ctx in
            let pos = min(scrub ?? player.interpolatedPosition(at: ctx.date), duration > 0 ? duration : .infinity)
            HStack(spacing: 6) {
                Text(Self.format(pos)).frame(minWidth: 28, alignment: .leading)
                bar(pos: pos, duration: duration)
                Text(duration > 0 ? "-" + Self.format(max(0, duration - pos)) : "--:--")
                    .frame(minWidth: 28, alignment: .trailing)
            }
            .font(.system(size: 10).monospacedDigit()).foregroundStyle(.primary.opacity(0.7))
        }
    }

    private func bar(pos: Double, duration: Double) -> some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let frac = duration > 0 ? CGFloat(min(max(pos / duration, 0), 1)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.3)).frame(height: 6)
                Capsule().fill(Color.primary).frame(width: w * frac, height: 6)
                Circle().fill(Color.primary).frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    .offset(x: min(max(w * frac - 6, 0), w - 12))
                    .opacity(barHover || scrub != nil ? 1 : 0)
            }
            .onHover { barHover = $0 }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard duration > 0 else { return }
                    scrub = Double(min(max(g.location.x / w, 0), 1)) * duration
                }
                .onEnded { g in
                    guard duration > 0 else { scrub = nil; return }
                    let v = Double(min(max(g.location.x / w, 0), 1)) * duration
                    scrub = v
                    Task { await bridge.send(.seek(v)); scrub = nil }
                })
        }
        .frame(height: 14)
        .disabled(duration <= 0)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Self.format(pos)) of \(Self.format(duration))")
        .accessibilityAdjustableAction { dir in
            guard duration > 0 else { return }
            let delta = dir == .increment ? 10.0 : -10.0
            let v = min(max(pos + delta, 0), duration)
            Task { await bridge.send(.seek(v)) }
        }
    }

    static func format(_ s: Double) -> String {
        let t = Int(s.isFinite ? max(0, s) : 0)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

#if DEBUG
@MainActor private func previewModel(track: Bool, playing: Bool, liked: Bool? = nil,
                                  shuffle: Bool? = nil, repeatMode: RepeatMode? = nil, title: String = "A Fairly Long Track Title That Wraps To Two Lines") -> (PlayerState, PlayerBridge) {
    let s = PlayerState()
    if track {
        s.apply(.state(.init(trackId: "t1", title: title, artist: "Some Artist",
                             album: "Album", artworkURL: nil, duration: 245, position: 83, isPlaying: playing, liked: liked, shuffle: shuffle, repeatMode: repeatMode)))
    } else {
        s.markUnhealthy("preview")
    }
    return (s, PlayerBridge(state: s))
}

#Preview("Up Next (collapsed/expanded persisted state)") {
    let (s, b) = previewModel(track: true, playing: true, liked: false, shuffle: false, repeatMode: .off)
    s.apply(.state(.init(trackId: "t1", title: "Now", artist: "Artist", album: "A", artworkURL: nil, duration: 245, position: 83, isPlaying: true,
                         queue: (1...10).map { .init(title: "Upcoming song \($0)", artist: "Artist \($0)", artworkURL: nil) })))
    return MiniPlayerView().environment(s).environment(b)
}
#Preview("Playing, shuffle on, repeat all") {
    let (s, b) = previewModel(track: true, playing: true, liked: false, shuffle: true, repeatMode: .all)
    MiniPlayerView().environment(s).environment(b)
}
#Preview("Repeat one") {
    let (s, b) = previewModel(track: true, playing: true, liked: true, shuffle: false, repeatMode: .one, title: "Short Title")
    MiniPlayerView().environment(s).environment(b)
}
#Preview("Playing") {
    let (s, b) = previewModel(track: true, playing: true)
    MiniPlayerView().environment(s).environment(b)
}
#Preview("Liked unknown / long title") {
    let (s, b) = previewModel(track: true, playing: true, liked: nil)
    MiniPlayerView().environment(s).environment(b)
}
#Preview("Liked") {
    let (s, b) = previewModel(track: true, playing: true, liked: true)
    MiniPlayerView().environment(s).environment(b)
}
#Preview("Paused") {
    let (s, b) = previewModel(track: true, playing: false, liked: false, shuffle: false, repeatMode: .off)
    MiniPlayerView().environment(s).environment(b)
}
#Preview("Heart overlay: liked / not liked") {
    let a = previewModel(track: true, playing: true, liked: true)
    let b = previewModel(track: true, playing: true, liked: false)
    VStack(spacing: 0) {
        MiniPlayerView().environment(a.0).environment(a.1)
        MiniPlayerView(forceHover: true).environment(b.0).environment(b.1)
        MiniPlayerView().environment(b.0).environment(b.1)
    }
}
#Preview("No track") {
    let (s, b) = previewModel(track: false, playing: false)
    MiniPlayerView().environment(s).environment(b)
}
#endif
