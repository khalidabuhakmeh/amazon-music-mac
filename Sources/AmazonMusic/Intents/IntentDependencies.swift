import AppIntents
import Foundation

struct PlayerUnavailableError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

@MainActor
enum IntentSupport {
    /// Waits up to `timeout` for the web page bridge (intents may launch the app in the background).
    static func send(_ action: PlayerAction, bridge: PlayerBridge, timeout: Duration = .seconds(10)) async throws {
        try await waitUntilReady(bridge, timeout: timeout)
        let r = await bridge.send(action.command)
        if !r.ok {
            let reason = r.reason?.replacingOccurrences(of: "_", with: " ") ?? "unknown error"
            throw PlayerUnavailableError(message: "\(action.title) failed: \(reason).")
        }
    }

    static func waitUntilReady(_ bridge: PlayerBridge, timeout: Duration) async throws {
        let deadline = ContinuousClock.now + timeout
        while !bridge.isReady {
            if ContinuousClock.now >= deadline {
                throw PlayerUnavailableError(message: "Amazon Music isn't ready yet. Open the app and sign in, then try again.")
            }
            try await Task.sleep(for: .milliseconds(200))
        }
    }
}
