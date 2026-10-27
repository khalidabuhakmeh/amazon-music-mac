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
        let track = player.bridgeHealthy ? player.track : nil
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                if let track {
                    MiniTitleBlock(track: track)
                } else {
                    MiniPlaceholderText()
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
        .frame(width: Self.width)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Nothing playing").font(.system(size: 19, weight: .semibold))
                .lineLimit(2)
            Text("Open the main window to sign in").font(.system(size: 14)).foregroundStyle(.primary.opacity(0.65))
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
