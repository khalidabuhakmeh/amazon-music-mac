import AppIntents
import SwiftUI

@main
struct AmazonMusicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings: AppSettings
    @State private var web: WebController
    @State private var player: PlayerState
    @State private var bridge: PlayerBridge
    private let nowPlaying: NowPlayingController // strong ref for app lifetime
    private let notifications: NotificationController // strong ref for app lifetime

    init() {
        let mode = LaunchMode.current
        let s = AppSettings()
        let w = WebController(settings: s) // creates the WKWebView but does not load anything
        let p = PlayerState()
        let b = PlayerBridge(state: p)
        AppDelegate.pending = (p, b)
        AppDelegate.pendingWeb = w
        let np = NowPlayingController(state: p, bridge: b)
        let nc = NotificationController(state: p, settings: s, dryRun: mode != .normal)
        nc.onOpenMainWindow = { MainWindowCoordinator.shared.open() }
        if mode == .normal {
            AppDependencyManager.shared.add(dependency: b)
            AppDependencyManager.shared.add(dependency: p)
            // Order matters: register script + handler first, THEN the first load.
            b.install(on: w)
            w.installHideSections()
            w.start()
            np.start()
            nc.start()
        } // --snapshot/--selftest: no bridge, no load, no integrations; AppDelegate runs the runner and exits.
        nowPlaying = np
        notifications = nc
        _settings = State(initialValue: s)
        _web = State(initialValue: w)
        _player = State(initialValue: p)
        _bridge = State(initialValue: b)
    }

    var body: some Scene {
        Window("Amazon Music", id: "main") {
            MainWindow()
                .environment(web)
                .environment(settings)
                .environment(player)
                .environment(bridge)
        }
        .defaultSize(width: 1100, height: 760)
        .defaultLaunchBehavior(LaunchMode.current == .normal ? .automatic : .suppressed)
        .commands { AboutCommands(player: player) }
        .commands { PlayerCommands(player: player, bridge: bridge, web: web) }

        MenuBarExtra(isInserted: LaunchMode.current == .normal ? Bindable(settings).showMenuBar : .constant(false)) {
            MiniPlayerView()
                .environment(player)
                .environment(bridge)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(settings)
                .environment(web)
                .environment(player)
                .environment(bridge)
                .environment(notifications)
        }
    }
}
