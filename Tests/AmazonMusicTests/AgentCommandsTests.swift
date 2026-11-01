import Foundation
import Testing
@testable import AmazonMusic

@MainActor
struct AgentCommandsTests {
    private func context(_ fixture: PlayerStateFixtures) -> AgentContext {
        let (player, bridge) = fixture.make()
        return AgentContext(player: player, bridge: bridge, web: WebController(settings: AppSettings()), readyTimeout: .zero)
    }

    private func call(_ command: String, _ args: [String: String] = [:], _ fixture: PlayerStateFixtures = .playing) async -> JSONObject {
        let request = JSON.data(["command": command, "args": args])
        let reply = await AgentRouter.handle(request, context: context(fixture))
        return (try? JSONSerialization.jsonObject(with: reply) as? JSONObject) ?? [:]
    }

    private func code(_ reply: JSONObject) -> String? { (reply["error"] as? JSONObject)?["code"] as? String }

    // MARK: Parsing

    @Test func parsesOptionsAndPositionals() throws {
        let seek = try #require(AgentCommands.all.first { $0.name == "player seek" })
        #expect(try AgentCLI.parse(["--seconds", "90"], for: seek) == ["seconds": "90"])
        let list = try #require(AgentCommands.all.first { $0.name == "queue list" })
        #expect(try AgentCLI.parse(["--limit", "5", "--offset", "2"], for: list) == ["limit": "5", "offset": "2"])
    }

    @Test func rejectsBadArguments() throws {
        let seek = try #require(AgentCommands.all.first { $0.name == "player seek" })
        for bad in [["--seconds", "nan"], ["--seconds", "inf"], ["--seconds", "-5"], ["--seconds", "abc"], [], ["--bogus", "1"], ["--seconds"]] {
            #expect(throws: AgentError.self) { try AgentCLI.parse(bad, for: seek) }
            do { _ = try AgentCLI.parse(bad, for: seek) } catch let e as AgentError { #expect(e.exit == 2) }
        }
    }

    @Test func everyCommandHasSummaryExampleAndSchema() {
        let names = AgentCommands.all.map(\.name)
        #expect(Set(names).count == names.count)
        for c in AgentCommands.all {
            #expect(!c.summary.isEmpty && c.example.hasPrefix("amazonmusic "))
            let schema = AgentCLI.schema(c)
            #expect((schema["inputSchema"] as? JSONObject)?["type"] as? String == "object")
            #expect(c.destructive == false)
        }
        #expect(AgentCommands.all.filter(\.readOnly).map(\.name) == ["status", "track show", "queue list"])
    }

    // MARK: Result shapes

    @Test func trackShowShape() async {
        let r = await call("track show")
        let t = r["result"] as? JSONObject
        #expect(r["ok"] as? Bool == true)
        for key in ["hasTrack", "title", "artist", "album", "position", "duration", "isPlaying", "liked", "shuffle", "repeat", "healthy"] {
            #expect(t?[key] != nil, "missing \(key)")
        }
        #expect(t?["isPlaying"] as? Bool == true)
    }

    @Test func trackShowWhenSignedOutIsEmptyShape() async {
        let t = await call("track show", [:], .bridgeUnhealthy)["result"] as? JSONObject
        #expect(t?["hasTrack"] as? Bool == false)
        #expect(t?["healthy"] as? Bool == false)
        #expect(t?["title"] is NSNull)
    }

    @Test func statusShape() async {
        let t = await call("status", [:], .noTrack)["result"] as? JSONObject
        #expect(t?["running"] as? Bool == true)
        #expect(t?["ready"] as? Bool == false)
        #expect(t?["page"] != nil)
    }

    @Test func queueListPages() async throws {
        let r = try #require(await call("queue list", ["limit": "3", "offset": "1"], .upNextExpanded)["result"] as? JSONObject)
        #expect((r["items"] as? [JSONObject])?.count == 3)
        #expect(r["total"] as? Int == 10)
        #expect(r["nextOffset"] as? Int == 4)
        let all = try #require(await call("queue list", [:], .upNextExpanded)["result"] as? JSONObject)
        #expect(all["nextOffset"] == nil)
    }

    // MARK: Errors

    @Test func writesNeedTheBridge() async {
        for name in ["player play", "player next", "player shuffle", "track like", "track similar"] {
            #expect(code(await call(name)) == "bridge_unavailable", "\(name)")
        }
        let msg = (await call("player play")["error"] as? JSONObject)?["message"] as? String
        #expect(msg?.contains("Open Amazon Music and sign in") == true)
    }

    @Test func seekValidatesBeforeTouchingTheBridge() async {
        for bad in ["nan", "-1", "inf", "x"] { #expect(code(await call("player seek", ["seconds": bad])) == "usage") }
        #expect(code(await call("player seek", ["seconds": "10"])) == "bridge_unavailable")
    }

    @Test func queuePlayValidatesIDs() async {
        #expect(code(await call("queue play", ["id": "x;alert(1)"], .upNextExpanded)) == "usage")
        #expect(code(await call("queue play", ["id": "nope"], .upNextExpanded)) == "not_found")
        #expect(code(await call("queue play", ["id": "q1"], .upNextExpanded)) == "bridge_unavailable") // valid + present, bridge not ready
    }

    @Test func openReusesURLRouterValidation() async {
        for bad in ["//evil.com", "/a/../b", "search", "/x\\y", "/%2e%2e/x", "https://evil.com/"] {
            #expect(code(await call("open", ["path": bad])) == "usage", "\(bad)")
        }
    }

    @Test func routerRejectsBadRequests() async {
        let c = context(.playing)
        for raw in ["not json", "{}", "{\"command\":\"nope\"}", "{\"command\":\"status\",\"args\":{\"x\":\"1\"}}",
                    "{\"command\":\"status\",\"args\":{\"x\":1}}", "{\"command\":\"player seek\"}"] {
            let reply = await AgentRouter.handle(Data(raw.utf8), context: c)
            let object = try? JSONSerialization.jsonObject(with: reply) as? JSONObject
            #expect(object?["ok"] as? Bool == false, "\(raw)")
            #expect((object?["error"] as? JSONObject)?["code"] as? String == "usage", "\(raw)")
        }
    }
}
