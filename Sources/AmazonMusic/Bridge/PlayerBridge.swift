import Foundation
import Observation
import OSLog
import WebKit

@MainActor @Observable
final class PlayerBridge {
    static let handlerName = "amazonMusic"
    static let watchdogSeconds: Double = 15
    /// A command whose page script never answers is abandoned after this long (so no spinner/pending state can stick).
    static let commandTimeout: Double = 8
    private static let log = Logger(subsystem: "com.khalidabuhakmeh.amazonmusic", category: "bridge")

    @ObservationIgnored let state: PlayerState
    @ObservationIgnored private weak var web: WebController?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var proxy: HandlerProxy?
    /// Host of the configured start URL (extra allowed message origin besides the preset music.amazon.* hosts).
    @ObservationIgnored var configuredHost: @MainActor () -> String? = { nil }

    init(state: PlayerState) { self.state = state }

    /// Registers script + handler. MUST be called before the first page load.
    func install(on web: WebController) {
        self.web = web
        configuredHost = { [weak web] in web?.startHost }
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

    /// "Play Similar Music": badge shows a spinner while it runs; the popover then updates naturally (new track / Up Next).
    /// Failures are logged only. The spinner is cleared after the window (or on failure) no matter how the command ends.
    func playSimilar() async {
        guard state.canPlaySimilar, !state.isSimilarInProgress() else { return }
        state.beginSimilar()
        let clear = Task { [state] in
            try? await Task.sleep(for: .seconds(PlayerState.similarWindow))
            if !Task.isCancelled { state.endSimilar() }
        }
        let result = await send(.playSimilar)
        if !result.ok { clear.cancel(); state.endSimilar() }
    }

    /// Jumps playback to an Up Next entry. The row shows pending until the track changes (PlayerState clears it) or the window ends.
    /// Failures (stale/unknown entry, controller unavailable, timeout) are logged only.
    func playQueueItem(_ id: String) async {
        guard state.canJumpToQueueItem, BridgeMessage.validQueueItemID(id) != nil else { return }
        state.beginJump(to: id)
        let clear = Task { [state] in
            try? await Task.sleep(for: .seconds(PlayerState.jumpWindow))
            if !Task.isCancelled, state.jumpPending?.id == id { state.endJump() }
        }
        let result = await send(.playQueueItem(id))
        if !result.ok { clear.cancel(); if state.jumpPending?.id == id { state.endJump() } }
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
            let outcome = await Self.evaluate(web, body: body, timeout: Self.commandTimeout)
            let result: CommandResult
            switch outcome {
            case .value(let v): result = CommandResult.parse(v)
            case .timedOut: result = .failure("timeout")
            case .failed: throw EvalFailure()
            }
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

struct EvalFailure: Error {}

enum EvalOutcome: Sendable, Equatable { case value(String?), failed, timedOut }

/// Resumes a continuation exactly once, whichever of {result, timeout} gets there first.
final class EvalGate: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<EvalOutcome, Never>?
    init(_ cont: CheckedContinuation<EvalOutcome, Never>) { self.cont = cont }
    func resume(_ outcome: EvalOutcome) {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        c?.resume(returning: outcome)
    }
}

extension PlayerBridge {
    /// Runs a command script with a deadline. A hung WebKit call is abandoned (its late result is ignored), never awaited forever.
    static func evaluate(_ web: WebController, body: String, timeout: Double) async -> EvalOutcome {
        await withCheckedContinuation { (cont: CheckedContinuation<EvalOutcome, Never>) in
            let gate = EvalGate(cont)
            Task { @MainActor in
                do { gate.resume(.value(try await web.evaluateAsync(body) as? String)) } catch { gate.resume(.failed) }
            }
            Task { try? await Task.sleep(for: .seconds(timeout)); gate.resume(.timedOut) }
        }
    }
}

/// Weak proxy so WKUserContentController doesn't retain the bridge.
@MainActor
private final class HandlerProxy: NSObject, WKScriptMessageHandler {
    weak var target: PlayerBridge?
    init(_ t: PlayerBridge) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard BridgeOriginPolicy.isAllowed(isMainFrame: message.frameInfo.isMainFrame, scheme: origin.protocol, host: origin.host,
                                           configuredHost: target?.configuredHost()) else { return }
        target?.handle(body: message.body)
    }
}
