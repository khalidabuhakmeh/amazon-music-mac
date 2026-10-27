import XCTest
@testable import AmazonMusic

/// Fixtures are embedded literals mirroring bridge.js output (post() -> {v,type,payload}).
final class BridgeMessageDecodingTests: XCTestCase {
    func d(_ s: String) -> BridgeMessage { BridgeMessage.decode(Data(s.utf8)) }

    func testReady() {
        XCTAssertEqual(d(#"{"v":1,"type":"ready","payload":{"bridgeVersion":"1.0.0","sources":{"mediaSession":true,"mediaElement":false,"dom":false}}}"#), .ready(bridgeVersion: "1.0.0"))
    }
    func testState() {
        let m = d(#"{"v":1,"type":"state","payload":{"title":"T","artist":"A","album":"Al","artworkURL":"https://x.com/a.jpg","duration":200.5,"position":3,"isPlaying":true,"trackId":"T|A|Al","extra":1}}"#)
        guard case .state(let s) = m else { return XCTFail("\(m)") }
        XCTAssertEqual(s.title, "T"); XCTAssertEqual(s.duration, 200.5); XCTAssertTrue(s.isPlaying)
        XCTAssertEqual(s.artworkURL, URL(string: "https://x.com/a.jpg")); XCTAssertEqual(s.trackId, "T|A|Al")
    }
    func testLikedDecoding() {
        func liked(_ frag: String) -> Bool?? {
            guard case .state(let s) = d(#"{"v":1,"type":"state","payload":{"title":"T","isPlaying":true\#(frag)}}"#) else { return .none }
            return .some(s.liked)
        }
        XCTAssertEqual(liked(""), .some(nil))                       // old bridge: backward compatible
        XCTAssertEqual(liked(#","liked":true"#), .some(true))
        XCTAssertEqual(liked(#","liked":false"#), .some(false))
        XCTAssertEqual(liked(#","liked":null"#), .some(nil))
        XCTAssertEqual(liked(#","liked":"yes""#), .some(nil))       // wrong type ignored, message still decodes
    }
    func testShuffleAndRepeatDecoding() {
        func st(_ frag: String) -> BridgeMessage.StatePayload? {
            guard case .state(let s) = d(#"{"v":1,"type":"state","payload":{"title":"T","isPlaying":true\#(frag)}}"#) else { return nil }
            return s
        }
        XCTAssertNil(st("")?.shuffle); XCTAssertNil(st("")?.repeatMode)                // old bridge (1.2.x): backward compatible
        XCTAssertNotNil(st(""))
        XCTAssertEqual(st(#","shuffle":true,"repeat":"all""#)?.shuffle, true)
        XCTAssertEqual(st(#","shuffle":false,"repeat":"off""#)?.shuffle, false)
        XCTAssertEqual(st(#","repeat":"all""#)?.repeatMode, .all)
        XCTAssertEqual(st(#","repeat":"one""#)?.repeatMode, .one)
        XCTAssertEqual(st(#","repeat":"off""#)?.repeatMode, .off)
        XCTAssertNil(st(#","shuffle":null,"repeat":null"#)?.repeatMode)
        XCTAssertNotNil(st(#","shuffle":null,"repeat":null"#))
        XCTAssertNil(st(#","repeat":"bogus""#)?.repeatMode)                          // unknown value ignored, message decodes
        XCTAssertNil(st(#","shuffle":"yes","repeat":3"#)?.shuffle)
        XCTAssertNotNil(st(#","shuffle":"yes","repeat":3"#))
    }
    func testCommandScripts() {
        XCTAssertEqual(PlayerCommand.toggleShuffle.script, "window.__amzBridge.toggleShuffle()")
        XCTAssertEqual(PlayerCommand.cycleRepeat.script, "window.__amzBridge.cycleRepeat()")
    }
    func testPosition() {
        XCTAssertEqual(d(#"{"v":1,"type":"position","payload":{"position":5.5,"duration":100}}"#), .position(position: 5.5, duration: 100))
    }
    func testError() {
        XCTAssertEqual(d(#"{"v":1,"type":"error","payload":{"code":"c","message":"m"}}"#), .error(code: "c", message: "m"))
    }
    func testLog() {
        XCTAssertEqual(d(#"{"v":1,"type":"log","payload":{"message":"hi"}}"#), .log(message: "hi"))
    }
    func testUnknownTypeAndVersion() {
        XCTAssertEqual(d(#"{"v":1,"type":"zzz","payload":{}}"#), .unknown)
        XCTAssertEqual(d(#"{"v":2,"type":"ready","payload":{}}"#), .unknown)
        XCTAssertEqual(d(#"{"type":"ready","payload":{}}"#), .unknown)
        XCTAssertEqual(d("garbage"), .unknown)
    }
    func testNullMissingAndNonFiniteNumbers() {
        guard case .state(let s) = d(#"{"v":1,"type":"state","payload":{"title":"T","duration":null,"isPlaying":false}}"#) else { return XCTFail() }
        XCTAssertNil(s.duration); XCTAssertNil(s.position)
        XCTAssertEqual(d(#"{"v":1,"type":"position","payload":{"position":null,"duration":"x"}}"#), .position(position: nil, duration: nil))
        // JS JSON.stringify turns NaN/Infinity into null; raw non-finite via body path:
        XCTAssertEqual(BridgeMessage.decode(body: ["v": 1, "type": "position", "payload": ["position": Double.nan]] as [String: Any]), .unknown)
        XCTAssertEqual(d(#"{"v":1,"type":"position","payload":{"position":1e999}}"#), .position(position: nil, duration: nil))
    }
    func testArtwork() {
        func art(_ a: String) -> URL? {
            guard case .state(let s) = d(#"{"v":1,"type":"state","payload":{"title":"T","artworkURL":"\#(a)","isPlaying":false}}"#) else { return nil }
            return s.artworkURL
        }
        XCTAssertNil(art("/img/a.jpg")); XCTAssertNil(art("a.jpg")); XCTAssertNil(art("javascript:alert(1)"))
        XCTAssertNotNil(art("https://m.media-amazon.com/a.jpg"))
        guard case .state(let s) = d(#"{"v":1,"type":"state","payload":{"title":"T","isPlaying":false}}"#) else { return XCTFail() }
        XCTAssertNil(s.artworkURL)
    }
    func testBodyDictionary() {
        XCTAssertEqual(BridgeMessage.decode(body: ["v": 1, "type": "log", "payload": ["message": "x"]] as [String: Any]), .log(message: "x"))
        XCTAssertEqual(BridgeMessage.decode(body: "str"), .unknown)
    }
}
