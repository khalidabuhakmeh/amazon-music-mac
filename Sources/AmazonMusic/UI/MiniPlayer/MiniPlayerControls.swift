import AppKit
import SwiftUI

/// A fixed-size hit target that shares the row width equally with its siblings.
struct ControlSlot: View {
    let symbol: String
    let size: Font
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
                .font(size)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, minHeight: 32)
                .overlay(alignment: .bottom) {
                    // State indicator that doesn't rely on colour alone.
                    Circle().fill(Color.accentColor).frame(width: 4, height: 4).opacity(isOn ? 1 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : Surface.faint)
        .help(help)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
    }
}

/// Heart badge overlaid on the cover's bottom-right corner. Hidden when the page exposes no like control (isLiked == nil).
/// Liked: always visible, red. Not liked: white outline at ~55% opacity, full on hover.
struct LikeBadge: View {
    let liked: Bool
    let hovering: Bool
    @Environment(PlayerBridge.self) private var bridge

    var body: some View {
        Button { Task { await bridge.toggleLike() } } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(Glyph.control)
                .foregroundStyle(liked ? Color.red : Color.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.black.opacity(Surface.scrim)))
                .background(Circle().fill(.ultraThinMaterial))
                .shadow(color: .black.opacity(Surface.faint), radius: 3, y: 1)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(liked || hovering ? 1 : Surface.dim)
        .animation(Motion.quick, value: hovering)
        .help(liked ? "Unlike" : "Like")
        .accessibilityLabel(liked ? "Unlike" : "Like")
        .accessibilityValue(liked ? "Liked" : "Not liked")
        .accessibilityAddTraits(.isButton)
    }
}

/// "Play Similar Music" badge on the cover's top-left corner, the mirror of `LikeBadge` (same size, backing, padding, hover treatment).
/// Shown only when a track is loaded and the page says the action is available. Spinner while it runs.
struct SimilarBadge: View {
    let hovering: Bool
    @Environment(PlayerState.self) private var player
    @Environment(PlayerBridge.self) private var bridge

    var body: some View {
        let busy = player.similarPending != nil
        Button { Task { await bridge.playSimilar() } } label: {
            Group {
                if busy { ProgressView().controlSize(.small).tint(.white).colorScheme(.dark) }
                else { Image(systemName: "dot.radiowaves.left.and.right").font(Glyph.control).foregroundStyle(Color.white) }
            }
            .frame(width: 32, height: 32)
            .background(Circle().fill(.black.opacity(Surface.scrim)))
            .background(Circle().fill(.ultraThinMaterial))
            .shadow(color: .black.opacity(Surface.faint), radius: 3, y: 1)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy || hovering ? 1 : Surface.dim)
        .animation(Motion.quick, value: hovering)
        .help("Play Similar Music")
        .accessibilityLabel("Play Similar Music")
        .accessibilityValue(busy ? "Starting" : "")
        .accessibilityAddTraits(.isButton)
    }
}
