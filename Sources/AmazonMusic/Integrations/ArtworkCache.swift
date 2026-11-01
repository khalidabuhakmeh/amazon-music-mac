import AppKit
import Foundation
import ImageIO
import OSLog

/// Downloads artwork (https only), caches in memory and on disk (Caches/<bundle id>/artwork).
actor ArtworkCache {
    static let shared = ArtworkCache()
    static let maxBytes = 8 * 1024 * 1024
    static let maxDiskFiles = 100
    private static let log = Logger(subsystem: "com.khalidabuhakmeh.amazonmusic", category: "artwork")

    /// Pixel sizes used by callers (display points x 2 backing scale, rounded up).
    static let coverPixels = 256      // mini player cover, 120 pt
    static let rowPixels = 64         // Up Next row, 28 pt
    static let nowPlayingPixels = 512 // Control Center / Now Playing

    private struct Key: Hashable { let url: URL; let pixels: Int }
    private var memory: [Key: NSImage] = [:]
    private var order: [Key] = []
    private let memoryLimit = 20
    private let directory: URL
    private let session: URLSession

    init(directory: URL? = nil, session: URLSession = .shared) {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = directory ?? base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.khalidabuhakmeh.amazonmusic", isDirectory: true)
            .appendingPathComponent("artwork", isDirectory: true)
        self.session = session
    }

    func image(for url: URL, maxPixelSize: Int = ArtworkCache.nowPlayingPixels) async -> NSImage? {
        let key = Key(url: url, pixels: maxPixelSize)
        if let img = memory[key] { return img }
        guard let file = await fileURL(for: url) else { return nil }
        // Decode off the actor; only a Sendable CGImage crosses back.
        guard let cg = await Task.detached(priority: .utility, operation: { Self.decodeThumbnail(file: file, maxPixelSize: maxPixelSize) }).value else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        remember(img, for: key)
        return img
    }

    /// Decodes at most `maxPixelSize` px on the long edge (never the full-size bitmap).
    nonisolated static func decodeThumbnail(data: Data, maxPixelSize: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(src, maxPixelSize)
    }

    nonisolated static func decodeThumbnail(file: URL, maxPixelSize: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        return thumbnail(src, maxPixelSize)
    }

    nonisolated private static func thumbnail(_ src: CGImageSource, _ maxPixelSize: Int) -> CGImage? {
        guard maxPixelSize > 0, CGImageSourceGetCount(src) > 0 else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    nonisolated static func isDecodable(_ data: Data) -> Bool {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(src) > 0 && CGImageSourceGetStatus(src) != .statusInvalidData
    }

    /// Local file URL (valid .jpg/.png extension) for the artwork, downloading if needed. nil on failure.
    func fileURL(for url: URL) async -> URL? {
        guard ArtworkPolicy.isTrusted(url) else { return nil }
        let fm = FileManager.default
        let target = directory.appendingPathComponent(Self.baseName(for: url))
        for ext in ["jpg", "png"] {
            let f = target.appendingPathExtension(ext)
            if fm.fileExists(atPath: f.path) { return f }
        }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 15
            let (data, response) = try await session.data(for: req)
            guard data.count <= Self.maxBytes, !data.isEmpty,
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  Self.isDecodable(data) else { return nil }
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let ext = Self.isPNG(data) ? "png" : "jpg"
            let final = target.appendingPathExtension(ext)
            try data.write(to: final, options: .atomic)
            trimDisk()
            return final
        } catch {
            Self.log.debug("artwork fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // Extension depends on content; callers probe both.
    private static func baseName(for url: URL) -> String {
        var h: UInt64 = 5381
        for b in url.absoluteString.utf8 { h = (h &* 33) &+ UInt64(b) }
        return String(h, radix: 16)
    }

    private static func isPNG(_ d: Data) -> Bool { d.starts(with: [0x89, 0x50, 0x4E, 0x47]) }

    private func remember(_ img: NSImage, for key: Key) {
        memory[key] = img
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > memoryLimit { memory[order.removeFirst()] = nil }
    }

    private func trimDisk() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]),
              files.count > Self.maxDiskFiles else { return }
        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a < b
        }
        for f in sorted.prefix(files.count - Self.maxDiskFiles) { try? fm.removeItem(at: f) }
    }
}
