import XCTest
@testable import AmazonMusic

/// Fixtures are embedded literals mirroring bridge.js output (post() -> {v,type,payload}).
final class BridgeMessageDecodingTests: XCTestCase {
    func d(_ s: String) -> BridgeMessage { BridgeMessage.decode(Data(s.utf8)) }

    func testReady() {
        XCTAssertEqual(d(#"{"v":1,"type":"ready","payload":{"bridgeVersion":"1.0.0","sources":{"mediaSession":true,"mediaElement":false,"dom":false}}}"#), .ready(bridgeVersion: "1.0.0"))
    }
    func testState() {
        let m = d(#"{"v":1,"type":"state","payload":{"title":"T","artist":"A","album":"Al","artworkURL":"https://m.media-amazon.com/a.jpg","duration":200.5,"position":3,"isPlaying":true,"trackId":"T|A|Al","extra":1}}"#)
        guard case .state(let s) = m else { return XCTFail("\(m)") }
        XCTAssertEqual(s.title, "T"); XCTAssertEqual(s.duration, 200.5); XCTAssertTrue(s.isPlaying)
        XCTAssertEqual(s.artworkURL, URL(string: "https://m.media-amazon.com/a.jpg")); XCTAssertEqual(s.trackId, "T|A|Al")
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
    func testSignedInDecoding() {
        func si(_ frag: String) -> Bool?? {
            guard case .state(let s) = d(#"{"v":1,"type":"state","payload":{"title":"T","isPlaying":false\#(frag)}}"#) else { return .none }
            return .some(s.signedIn)
        }
        XCTAssertEqual(si(""), .some(nil))                    // older bridge
        XCTAssertEqual(si(#","signedIn":true"#), .some(true))
        XCTAssertEqual(si(#","signedIn":false"#), .some(false))
        XCTAssertEqual(si(#","signedIn":null"#), .some(nil))
        XCTAssertEqual(si(#","signedIn":"no""#), .some(nil)) // wrong type ignored, message still decodes
    }
    func testCanPlaySimilarDecodingAndCommand() {
        func c(_ frag: String) -> Bool?? {
            guard case .state(let s) = d(#"{"v":1,"type":"state","payload":{"title":"T","isPlaying":false\#(frag)}}"#) else { return .none }
            return .some(s.canPlaySimilar)
        }
        XCTAssertEqual(c(""), .some(nil))                         // older bridge
        XCTAssertEqual(c(#","canPlaySimilar":true"#), .some(true))
        XCTAssertEqual(c(#","canPlaySimilar":false"#), .some(false))
        XCTAssertEqual(c(#","canPlaySimilar":"yes""#), .some(nil)) // wrong type ignored, message still decodes
        XCTAssertEqual(PlayerCommand.playSimilar.script, "window.__amzBridge.playSimilar()")
    }
    func testQueueItemIDDecodingAndValidation() {
        func items(_ json: String) -> [BridgeMessage.QueueItem]? {
            guard case .state(let s) = d(#"{"v":1,"type":"state","payload":{"title":"T","isPlaying":true,"queue":\#(json)}}"#) else { return nil }
            return s.queue
        }
        let uuid = "7973d195-68b1-4ded-9727-20bb4a5a81e9"
        XCTAssertEqual(items(#"[{"id":"\#(uuid)","title":"A"},{"title":"B"}]"#)?.map(\.id), [uuid, nil])   // missing id -> nil
        XCTAssertNil(items(#"[{"id":"a b","title":"A"}]"#)?.first?.id)                  // space
        XCTAssertNil(items(#"[{"id":"x\"); alert(1);//","title":"A"}]"#)?.first?.id)    // script injection attempt
        XCTAssertNil(items(#"[{"id":"é","title":"A"}]"#)?.first?.id)                      // non-ASCII
        XCTAssertNil(items(#"[{"id":"\#(String(repeating: "a", count: 101))","title":"A"}]"#)?.first?.id) // too long
        XCTAssertNotNil(items(#"[{"id":"\#(String(repeating: "a", count: 100))","title":"A"}]"#)?.first?.id)
        XCTAssertNil(items(#"[{"id":42,"title":"A"}]"#))                                  // wrong type: the queue is dropped, message decodes
        XCTAssertEqual(BridgeMessage.validQueueItemID("abc-DEF_1.2:3"), "abc-DEF_1.2:3")
        XCTAssertNil(BridgeMessage.validQueueItemID("")); XCTAssertNil(BridgeMessage.validQueueItemID(nil))
        // command script: only validated ids are put into script text
        XCTAssertEqual(PlayerCommand.playQueueItem(uuid).script, "window.__amzBridge.playQueueItem(\"\(uuid)\")")
        XCTAssertNil(PlayerCommand.playQueueItem("a\"); evil(").script)
        XCTAssertNil(PlayerCommand.playQueueItem("a\"); evil(").asyncBody)
        // oversized id strings are cut by the generic string limit before decoding, never crashing
        let huge = String(repeating: "z", count: 1_000_000)
        let b: [String: Any] = ["v": 1, "type": "state", "payload": ["title": "T", "isPlaying": true, "canJumpToQueueItem": true, "queue": [["id": huge, "title": "X"]]]]
        guard case .state(let s) = BridgeMessage.decode(body: b) else { return XCTFail() }
        XCTAssertNil(s.queue?.first?.id); XCTAssertEqual(s.canJumpToQueueItem, true)
    }
    func testCommandIDIsEmittedAsJSONStringLiteral() throws {
        for id in ["7973d195-68b1-4ded-9727-20bb4a5a81e9", "a.b:c_d-E"] {
            let expected = String(data: try JSONEncoder().encode(id), encoding: .utf8)!
            XCTAssertEqual(PlayerCommand.playQueueItem(id).script, "window.__amzBridge.playQueueItem(\(expected))")
            XCTAssertEqual(PlayerCommand.playQueueItem(id).asyncBody, "return JSON.stringify(await window.__amzBridge.playQueueItem(\(expected)));")
        }
        for bad in ["", "a b", "a\"b", "a\\b", "a'b", "a);b", "\u{2028}", String(repeating: "a", count: 101)] {
            XCTAssertNil(PlayerCommand.playQueueItem(bad).script, bad)
        }
    }
    func testUpNextRowKeysUseEntryIDsWithPositionalFallback() {
        func item(_ id: String?, _ t: String) -> BridgeMessage.QueueItem { .init(id: id, title: t) }
        let a = UpNextRowKeys.keyed([item("x1", "A"), item("x2", "B"), item(nil, "C"), item(nil, "D")])
        XCTAssertEqual(a.map(\.key), ["x1", "x2", "pos-2", "pos-3"])
        // the same song keeps its key when the list shifts (so a pending spinner stays on it)
        let b = UpNextRowKeys.keyed([item("x2", "B"), item(nil, "C")])
        XCTAssertEqual(b.first?.key, "x2")
        // duplicate ids never produce duplicate keys; capped at 10 rows
        XCTAssertEqual(Set(UpNextRowKeys.keyed([item("d", "A"), item("d", "B")]).map(\.key)).count, 2)
        XCTAssertEqual(UpNextRowKeys.keyed((0..<15).map { item("i\($0)", "S\($0)") }).count, 10)
    }
    func testEvalGateResumesExactlyOnce() async {
        let outcome: EvalOutcome = await withCheckedContinuation { cont in
            let gate = EvalGate(cont)
            gate.resume(.timedOut)       // whichever finishes first wins ...
            gate.resume(.value("late"))  // ... a late second result is ignored (no double-resume crash)
            gate.resume(.failed)
        }
        XCTAssertEqual(outcome, .timedOut)
        let timeout = await MainActor.run { PlayerBridge.commandTimeout }
        XCTAssertEqual(timeout, 8)
    }
    func testQueueDecoding() {
        func st(_ frag: String) -> BridgeMessage.StatePayload? {
            guard case .state(let s) = d(#"{"v":1,"type":"state","payload":{"title":"T","isPlaying":true\#(frag)}}"#) else { return nil }
            return s
        }
        XCTAssertNil(st("")?.queue)                                   // old bridge: backward compatible
        XCTAssertNotNil(st(""))
        XCTAssertNil(st(#","queue":null"#)?.queue)
        let q = st(#","queue":[{"title":"One","artist":"A","artworkURL":"https://m.media-amazon.com/a.jpg"},{"title":"Two"},{"title":" "},{"artist":"No title"},{"title":"Rel","artworkURL":"/a.jpg"}]"#)?.queue
        XCTAssertEqual(q?.map(\.title), ["One", "Two", "Rel"])        // untitled items dropped
        XCTAssertEqual(q?.first, .init(title: "One", artist: "A", artworkURL: URL(string: "https://m.media-amazon.com/a.jpg")))
        XCTAssertNil(q?[1].artist); XCTAssertNil(q?[2].artworkURL)   // non-absolute artwork rejected
        XCTAssertNil(st(#","queue":"bogus""#)?.queue)                 // wrong type ignored, message still decodes
        XCTAssertNotNil(st(#","queue":"bogus""#))
        let many = (0..<30).map { #"{"title":"S\#($0)"}"# }.joined(separator: ",")
        XCTAssertEqual(st(#","queue":[\#(many)]"#)?.queue?.count, 20)
    }
    func testCommandScripts() {
        XCTAssertEqual(PlayerCommand.refreshQueue.script, "window.__amzBridge.refreshQueue()")
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
    func testArtworkHostValidation() {
        func ok(_ u: String) -> Bool { URL(string: u).map(ArtworkPolicy.isTrusted) ?? false }
        XCTAssertTrue(ok("https://m.media-amazon.com/images/I/a.jpg"))
        XCTAssertTrue(ok("https://media-amazon.com/a.jpg"))
        XCTAssertTrue(ok("https://images-na.ssl-images-amazon.com/a.jpg"))
        XCTAssertTrue(ok("https://M.MEDIA-AMAZON.COM/a.jpg"))
        XCTAssertFalse(ok("http://m.media-amazon.com/a.jpg"))               // not https
        XCTAssertFalse(ok("https://evilmedia-amazon.com/a.jpg"))            // no dot boundary
        XCTAssertFalse(ok("https://media-amazon.com.evil.example/a.jpg"))   // suffix trick
        XCTAssertFalse(ok("https://evil.example/media-amazon.com/a.jpg"))   // path trick
        XCTAssertFalse(ok("https://m.media-amazon.com@evil.example/a.jpg")) // userinfo trick
        XCTAssertFalse(ok("https://user:pw@m.media-amazon.com/a.jpg"))
        XCTAssertFalse(ok("https://example.com/a.jpg"))
        XCTAssertFalse(ok("file:///etc/passwd"))
        XCTAssertNil(BridgeMessage.safeURL("https://example.com/a.jpg"))
        XCTAssertNotNil(BridgeMessage.safeURL("https://m.media-amazon.com/a.jpg"))
        XCTAssertNil(BridgeMessage.safeURL("https://m.media-amazon.com/" + String(repeating: "a", count: 3000)))
        // queue artwork goes through the same check
        guard case .state(let s) = d(#"{"v":1,"type":"state","payload":{"title":"T","isPlaying":true,"queue":[{"title":"a","artworkURL":"https://evil.example/x.jpg"},{"title":"b","artworkURL":"https://m.media-amazon.com/x.jpg"}]}}"#) else { return XCTFail() }
        XCTAssertNil(s.queue?[0].artworkURL); XCTAssertNotNil(s.queue?[1].artworkURL)
    }
    func testOriginPolicy() {
        func ok(_ host: String?, scheme: String? = "https", main: Bool = true, cfg: String? = nil) -> Bool {
            BridgeOriginPolicy.isAllowed(isMainFrame: main, scheme: scheme, host: host, configuredHost: cfg)
        }
        XCTAssertTrue(ok("music.amazon.com")); XCTAssertTrue(ok("music.amazon.co.uk")); XCTAssertTrue(ok("MUSIC.AMAZON.DE"))
        XCTAssertFalse(ok("music.amazon.com", main: false))        // sub-frame
        XCTAssertFalse(ok("music.amazon.com", scheme: "http"))                      // not https
        XCTAssertFalse(ok("music.amazon.com", scheme: nil)); XCTAssertFalse(ok(nil))
        XCTAssertFalse(ok("music.amazon.com.evil.example"))                 // suffix trick
        XCTAssertFalse(ok("evilmusic.amazon.com"))
        XCTAssertFalse(ok("www.amazon.com"))                                // not the music host
        XCTAssertFalse(ok("evil.example"))
        XCTAssertFalse(ok("music.amazon.ch"))                               // not a preset, not configured
        XCTAssertTrue(ok("music.amazon.ch", cfg: "music.amazon.ch"))        // configured region host
        XCTAssertFalse(ok("evil.example", cfg: "evil.example"))             // configured must still be music.amazon.*
    }
    func testOversizedMessageLimits() {
        // Oversized serialized message -> dropped, no crash.
        let big = String(repeating: "x", count: BridgeMessage.Limits.maxMessageBytes + 10)
        XCTAssertEqual(BridgeMessage.decode(Data((#"{"v":1,"type":"log","payload":{"message":""# + big + #""}}"#).utf8)), .unknown)
        // Huge array in a raw body is truncated BEFORE serialization.
        let items: [[String: Any]] = (0..<5000).map { ["title": "S\($0)", "artist": "A"] }
        let body: [String: Any] = ["v": 1, "type": "state", "payload": ["title": "T", "isPlaying": true, "queue": items]]
        guard case .state(let s) = BridgeMessage.decode(body: body) else { return XCTFail("should decode truncated") }
        XCTAssertEqual(s.queue?.count, BridgeMessage.Limits.maxQueueItems)
        XCTAssertEqual(s.queue?.first?.title, "S0")
        // Long strings are truncated (title/artist 300, giant strings cut at 2048 first).
        let long = String(repeating: "y", count: 1_000_000)
        let b2: [String: Any] = ["v": 1, "type": "state", "payload": ["title": long, "artist": long, "isPlaying": true,
                                  "queue": [["title": long, "artist": long, "artworkURL": long]]]]
        guard case .state(let s2) = BridgeMessage.decode(body: b2) else { return XCTFail() }
        XCTAssertEqual(s2.title?.count, BridgeMessage.Limits.maxTextLength)
        XCTAssertEqual(s2.artist?.count, BridgeMessage.Limits.maxTextLength)
        XCTAssertEqual(s2.queue?.first?.title.count, BridgeMessage.Limits.maxTextLength)
        XCTAssertEqual(s2.queue?.first?.artist?.count, BridgeMessage.Limits.maxTextLength)
        XCTAssertNil(s2.queue?.first?.artworkURL)
        // Deeply nested / non-JSON values never crash.
        var nested: Any = "leaf"; for _ in 0..<200 { nested = ["a": nested] }
        _ = BridgeMessage.decode(body: ["v": 1, "type": "state", "payload": ["title": "T", "x": nested, "d": Date()]] as [String: Any])
    }
    func testBodyDictionary() {
        XCTAssertEqual(BridgeMessage.decode(body: ["v": 1, "type": "log", "payload": ["message": "x"]] as [String: Any]), .log(message: "x"))
        XCTAssertEqual(BridgeMessage.decode(body: "str"), .unknown)
    }
}
