import Foundation
import Observation
import OSLog
import WebKit

@MainActor @Observable
final class PlayerBridge {
    static let handlerName = "amazonMusic"
    static let watchdogSeconds: Double = 15
    private static let log = Logger(subsystem: "com.khalidabuhakmeh.amazonmusic", category: "bridge")

    @ObservationIgnored let state: PlayerState
    @ObservationIgnored private weak var web: WebController?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var proxy: HandlerProxy?

    init(state: PlayerState) { self.state = state }

    /// Registers script + handler. MUST be called before the first page load.
    func install(on web: WebController) {
        self.web = web
        let proxy = HandlerProxy(self)
        self.proxy = proxy
        web.addMessageHandler(proxy, name: Self.handlerName)
        if let url = Bundle.main.url(forResource: "bridge", withExtension: "js"),
           let src = try? String(contentsOf: url, encoding: .utf8) {
            web.addUserScript(WKUserScript(source: src, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        } else {
            Self.log.error("bridge.js missing from bundle")
            state.markUnhealthy("bridge.js missing from app bundle")
        }
        web.onNavigationStart = { [weak self] in self?.startWatchdog() }
        startWatchdog()
    }

    func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.watchdogSeconds))
            guard !Task.isCancelled, let self else { return }
            Self.log.error("watchdog: no ready within \(Self.watchdogSeconds)s")
            self.state.markUnhealthy("Bridge did not report ready")
        }
    }

    func handle(body: Any) {
        let msg = BridgeMessage.decode(body: body)
        if case .ready = msg { watchdog?.cancel(); watchdog = nil }
        let before = (state.track?.identity, state.isPlaying, state.bridgeHealthy)
        state.apply(msg)
        switch msg {
        case .log(let m): Self.log.debug("js: \(m ?? "", privacy: .public)")
        case .unknown: Self.log.debug("unknown bridge message")
        case .error(let c, let m): Self.log.error("bridge error \(c ?? "-", privacy: .public): \(m ?? "-", privacy: .public)")
        default:
            let after = (state.track?.identity, state.isPlaying, state.bridgeHealthy)
            if before != after {
                Self.log.info("state: track=\(self.state.track?.title ?? "nil", privacy: .public) playing=\(after.1) healthy=\(after.2)")
            }
        }
    }

    /// Like/unlike the current track: optimistic UI update, reverted if the command fails or isn't confirmed in time.
    func toggleLike() async {
        guard state.beginOptimisticLike() != nil else { return }
        let ok = await send(.toggleLike).ok
        if !ok { state.clearOptimisticLike(); return }
        try? await Task.sleep(for: .seconds(PlayerState.optimisticWindow))
        state.clearOptimisticLike()
    }

    /// Shuffle on/off: optimistic UI update, reverted if the command fails or isn't confirmed in time.
    func toggleShuffle() async {
        guard state.beginOptimisticShuffle() != nil else { return }
        let ok = await send(.toggleShuffle).ok
        if !ok { state.clearOptimisticShuffle(); return }
        try? await Task.sleep(for: .seconds(PlayerState.optimisticWindow))
        state.clearOptimisticShuffle()
    }

    /// Advances repeat off -> all -> one -> off (the page's own cycle), optimistically.
    func cycleRepeat() async {
        guard state.beginOptimisticRepeat() != nil else { return }
        let ok = await send(.cycleRepeat).ok
        if !ok { state.clearOptimisticRepeat(); return }
        try? await Task.sleep(for: .seconds(PlayerState.optimisticWindow))
        state.clearOptimisticRepeat()
    }

    /// Sends a command to the page. Failures are logged (command name + reason only) and returned; never silent.
    @discardableResult
    func send(_ command: PlayerCommand) async -> CommandResult {
        let name = "\(command)"
        guard let body = command.asyncBody else {
            Self.log.error("command \(name, privacy: .public) rejected: invalid arguments")
            return .failure("invalid_argument")
        }
        guard let web else {
            Self.log.error("command \(name, privacy: .public) dropped: no web view")
            return .failure("no_web_view")
        }
        do {
            let result = CommandResult.parse(try await web.evaluateAsync(body))
            if result.ok {
                Self.log.info("command \(name, privacy: .public) ok via=\(result.via ?? "-", privacy: .public) changed=\(result.changed.map(String.init) ?? "-", privacy: .public)")
            } else {
                Self.log.error("command \(name, privacy: .public) failed: \(result.reason ?? "-", privacy: .public)")
            }
            return result
        } catch {
            Self.log.error("command \(name, privacy: .public) threw: \(error.localizedDescription, privacy: .public)")
            return .failure("evaluate_failed")
        }
    }
}

/// Weak proxy so WKUserContentController doesn't retain the bridge.
@MainActor
private final class HandlerProxy: NSObject, WKScriptMessageHandler {
    weak var target: PlayerBridge?
    init(_ t: PlayerBridge) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.handle(body: message.body)
    }
}
