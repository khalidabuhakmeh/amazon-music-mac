import Testing
import Foundation
@testable import AmazonMusic

/// Fixtures are embedded literals mirroring bridge.js output (post() -> {v,type,payload}).
@Suite struct BridgeMessageDecodingTests {
    func d(_ s: String) -> BridgeMessage { BridgeMessage.decode(Data(s.utf8)) }

    @Test func testReady() {
        #expect(d(#"{"v":1,"type":"ready","payload":{"bridgeVersion":"1.0.0","sources":{"mediaSession":true,"mediaElement":false,"dom":false}}}"#) == .ready(bridgeVersion: "1.0.0"))
    }
    @Test func testState() {
        let m = d(#"{"v":1,"type":"state","payload":{"title":"T","artist":"A","album":"Al","artworkURL":"https://m.media-amazon.com/a.jpg","duration":200.5,"position":3,"isPlaying":true,"trackId":"T|A|Al","extra":1}}"#)
        guard case .state(let s) = m else { Issue.record("\(m)"); return }
        #expect(s.title == "T"); #expect(s.duration == 200.5); #expect(s.isPlaying)
        #expect(s.artworkURL == URL(string: "https://m.media-amazon.com/a.jpg")); #expect(s.trackId == "T|A|Al")
    }
    @Test func testLikedDecoding() {
        func liked(_ frag: String) -> Bool?? {
            guard case .state(let s) = d(#"{"v":1,"type":"state","payload":{"title":"T","isPlaying":true\#(frag)}}"#) else { return .none }
            return .some(s.liked)
        }
        #expect(liked("") == .some(nil))                       // old bridge: backward compatible
        #expect(liked(#","liked":true"#) == .some(true))
        #expect(liked(#","liked":false"#) == .some(false))
        #expect(liked(#","liked":null"#) == .some(nil))
        #expect(liked(#","liked":"yes""#) == .some(nil))       // wrong type ignored, message still decodes
    }
    @Test func testShuffleAndRepeatDecoding() {
        func st(_ frag: String) -> BridgeMessage.StatePayload? {
            guard case .state(let s) = d(#"{"v":1,"type":"state","payload":{"title":"T","isPlaying":true\#(frag)}}"#) else { return nil }
            return s
        }
        #expect(st("")?.shuffle == nil); #expect(st("")?.repeatMode == nil)                // old bridge (1.2.x): backward compatible
        #expect(st("") != nil)
        #expect(st(#","shuffle":true,"repeat":"all""#)?.shuffle == true)
        #expect(st(#","shuffle":false,"repeat":"off""#)?.shuffle == false)
        #expect(st(#","repeat":"all""#)?.repeatMode == .all)
        #expect(st(#","repeat":"one""#)?.repeatMode == .one)
        #expect(st(#","repeat":"off""#)?.repeatMode == .off)
        #expect(st(#","shuffle":null,"repeat":null"#)?.repeatMode == nil)
        #expect(st(#","shuffle":null,"repeat":null"#) != nil)
        #expect(st(#","repeat":"bogus""#)?.repeatMode == nil)                          // unknown value ignored, message decodes
        #expect(st(#","shuffle":"yes","repeat":3"#)?.shuffle == nil)
        #expect(st(#","shuffle":"yes","repeat":3"#) != nil)
    }
    @Test func testSignedInDecoding() {
        func si(_ frag: String) -> Bool?? {
            guard case .state(let s) = d(#"{"v":1,"type":"state","payload":{"title":"T","isPlaying":false\#(frag)}}"#) else { return .none }
            return .some(s.signedIn)
        }
        #expect(si("") == .some(nil))                    // older bridge
        #expect(si(#","signedIn":true"#) == .some(true))
        #expect(si(#","signedIn":false"#) == .some(false))
        #expect(si(#","signedIn":null"#) == .some(nil))
        #expect(si(#","signedIn":"no""#) == .some(nil)) // wrong type ignored, message still decodes
    }
    @Test func testCanPlaySimilarDecodingAndCommand() {
        func c(_ frag: String) -> Bool?? {
            guard case .state(let s) = d(#"{"v":1,"type":"state","payload":{"title":"T","isPlaying":false\#(frag)}}"#) else { return .none }
            return .some(s.canPlaySimilar)
        }
        #expect(c("") == .some(nil))                         // older bridge
        #expect(c(#","canPlaySimilar":true"#) == .some(true))
        #expect(c(#","canPlaySimilar":false"#) == .some(false))
        #expect(c(#","canPlaySimilar":"yes""#) == .some(nil)) // wrong type ignored, message still decodes
        #expect(PlayerCommand.playSimilar.script == "window.__amzBridge.playSimilar()")
    }
    @Test func testQueueItemIDDecodingAndValidation() {
        func items(_ json: String) -> [BridgeMessage.QueueItem]? {
            guard case .state(let s) = d(#"{"v":1,"type":"state","payload":{"title":"T","isPlaying":true,"queue":\#(json)}}"#) else { return nil }
            return s.queue
        }
        let uuid = "7973d195-68b1-4ded-9727-20bb4a5a81e9"
        #expect(items(#"[{"id":"\#(uuid)","title":"A"},{"title":"B"}]"#)?.map(\.id) == [uuid, nil])   // missing id -> nil
        #expect(items(#"[{"id":"a b","title":"A"}]"#)?.first?.id == nil)                  // space
        #expect(items(#"[{"id":"x\"); alert(1);//","title":"A"}]"#)?.first?.id == nil)    // script injection attempt
        #expect(items(#"[{"id":"é","title":"A"}]"#)?.first?.id == nil)                      // non-ASCII
        #expect(items(#"[{"id":"\#(String(repeating: "a", count: 101))","title":"A"}]"#)?.first?.id == nil) // too long
        #expect(items(#"[{"id":"\#(String(repeating: "a", count: 100))","title":"A"}]"#)?.first?.id != nil)
        #expect(items(#"[{"id":42,"title":"A"}]"#) == nil)                                  // wrong type: the queue is dropped, message decodes
        #expect(BridgeMessage.validQueueItemID("abc-DEF_1.2:3") == "abc-DEF_1.2:3")
        #expect(BridgeMessage.validQueueItemID("") == nil); #expect(BridgeMessage.validQueueItemID(nil) == nil)
        // command script: only validated ids are put into script text
        #expect(PlayerCommand.playQueueItem(uuid).script == "window.__amzBridge.playQueueItem(\"\(uuid)\")")
        #expect(PlayerCommand.playQueueItem("a\"); evil(").script == nil)
        #expect(PlayerCommand.playQueueItem("a\"); evil(").asyncBody == nil)
        // oversized id strings are cut by the generic string limit before decoding, never crashing
        let huge = String(repeating: "z", count: 1_000_000)
        let b: [String: Any] = ["v": 1, "type": "state", "payload": ["title": "T", "isPlaying": true, "canJumpToQueueItem": true, "queue": [["id": huge, "title": "X"]]]]
        guard case .state(let s) = BridgeMessage.decode(body: b) else { Issue.record(); return }
        #expect(s.queue?.first?.id == nil); #expect(s.canJumpToQueueItem == true)
    }
    @Test func testCommandIDIsEmittedAsJSONStringLiteral() throws {
        for id in ["7973d195-68b1-4ded-9727-20bb4a5a81e9", "a.b:c_d-E"] {
            let expected = String(data: try JSONEncoder().encode(id), encoding: .utf8)!
            #expect(PlayerCommand.playQueueItem(id).script == "window.__amzBridge.playQueueItem(\(expected))")
            #expect(PlayerCommand.playQueueItem(id).asyncBody == "return JSON.stringify(await window.__amzBridge.playQueueItem(\(expected)));")
        }
        for bad in ["", "a b", "a\"b", "a\\b", "a'b", "a);b", "\u{2028}", String(repeating: "a", count: 101)] {
            #expect(PlayerCommand.playQueueItem(bad).script == nil, "\(bad)")
        }
    }
    @Test func testUpNextRowKeysUseEntryIDsWithPositionalFallback() {
        func item(_ id: String?, _ t: String) -> BridgeMessage.QueueItem { .init(id: id, title: t) }
        let a = UpNextRowKeys.keyed([item("x1", "A"), item("x2", "B"), item(nil, "C"), item(nil, "D")])
        #expect(a.map(\.key) == ["x1", "x2", "pos-2", "pos-3"])
        // the same song keeps its key when the list shifts (so a pending spinner stays on it)
        let b = UpNextRowKeys.keyed([item("x2", "B"), item(nil, "C")])
        #expect(b.first?.key == "x2")
        // duplicate ids never produce duplicate keys; capped at 10 rows
        #expect(Set(UpNextRowKeys.keyed([item("d", "A"), item("d", "B")]).map(\.key)).count == 2)
        #expect(UpNextRowKeys.keyed((0..<15).map { item("i\($0)", "S\($0)") }).count == 10)
    }
    @Test func testEvalGateResumesExactlyOnce() async {
        let outcome: EvalOutcome = await withCheckedContinuation { cont in
            let gate = EvalGate(cont)
            gate.resume(.timedOut)       // whichever finishes first wins ...
            gate.resume(.value("late"))  // ... a late second result is ignored (no double-resume crash)
            gate.resume(.failed)
        }
        #expect(outcome == .timedOut)
        let timeout = await MainActor.run { PlayerBridge.commandTimeout }
        #expect(timeout == 8)
    }
    @Test func testQueueDecoding() {
        func st(_ frag: String) -> BridgeMessage.StatePayload? {
            guard case .state(let s) = d(#"{"v":1,"type":"state","payload":{"title":"T","isPlaying":true\#(frag)}}"#) else { return nil }
            return s
        }
        #expect(st("")?.queue == nil)                                   // old bridge: backward compatible
        #expect(st("") != nil)
        #expect(st(#","queue":null"#)?.queue == nil)
        let q = st(#","queue":[{"title":"One","artist":"A","artworkURL":"https://m.media-amazon.com/a.jpg"},{"title":"Two"},{"title":" "},{"artist":"No title"},{"title":"Rel","artworkURL":"/a.jpg"}]"#)?.queue
        #expect(q?.map(\.title) == ["One", "Two", "Rel"])        // untitled items dropped
        #expect(q?.first == .init(title: "One", artist: "A", artworkURL: URL(string: "https://m.media-amazon.com/a.jpg")))
        #expect(q?[1].artist == nil); #expect(q?[2].artworkURL == nil)   // non-absolute artwork rejected
        #expect(st(#","queue":"bogus""#)?.queue == nil)                 // wrong type ignored, message still decodes
        #expect(st(#","queue":"bogus""#) != nil)
        let many = (0..<30).map { #"{"title":"S\#($0)"}"# }.joined(separator: ",")
        #expect(st(#","queue":[\#(many)]"#)?.queue?.count == 20)
    }
    @Test func testCommandScripts() {
        #expect(PlayerCommand.refreshQueue.script == "window.__amzBridge.refreshQueue()")
        #expect(PlayerCommand.toggleShuffle.script == "window.__amzBridge.toggleShuffle()")
        #expect(PlayerCommand.cycleRepeat.script == "window.__amzBridge.cycleRepeat()")
    }
    @Test func testPosition() {
        #expect(d(#"{"v":1,"type":"position","payload":{"position":5.5,"duration":100}}"#) == .position(position: 5.5, duration: 100))
    }
    @Test func testError() {
        #expect(d(#"{"v":1,"type":"error","payload":{"code":"c","message":"m"}}"#) == .error(code: "c", message: "m"))
    }
    @Test func testLog() {
        #expect(d(#"{"v":1,"type":"log","payload":{"message":"hi"}}"#) == .log(message: "hi"))
    }
    @Test func testUnknownTypeAndVersion() {
        #expect(d(#"{"v":1,"type":"zzz","payload":{}}"#) == .unknown)
        #expect(d(#"{"v":2,"type":"ready","payload":{}}"#) == .unknown)
        #expect(d(#"{"type":"ready","payload":{}}"#) == .unknown)
        #expect(d("garbage") == .unknown)
    }
    @Test func testNullMissingAndNonFiniteNumbers() {
        guard case .state(let s) = d(#"{"v":1,"type":"state","payload":{"title":"T","duration":null,"isPlaying":false}}"#) else { Issue.record(); return }
        #expect(s.duration == nil); #expect(s.position == nil)
        #expect(d(#"{"v":1,"type":"position","payload":{"position":null,"duration":"x"}}"#) == .position(position: nil, duration: nil))
        // JS JSON.stringify turns NaN/Infinity into null; raw non-finite via body path:
        #expect(BridgeMessage.decode(body: ["v": 1, "type": "position", "payload": ["position": Double.nan]] as [String: Any]) == .unknown)
        #expect(d(#"{"v":1,"type":"position","payload":{"position":1e999}}"#) == .position(position: nil, duration: nil))
    }
    @Test func testArtwork() {
        func art(_ a: String) -> URL? {
            guard case .state(let s) = d(#"{"v":1,"type":"state","payload":{"title":"T","artworkURL":"\#(a)","isPlaying":false}}"#) else { return nil }
            return s.artworkURL
        }
        #expect(art("/img/a.jpg") == nil); #expect(art("a.jpg") == nil); #expect(art("javascript:alert(1)") == nil)
        #expect(art("https://m.media-amazon.com/a.jpg") != nil)
        guard case .state(let s) = d(#"{"v":1,"type":"state","payload":{"title":"T","isPlaying":false}}"#) else { Issue.record(); return }
        #expect(s.artworkURL == nil)
    }
    @Test func testArtworkHostValidation() {
        func ok(_ u: String) -> Bool { URL(string: u).map(ArtworkPolicy.isTrusted) ?? false }
        #expect(ok("https://m.media-amazon.com/images/I/a.jpg"))
        #expect(ok("https://media-amazon.com/a.jpg"))
        #expect(ok("https://images-na.ssl-images-amazon.com/a.jpg"))
        #expect(ok("https://M.MEDIA-AMAZON.COM/a.jpg"))
        #expect(!(ok("http://m.media-amazon.com/a.jpg")))               // not https
        #expect(!(ok("https://evilmedia-amazon.com/a.jpg")))            // no dot boundary
        #expect(!(ok("https://media-amazon.com.evil.example/a.jpg")))   // suffix trick
        #expect(!(ok("https://evil.example/media-amazon.com/a.jpg")))   // path trick
        #expect(!(ok("https://m.media-amazon.com@evil.example/a.jpg"))) // userinfo trick
        #expect(!(ok("https://user:pw@m.media-amazon.com/a.jpg")))
        #expect(!(ok("https://example.com/a.jpg")))
        #expect(!(ok("file:///etc/passwd")))
        #expect(BridgeMessage.safeURL("https://example.com/a.jpg") == nil)
        #expect(BridgeMessage.safeURL("https://m.media-amazon.com/a.jpg") != nil)
        #expect(BridgeMessage.safeURL("https://m.media-amazon.com/" + String(repeating: "a", count: 3000)) == nil)
        // queue artwork goes through the same check
        guard case .state(let s) = d(#"{"v":1,"type":"state","payload":{"title":"T","isPlaying":true,"queue":[{"title":"a","artworkURL":"https://evil.example/x.jpg"},{"title":"b","artworkURL":"https://m.media-amazon.com/x.jpg"}]}}"#) else { Issue.record(); return }
        #expect(s.queue?[0].artworkURL == nil); #expect(s.queue?[1].artworkURL != nil)
    }
    @Test func testOriginPolicy() {
        func ok(_ host: String?, scheme: String? = "https", main: Bool = true, cfg: String? = nil) -> Bool {
            BridgeOriginPolicy.isAllowed(isMainFrame: main, scheme: scheme, host: host, configuredHost: cfg)
        }
        #expect(ok("music.amazon.com")); #expect(ok("music.amazon.co.uk")); #expect(ok("MUSIC.AMAZON.DE"))
        #expect(!(ok("music.amazon.com", main: false)))        // sub-frame
        #expect(!(ok("music.amazon.com", scheme: "http")))                      // not https
        #expect(!(ok("music.amazon.com", scheme: nil))); #expect(!(ok(nil)))
        #expect(!(ok("music.amazon.com.evil.example")))                 // suffix trick
        #expect(!(ok("evilmusic.amazon.com")))
        #expect(!(ok("www.amazon.com")))                                // not the music host
        #expect(!(ok("evil.example")))
        #expect(!(ok("music.amazon.ch")))                               // not a preset, not configured
        #expect(ok("music.amazon.ch", cfg: "music.amazon.ch"))        // configured region host
        #expect(!(ok("evil.example", cfg: "evil.example")))             // configured must still be music.amazon.*
    }
    @Test func testOversizedMessageLimits() {
        // Oversized serialized message -> dropped, no crash.
        let big = String(repeating: "x", count: BridgeMessage.Limits.maxMessageBytes + 10)
        #expect(BridgeMessage.decode(Data((#"{"v":1,"type":"log","payload":{"message":""# + big + #""}}"#).utf8)) == .unknown)
        // Huge array in a raw body is truncated BEFORE serialization.
        let items: [[String: Any]] = (0..<5000).map { ["title": "S\($0)", "artist": "A"] }
        let body: [String: Any] = ["v": 1, "type": "state", "payload": ["title": "T", "isPlaying": true, "queue": items]]
        guard case .state(let s) = BridgeMessage.decode(body: body) else { Issue.record("should decode truncated"); return }
        #expect(s.queue?.count == BridgeMessage.Limits.maxQueueItems)
        #expect(s.queue?.first?.title == "S0")
        // Long strings are truncated (title/artist 300, giant strings cut at 2048 first).
        let long = String(repeating: "y", count: 1_000_000)
        let b2: [String: Any] = ["v": 1, "type": "state", "payload": ["title": long, "artist": long, "isPlaying": true,
                                  "queue": [["title": long, "artist": long, "artworkURL": long]]]]
        guard case .state(let s2) = BridgeMessage.decode(body: b2) else { Issue.record(); return }
        #expect(s2.title?.count == BridgeMessage.Limits.maxTextLength)
        #expect(s2.artist?.count == BridgeMessage.Limits.maxTextLength)
        #expect(s2.queue?.first?.title.count == BridgeMessage.Limits.maxTextLength)
        #expect(s2.queue?.first?.artist?.count == BridgeMessage.Limits.maxTextLength)
        #expect(s2.queue?.first?.artworkURL == nil)
        // Deeply nested / non-JSON values never crash.
        var nested: Any = "leaf"; for _ in 0..<200 { nested = ["a": nested] }
        _ = BridgeMessage.decode(body: ["v": 1, "type": "state", "payload": ["title": "T", "x": nested, "d": Date()]] as [String: Any])
    }
    @Test func testBodyDictionary() {
        #expect(BridgeMessage.decode(body: ["v": 1, "type": "log", "payload": ["message": "x"]] as [String: Any]) == .log(message: "x"))
        #expect(BridgeMessage.decode(body: "str") == .unknown)
    }
}
