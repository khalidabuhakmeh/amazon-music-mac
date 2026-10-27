import Foundation

struct TrackInfo: Equatable, Sendable {
    var trackId: String?
    var title: String?
    var artist: String?
    var album: String?
    var artworkURL: URL?
    var duration: Double?

    /// Identity: trackId, falling back to title+artist+album. nil when nothing identifies the track.
    var identity: String? {
        if let trackId, !trackId.isEmpty { return "id:" + trackId }
        guard title != nil || artist != nil || album != nil else { return nil }
        return "meta:" + [title, artist, album].map { $0 ?? "" }.joined(separator: "\u{1F}")
    }
}
