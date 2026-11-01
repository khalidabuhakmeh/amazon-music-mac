import Foundation

/// Everything an agent can do in Amazon Music. Add a command here and the CLI, `help` and the MCP
/// tools all get it. Each `run` is on the main actor and goes through `bridge.send`, the same path
/// as the buttons, menus and Shortcuts. There are no destructive commands.
nonisolated enum AgentCommands {
    static let all: [AgentCommand] = [
        AgentCommand(name: "status", summary: "Show whether the app runs, the bridge is healthy and signed in, and the open page path.",
                     example: "amazonmusic status --json", readOnly: true) { _, ctx in statusJSON(ctx) },
        AgentCommand(name: "track show", summary: "Show the current track: title, artist, album, position, duration, play, like, shuffle, repeat.",
                     example: "amazonmusic track show --json", readOnly: true) { _, ctx in trackJSON(ctx.player) },
        AgentCommand(name: "queue list", summary: "List the Up Next queue (ids work with `queue play`).",
                     params: [.init(name: "limit", kind: .integer, help: "at most this many (default 50)"),
                              .init(name: "offset", kind: .integer, help: "skip this many, for the next page")],
                     example: "amazonmusic queue list --limit 10 --json", readOnly: true) { args, ctx in
            try queueJSON(ctx.player, limit: try args.int("limit", default: 50), offset: try args.int("offset", default: 0))
        },
        action("player play", .play, "Start or resume playback."),
        action("player pause", .pause, "Pause playback."),
        action("player toggle", .toggle, "Toggle play and pause."),
        action("player next", .next, "Skip to the next track."),
        action("player previous", .previous, "Go to the previous track."),
        action("player shuffle", .shuffle, "Toggle shuffle."),
        action("player repeat", .repeatMode, "Cycle repeat: off, all, one."),
        AgentCommand(name: "player seek", summary: "Jump to a position in the current track.",
                     params: [.init(name: "seconds", kind: .number, required: true, help: "position in seconds (finite, 0 or more)")],
                     example: "amazonmusic player seek --seconds 90") { args, ctx in
            let seconds = try args.seconds("seconds")
            try await requireBridge(ctx)
            let result = await ctx.bridge.send(.seek(seconds))
            return try outcome("seek", result, extra: ["seconds": seconds])
        },
        AgentCommand(name: "track like", summary: "Like the current track. Already liked: changed is false.",
                     example: "amazonmusic track like --json") { _, ctx in
            try await requireBridge(ctx)
            guard let liked = ctx.player.isLiked else { throw AgentError.invalid("no like control for the current track. Play a track first (`amazonmusic track show`)") }
            if liked { return ["action": "like", "liked": true, "changed": false] }
            return try outcome("like", await ctx.bridge.send(PlayerAction.like.command), extra: ["liked": true])
        },
        AgentCommand(name: "track similar", summary: "Start a station of similar music for the current track.",
                     example: "amazonmusic track similar") { _, ctx in
            try await requireBridge(ctx)
            guard ctx.player.canPlaySimilar else { throw AgentError.invalid("Play Similar is not available for the current item. Play a track first") }
            return try outcome("similar", await ctx.bridge.send(PlayerAction.similar.command))
        },
        AgentCommand(name: "queue play", summary: "Jump to an Up Next entry by id.",
                     params: [.init(name: "id", required: true, help: "an id from `queue list`")],
                     example: "amazonmusic queue play --id 5b2f1c0e") { args, ctx in
            let raw = try args.required("id")
            guard let id = BridgeMessage.validQueueItemID(raw) else {
                throw AgentError.usage("--id must be 1-100 characters of letters, digits and - _ . : . Run `amazonmusic queue list`")
            }
            guard ctx.player.upNext.contains(where: { $0.id == id }) else {
                throw AgentError.notFound("no queue entry with id \(id). Run `amazonmusic queue list`")
            }
            try await requireBridge(ctx)
            guard ctx.player.canJumpToQueueItem else { throw AgentError.invalid("the page cannot jump to queue entries right now") }
            return try outcome("queue play", await ctx.bridge.send(.playQueueItem(id)), extra: ["id": id])
        },
        AgentCommand(name: "open", summary: "Show a music.amazon.com page in the window. The path is validated like amazonmusic://open links.",
                     params: [.init(name: "path", required: true, help: "path starting with /, like /search?q=jazz (percent-encoded)")],
                     example: "amazonmusic open --path /search?q=jazz") { args, ctx in
            let raw = try args.required("path")
            guard let path = URLRouter.validate(path: raw) else {
                throw AgentError.usage("--path must be a music.amazon.com path starting with /, percent-encoded ASCII, at most \(URLRouter.maxPathLength) characters. Example: amazonmusic open --path /search?q=jazz")
            }
            MainWindowCoordinator.shared.open()
            ctx.web.open(path: path)
            return ["opened": path]
        },
    ]

    // MARK: Builders

    private static func action(_ name: String, _ action: PlayerAction, _ summary: String) -> AgentCommand {
        AgentCommand(name: name, summary: summary, example: "amazonmusic \(name)") { _, ctx in
            try await requireBridge(ctx)
            return try outcome(action.rawValue, await ctx.bridge.send(action.command))
        }
    }

    /// Writes need the page bridge: wait briefly, then say how to fix it.
    @MainActor
    static func requireBridge(_ ctx: AgentContext) async throws {
        let deadline = ContinuousClock.now + ctx.readyTimeout
        while !ctx.bridge.isReady, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard ctx.bridge.isReady, ctx.player.bridgeHealthy else { throw AgentError.bridgeUnavailable }
    }

    static func outcome(_ name: String, _ result: CommandResult, extra: JSONObject = [:]) throws -> JSONObject {
        guard result.ok else {
            throw AgentError.invalid("\(name) failed: \((result.reason ?? "unknown error").replacingOccurrences(of: "_", with: " ")). Check `amazonmusic status`")
        }
        var out: JSONObject = ["action": name, "ok": true]
        if let changed = result.changed { out["changed"] = changed }
        for (key, value) in extra where out[key] == nil { out[key] = value }
        return out
    }

    // MARK: Result shapes

    @MainActor
    static func statusJSON(_ ctx: AgentContext) -> JSONObject {
        let page = ctx.web.webView.url?.path
        return ["running": true, "healthy": ctx.player.bridgeHealthy, "ready": ctx.bridge.isReady,
                "signedIn": ctx.player.signedIn ?? NSNull(), "page": page ?? NSNull(),
                "hasTrack": ctx.player.track != nil, "isPlaying": ctx.player.isPlaying]
    }

    @MainActor
    static func trackJSON(_ p: PlayerState) -> JSONObject {
        let t = p.track
        let position: Any = p.position == nil ? NSNull() : p.interpolatedPosition(at: Date())
        return ["hasTrack": t != nil, "title": t?.title ?? NSNull(), "artist": t?.artist ?? NSNull(), "album": t?.album ?? NSNull(),
                "position": position, "duration": t?.duration ?? NSNull(), "isPlaying": p.isPlaying,
                "liked": p.isLiked ?? NSNull(), "shuffle": p.isShuffled ?? NSNull(), "repeat": p.repeatMode?.rawValue ?? NSNull(),
                "healthy": p.bridgeHealthy]
    }

    @MainActor
    static func queueJSON(_ p: PlayerState, limit: Int, offset: Int) throws -> JSONObject {
        guard limit > 0 else { throw AgentError.usage("--limit must be 1 or more") }
        let page = p.upNext.dropFirst(offset).prefix(limit)
        var result: JSONObject = [
            "items": page.map { ["id": $0.id ?? NSNull(), "title": $0.title, "artist": $0.artist ?? NSNull()] as JSONObject },
            "total": p.upNext.count]
        if offset + page.count < p.upNext.count { result["nextOffset"] = offset + page.count }
        return result
    }
}
