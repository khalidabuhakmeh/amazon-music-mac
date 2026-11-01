import Foundation

// The agent interface: one list of commands (AgentCommands.swift) that the CLI, its help
// and the MCP server all read. Commands run inside the app, on the main actor, through the
// same bridge path as the buttons and menus.

typealias JSONObject = [String: Any]

/// One thing an agent can do. Names are "<noun> <verb>": "player play".
nonisolated struct AgentCommand: Sendable {
    struct Param: Sendable {
        enum Kind: String, Sendable { case string, integer, number, boolean }
        var name: String
        var kind: Kind = .string
        var required = false
        var positional = false
        var help: String
    }

    var name: String
    var summary: String
    var params: [Param] = []
    var example: String
    /// Only reads. Agents may run it without asking.
    var readOnly = false
    /// Removes data or cannot be undone. (None of this app's commands are.)
    var destructive = false
    var run: @MainActor @Sendable (Args, AgentContext) async throws -> JSONObject
}

/// What commands may touch: the same objects the window and menus use.
@MainActor
struct AgentContext {
    var player: PlayerState
    var bridge: PlayerBridge
    var web: WebController
    /// How long a write waits for the page bridge before saying "not ready".
    var readyTimeout: Duration = .seconds(3)
}

/// The values a command was called with, checked against its params.
nonisolated struct Args: Sendable {
    var values: [String: String]

    func string(_ name: String) -> String? { values[name] }

    func required(_ name: String) throws -> String {
        guard let value = values[name], !value.isEmpty else { throw AgentError.usage("missing --\(name)") }
        return value
    }

    func int(_ name: String, default fallback: Int) throws -> Int {
        guard let raw = values[name] else { return fallback }
        guard let value = Int(raw), value >= 0 else { throw AgentError.usage("--\(name) must be a whole number of 0 or more, not \"\(raw)\"") }
        return value
    }

    /// A finite number of 0 or more.
    func seconds(_ name: String) throws -> Double {
        let raw = try required(name)
        guard let value = Double(raw), value.isFinite, value >= 0 else {
            throw AgentError.usage("--\(name) must be a finite number of 0 or more, not \"\(raw)\". Example: amazonmusic player seek --seconds 90")
        }
        return value
    }
}

/// An error with a stable code an agent can branch on, a message that says how to fix it, and the CLI exit code.
nonisolated struct AgentError: Error, Sendable {
    var code: String
    var message: String
    var exit: Int32

    static func usage(_ message: String) -> AgentError { AgentError(code: "usage", message: message, exit: 2) }
    static func notFound(_ message: String) -> AgentError { AgentError(code: "not_found", message: message, exit: 3) }
    static func invalid(_ message: String) -> AgentError { AgentError(code: "invalid", message: message, exit: 1) }
    static func unavailable(_ message: String) -> AgentError { AgentError(code: "app_unavailable", message: message, exit: 4) }
    /// The app runs but the web page is not signed in or not loaded.
    static var bridgeUnavailable: AgentError {
        AgentError(code: "bridge_unavailable", message: "Amazon Music is not ready (the page is not loaded or you are signed out). Open Amazon Music and sign in, then try again.", exit: 1)
    }

    var json: JSONObject { ["ok": false, "error": ["code": code, "message": message]] }
}

/// Runs requests from the socket inside the app.
@MainActor
enum AgentRouter {
    static var context: AgentContext?

    /// A request is {"command": "player seek", "args": {"seconds": "90"}}. Always returns one reply object.
    static func handle(_ request: Data, context given: AgentContext? = nil) async -> Data {
        let reply: JSONObject
        do {
            guard let object = try? JSONSerialization.jsonObject(with: request) as? JSONObject,
                  let name = object["command"] as? String else { throw AgentError.usage("bad request: expected {\"command\":...,\"args\":{...}}") }
            guard let command = AgentCommands.all.first(where: { $0.name == name }) else {
                throw AgentError.usage("unknown command \"\(name.prefix(40))\". Run `amazonmusic help`")
            }
            let raw = object["args"] ?? [String: String]()
            guard let values = raw as? [String: String] else { throw AgentError.usage("args must be an object of strings") }
            for key in values.keys where !command.params.contains(where: { $0.name == key }) {
                throw AgentError.usage("\(command.name) has no option --\(key.prefix(40)). Run `amazonmusic help \(command.name)`")
            }
            for param in command.params where param.required && (values[param.name] ?? "").isEmpty {
                throw AgentError.usage("missing --\(param.name). Example: \(command.example)")
            }
            guard let context = given ?? context else { throw AgentError.unavailable("the app is still starting. Try again") }
            reply = ["ok": true, "result": try await command.run(Args(values: values), context)]
        } catch let error as AgentError {
            reply = error.json
        } catch {
            reply = AgentError.invalid(error.localizedDescription).json
        }
        return JSON.data(reply)
    }
}

nonisolated enum JSON {
    static func data(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
    }

    static func string(_ object: Any) -> String {
        String(decoding: data(object), as: UTF8.self)
    }
}

nonisolated enum AgentBinary {
    /// The app's binary, with the ~/.local/bin link followed.
    static var url: URL {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        let path = _NSGetExecutablePath(&buffer, &size) == 0
            ? String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
            : CommandLine.arguments[0]
        return URL(fileURLWithPath: path).resolvingSymlinksInPath()
    }

    static var version: String {
        let plist = url.deletingLastPathComponent().deletingLastPathComponent().appending(path: "Info.plist")
        return NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
