import AppKit
import SwiftUI

struct MiniPlayerView: View {
    @Environment(PlayerState.self) private var player
    @Environment(PlayerBridge.self) private var bridge
    @Environment(\.openSettings) private var openSettings

    static let width: CGFloat = 340
    private static let padding: CGFloat = 14

    private static let iconRow: CGFloat = 24

    var body: some View {
        let track = player.bridgeHealthy ? player.track : nil
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                LikeButton()
                FooterIconButton(systemName: "arrow.up.forward.app", label: "Open Amazon Music") {
                    MainWindowCoordinator.shared.open()
                }
                FooterIconButton(systemName: "gearshape", label: "Settings") {
                    NSApp.activate(); openSettings()
                }
            }
            .frame(height: Self.iconRow)
            .padding(.trailing, -7) // glyph edge aligns with the cover's right edge

            HStack(alignment: .top, spacing: 14) {
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
                        Color.clear.frame(height: 14)
                    }
                    Spacer(minLength: 4)
                    controls(enabled: track != nil)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .frame(height: CoverView.size)

                CoverArt(track: track)
            }
        }
        .padding(.horizontal, Self.padding)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .frame(width: Self.width)
    }

    /// One row of five evenly spread slots, like Amazon Music's own player bar:
    /// repeat, previous, play/pause, next, shuffle. Solid glyphs, semibold.
    private func controls(enabled: Bool) -> some View {
        let shuffled = player.isShuffled
        let mode = player.repeatMode
        return HStack(spacing: 0) {
            ControlSlot(symbol: mode == .one ? "repeat.1" : "repeat", size: 14,
                        tint: Self.toggleTint(on: mode.map { $0 != .off }),
                        label: "Repeat", value: Self.repeatValue(mode), help: Self.repeatHelp(mode),
                        enabled: enabled && mode != nil) { Task { await bridge.cycleRepeat() } }
            ControlSlot(symbol: "backward.end.fill", size: 16, label: "Previous track", help: "Previous track",
                        enabled: enabled) { Task { await bridge.send(.previous) } }
            ControlSlot(symbol: player.isPlaying ? "pause.fill" : "play.fill", size: 20,
                        label: player.isPlaying ? "Pause" : "Play", help: player.isPlaying ? "Pause" : "Play",
                        enabled: enabled) { Task { await bridge.send(.toggle) } }
            ControlSlot(symbol: "forward.end.fill", size: 16, label: "Next track", help: "Next track",
                        enabled: enabled) { Task { await bridge.send(.next) } }
            ControlSlot(symbol: "shuffle", size: 14, tint: Self.toggleTint(on: shuffled),
                        label: "Shuffle", value: shuffled.map { $0 ? "On" : "Off" },
                        help: shuffled == true ? "Shuffle: on (click to turn off)" : "Shuffle: off (click to turn on)",
                        enabled: enabled && shuffled != nil) { Task { await bridge.toggleShuffle() } }
        }
        .frame(maxWidth: .infinity)
    }

    /// On = accent at full opacity; off/unknown = secondary at ~50%.
    private static func toggleTint(on: Bool?) -> Color { on == true ? .accentColor : Color.secondary.opacity(0.5) }
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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(help)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
    }
}

/// Heart for the current track, shown in the top icon row. Hidden when the page exposes no like control (isLiked == nil).
private struct LikeButton: View {
    @Environment(PlayerState.self) private var player
    @Environment(PlayerBridge.self) private var bridge

    var body: some View {
        if let liked = player.isLiked {
            FooterIconButton(systemName: liked ? "heart.fill" : "heart", label: liked ? "Unlike" : "Like",
                             tint: liked ? .red : nil, value: liked ? "Liked" : "Not liked") {
                Task { await bridge.toggleLike() }
            }
        }
    }
}

private struct FooterIconButton: View {
    let systemName: String
    let label: String
    var tint: Color?
    var value: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundStyle(tint ?? (hovering ? Color.primary : Color.secondary))
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.primary.opacity(hovering ? 0.10 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
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

/// Loads artwork for the track (via ArtworkCache); placeholder when nil.
private struct CoverArt: View {
    let track: TrackInfo?
    @State private var image: NSImage?

    var body: some View {
        CoverView(image: image)
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
            Text("Open the main window to sign in").font(.system(size: 14)).foregroundStyle(.secondary)
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
                .font(.system(size: 14)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Slim custom scrubber (4pt track). Only this view re-renders on the timeline;
/// the schedule is paused while not playing or while scrubbing.
private struct MiniProgress: View {
    let track: TrackInfo
    @Environment(PlayerState.self) private var player
    @Environment(PlayerBridge.self) private var bridge
    @State private var scrub: Double?

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
            .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func bar(pos: Double, duration: Double) -> some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let frac = duration > 0 ? CGFloat(min(max(pos / duration, 0), 1)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.15)).frame(height: 4)
                Capsule().fill(.primary.opacity(0.6)).frame(width: w * frac, height: 4)
            }
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
#Preview("No track") {
    let (s, b) = previewModel(track: false, playing: false)
    MiniPlayerView().environment(s).environment(b)
}
#endif
