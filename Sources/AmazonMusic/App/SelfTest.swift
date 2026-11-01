import AppKit
import Foundation

/// `--selftest`: network-free checks. Prints `PASS <name>` / `FAIL <name>: reason`; exit code 0 only if everything passed.
@MainActor
enum SelfTest {
    /// Every SF Symbol name used in Sources (later fed by the shared action catalog).
    static var symbolNames: [String] = [
        "gearshape", "bell", "wrench.and.screwdriver",
        "chevron.down", "chevron.right", "chevron.left", "music.note", "play.fill", "pause.fill",
        "repeat", "repeat.1", "backward.end.fill", "forward.end.fill", "shuffle",
        "heart", "heart.fill", "dot.radiowaves.left.and.right", "arrow.clockwise", "house",
    ]

    /// Expected menu item titles per top-level menu (filled in with the Controls menu).
    static let expectedMenuTitles: [String: [String]] = [
        "Controls": ["Play", "Next", "Previous", "Like", "Shuffle", "Repeat: Off", "Play Similar"],
        "View": ["Back", "Forward", "Reload", "Home"],
    ]

    static func run() async -> Int32 {
        var failed = false
        func report(_ name: String, _ error: String?) {
            if let error { print("FAIL \(name): \(error)"); failed = true } else { print("PASS \(name)") }
        }
        report("sf-symbols", checkSymbols())
        report("menu-titles", checkMenuTitles())
        report("integrations-smoke", await integrationsSmoke())
        return failed ? 1 : 0
    }

    static func checkSymbols() -> String? {
        let missing = (symbolNames + PlayerAction.allCases.map(\.systemImage)).filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        return missing.isEmpty ? nil : "unresolved symbols: \(missing.joined(separator: ", "))"
    }

    static func checkMenuTitles() -> String? {
        guard !expectedMenuTitles.isEmpty else { return nil } // stub until the Controls menu exists
        var problems: [String] = []
        for (menu, titles) in expectedMenuTitles.sorted(by: { $0.key < $1.key }) {
            guard let m = NSApp.mainMenu?.items.first(where: { $0.title == menu })?.submenu else { problems.append("missing menu \(menu)"); continue }
            let have = Set(m.items.map(\.title))
            for t in titles where !have.contains(t) { problems.append("\(menu) lacks \(t)") }
        }
        return problems.isEmpty ? nil : problems.joined(separator: "; ")
    }

    /// Starts Now Playing + notification controllers on fixture state, mutates it for ~2s, stops. No web view, no real notifications.
    static func integrationsSmoke() async -> String? {
        let suite = "amazonmusic.selftest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let (state, bridge) = PlayerStateFixtures.playing.make()
        let np = NowPlayingController(state: state, bridge: bridge, mode: .override)
        let nc = NotificationController(state: state, settings: settings, dryRun: true)
        np.start(); nc.start()
        let deadline = Date().addingTimeInterval(2)
        var n = 0
        while Date() < deadline {
            n += 1
            state.apply(.state(.init(trackId: "t\(n)", title: "Song \(n)", artist: "A", album: "B", artworkURL: nil,
                                     duration: 200, position: 10, isPlaying: n % 2 == 0)))
            try? await Task.sleep(for: .milliseconds(250))
        }
        np.stop()
        return state.track?.title == "Song \(n)" ? nil : "state did not follow updates"
    }
}
