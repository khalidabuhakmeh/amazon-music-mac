import AppKit
import SwiftUI

/// Rounded cover with subtle border/shadow; placeholder glyph when there is no image.
struct CoverView: View {
    let image: NSImage?
    static let size: CGFloat = 120

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "music.note").font(Glyph.placeholder).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).strokeBorder(.primary.opacity(Surface.hairline), lineWidth: 0.5)) // grid: ok hairline border
        .shadow(color: .black.opacity(Surface.faint), radius: 5, y: 2)
        .accessibilityHidden(true)
    }
}

/// Loads artwork for the track (via ArtworkCache); placeholder when nil. Hosts the like badge.
struct CoverArt: View {
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
                        .padding(.trailing, Space.xs).padding(.bottom, Space.xs)
                }
            }
            .overlay(alignment: .topLeading) {
                if track != nil, player.canPlaySimilar {
                    SimilarBadge(hovering: hovering || forceHover)
                        .padding(.leading, Space.xs).padding(.top, Space.xs)
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
