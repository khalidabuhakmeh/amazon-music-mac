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
        let s = AppSettings()
        let w = WebController(settings: s)
        let p = PlayerState()
        let b = PlayerBridge(state: p)
        AppDelegate.pending = (p, b)
        // Order matters: register script + handler first, THEN the first load.
        b.install(on: w)
        w.installHideSections()
        w.start()
        let np = NowPlayingController(state: p, bridge: b)
        np.start()
        nowPlaying = np
        let nc = NotificationController(state: p, settings: s)
        nc.onOpenMainWindow = { MainWindowCoordinator.shared.open() }
        nc.start()
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
        .commands { AboutCommands(player: player) }
        #if DEBUG
        .commands { DebugCommands(bridge: bridge) }
        #endif

        MenuBarExtra(isInserted: Bindable(settings).showMenuBar) {
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

#if DEBUG
struct DebugCommands: Commands {
    let bridge: PlayerBridge
    var body: some Commands {
        CommandMenu("Debug") {
            Button("Play/Pause") { Task { await bridge.send(.toggle) } }
            Button("Next") { Task { await bridge.send(.next) } }
            Button("Previous") { Task { await bridge.send(.previous) } }
            Button("Seek +10s") {
                Task {
                    let p = bridge.state.interpolatedPosition(at: Date())
                    await bridge.send(.seek(p + 10))
                }
            }
        }
    }
}
#endif
