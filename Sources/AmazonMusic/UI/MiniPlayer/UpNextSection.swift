import AppKit
import SwiftUI

struct UpNextSection: View {
    let items: [BridgeMessage.QueueItem]
    var expandedOverride: Bool?
    @AppStorage("upNextExpanded") private var storedExpanded = false
    private var expanded: Bool { expandedOverride ?? storedExpanded }
    @Environment(PlayerState.self) private var player
    @Environment(PlayerBridge.self) private var bridge
    private static let rowHeight: CGFloat = 36
    private static let maxVisibleRows: CGFloat = 5.5

    /// Rows start their song when the page can jump to a queue entry; otherwise they behave as before (collapsed row toggles).
    private func playable(_ item: BridgeMessage.QueueItem) -> Bool { player.canJumpToQueueItem && item.id != nil }
    private func play(_ item: BridgeMessage.QueueItem) { if let id = item.id { Task { await bridge.playQueueItem(id) } } }

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(Surface.secondaryText)
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
                .padding(.bottom, Space.s)
            } else if let first = items.first {
                // Collapsed: a preview of the next song; the whole row (song + chevron) only expands the list.
                Button { toggle() } label: {
                    HStack(spacing: 0) {
                        UpNextRow(item: first, showsLabel: true)
                        chevron.frame(width: 44, height: 44)
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
                Text("Up Next").font(.callout.weight(.semibold)).foregroundStyle(.primary.opacity(Surface.secondaryText))
                Spacer()
                chevron
            }
            .padding(.horizontal, Space.l).frame(height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Hide upcoming songs")
        .accessibilityLabel("Up Next")
        .accessibilityValue("Expanded")
        .accessibilityHint("Hides the upcoming songs")
    }

    private var chevron: some View {
        Image(systemName: expanded ? "chevron.down" : "chevron.right")
            .font(Glyph.small).foregroundStyle(.primary.opacity(Surface.secondaryText))
    }

    private func toggle() { withAnimation(Motion.standard) { storedExpanded.toggle() } }
}

/// One upcoming song. When `playable` (expanded list), the whole row is a button that plays it (hover highlight + play icon
/// on the artwork, "Play <title>" tooltip, spinner on the artwork while `pending`). `showsLabel` marks the collapsed preview
/// row, which is never playable: its parent button only expands the list.
struct UpNextRow: View {
    let item: BridgeMessage.QueueItem
    var showsLabel = false
    var playable = false
    var pending = false
    var onPlay: () -> Void = {}
    @State private var image: NSImage?
    @State private var hovering = false

    var body: some View {
        let content = HStack(spacing: Space.m) {
            ZStack {
                Group {
                    if let image { Image(nsImage: image).resizable().scaledToFill() }
                    else { ZStack { Rectangle().fill(.quaternary); Image(systemName: "music.note").font(.caption).foregroundStyle(.secondary) } }
                }
                // Hover/pending feedback lives on the artwork (like Music.app), not as a trailing glyph next to the chevron.
                if pending {
                    Rectangle().fill(.black.opacity(Surface.scrim))
                    ProgressView().controlSize(.mini).tint(.white)
                } else if playable && hovering {
                    Rectangle().fill(.black.opacity(Surface.scrim))
                    Image(systemName: "play.fill").font(Glyph.small).foregroundStyle(.white)
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous).strokeBorder(.primary.opacity(Surface.hairline), lineWidth: 0.5)) // grid: ok hairline border
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.tail)
                if let artist = item.artist {
                    Text(artist).font(.caption).foregroundStyle(.primary.opacity(Surface.secondaryText)).lineLimit(1).truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Collapsed: artwork aligns with the title column above (14pt), chevron button supplies the trailing edge.
        .padding(.leading, Space.l)
        .padding(.trailing, showsLabel ? 0 : Space.l)
        .frame(maxHeight: .infinity)
        .background {
            // Expanded list rows get a subtle inset highlight; the collapsed row relies on the artwork overlay only.
            if !showsLabel {
                RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                    .fill(Color.primary.opacity(playable && hovering && !pending ? Surface.hoverFill : 0))
                    .padding(.horizontal, Space.s).padding(.vertical, Space.xxs)
            }
        }
        .opacity(pending ? Surface.dim : 1)
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
