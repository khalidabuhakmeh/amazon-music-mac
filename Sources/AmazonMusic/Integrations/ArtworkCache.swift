import AppKit
import Foundation
import OSLog

/// Downloads artwork (https only), caches in memory and on disk (Caches/<bundle id>/artwork).
actor ArtworkCache {
    static let shared = ArtworkCache()
    static let maxBytes = 8 * 1024 * 1024
    static let maxDiskFiles = 100
    private static let log = Logger(subsystem: "com.khalidabuhakmeh.amazonmusic", category: "artwork")

    private var memory: [URL: NSImage] = [:]
    private var order: [URL] = []
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

    func image(for url: URL) async -> NSImage? {
        if let img = memory[url] { return img }
        guard let file = await fileURL(for: url), let img = NSImage(contentsOf: file) else { return nil }
        remember(img, for: url)
        return img
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
                  NSImage(data: data) != nil else { return nil }
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

    private func remember(_ img: NSImage, for url: URL) {
        memory[url] = img
        order.removeAll { $0 == url }
        order.append(url)
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
