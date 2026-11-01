import AppKit
import SwiftUI

struct MiniPlaceholderText: View {
    /// Sign-in wording only when the page says the user is signed out; otherwise a hint to pick something to play.
    var signedOut = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Nothing playing").font(.title3.weight(.semibold))
                .lineLimit(2)
            Text(signedOut ? "Open the main window to sign in" : "Pick something to play in Amazon Music").font(.body).foregroundStyle(.primary.opacity(Surface.secondaryText))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct MiniTitleBlock: View {
    let track: TrackInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track.title ?? "Unknown title")
                .font(.title3.weight(.semibold))
                .lineLimit(2).truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            Text(track.artist ?? "")
                .font(.body).foregroundStyle(.primary.opacity(Surface.secondaryText))
                .lineLimit(1).truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Custom scrubber (6pt track, knob on hover/drag). Only this view re-renders on the timeline;
/// the schedule is paused while not playing or while scrubbing.
struct MiniProgress: View {
    let track: TrackInfo
    @Environment(PlayerState.self) private var player
    @Environment(PlayerBridge.self) private var bridge
    @State private var scrub: Double?
    @State private var barHover = false

    var body: some View {
        let duration = max(track.duration ?? 0, 0)
        TimelineView(.animation(minimumInterval: 0.5, paused: !player.isPlaying || scrub != nil)) { ctx in
            let pos = min(scrub ?? player.interpolatedPosition(at: ctx.date), duration > 0 ? duration : .infinity)
            HStack(spacing: Space.s) {
                Text(Self.format(pos)).frame(minWidth: 28, alignment: .leading)
                bar(pos: pos, duration: duration)
                Text(duration > 0 ? "-" + Self.format(max(0, duration - pos)) : "--:--")
                    .frame(minWidth: 28, alignment: .trailing)
            }
            .font(.caption2.monospacedDigit()).foregroundStyle(.primary.opacity(Surface.secondaryText))
        }
    }

    private func bar(pos: Double, duration: Double) -> some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let frac = duration > 0 ? CGFloat(min(max(pos / duration, 0), 1)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(Surface.faint)).frame(height: 8)
                Capsule().fill(Color.primary).frame(width: w * frac, height: 8)
                Circle().fill(Color.primary).frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(Surface.faint), radius: 1.5, y: 0.5)
                    .offset(x: min(max(w * frac - 6, 0), w - 12)) // grid: ok scrub knob follows drag position
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
        .frame(height: 16)
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
