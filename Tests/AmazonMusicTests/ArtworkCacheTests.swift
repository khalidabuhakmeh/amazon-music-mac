import AppKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AmazonMusic

private func makePNG(_ side: Int) -> Data {
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return out as Data
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var hits = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.hits += 1
        let r = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct ArtworkCacheTests {
    @Test func downscalesLargeImage() throws {
        let cg = try #require(ArtworkCache.decodeThumbnail(data: makePNG(2000), maxPixelSize: 256))
        #expect(max(cg.width, cg.height) <= 256)
        #expect(cg.width > 0)
    }

    @Test func rejectsNonImage() {
        #expect(ArtworkCache.decodeThumbnail(data: Data("not an image".utf8), maxPixelSize: 256) == nil)
        #expect(!ArtworkCache.isDecodable(Data("nope".utf8)))
        #expect(ArtworkCache.isDecodable(makePNG(8)))
    }

    @Test func cacheServesSecondCallFromMemory() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("artcache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.payload = makePNG(2000)
        StubURLProtocol.hits = 0
        let cache = ArtworkCache(directory: dir, session: URLSession(configuration: cfg))
        let url = try #require(URL(string: "https://m.media-amazon.com/images/I/test.png"))
        let a = try #require(await cache.image(for: url, maxPixelSize: 256))
        let b = try #require(await cache.image(for: url, maxPixelSize: 256))
        #expect(a === b)
        #expect(max(a.size.width, a.size.height) <= 256)
        #expect(StubURLProtocol.hits == 1)
        let c = try #require(await cache.image(for: url, maxPixelSize: 64))
        #expect(max(c.size.width, c.size.height) <= 64)
        #expect(StubURLProtocol.hits == 1) // disk hit, no refetch
    }

    @Test func rejectsOversizeAndUntrusted() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("artcache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.payload = Data(count: ArtworkCache.maxBytes + 1)
        let cache = ArtworkCache(directory: dir, session: URLSession(configuration: cfg))
        let ok = try #require(URL(string: "https://m.media-amazon.com/images/I/big.png"))
        #expect(await cache.image(for: ok) == nil)
        let bad = try #require(URL(string: "http://evil.example/a.png"))
        #expect(await cache.image(for: bad) == nil)
    }
}
