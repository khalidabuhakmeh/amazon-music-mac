import AppKit
import SwiftUI

/// `--snapshot`: renders every surface in light and dark to PNGs from fixtures, with no web view loading and no network.
/// Method: host the SwiftUI view in an offscreen borderless NSWindow (ImageRenderer draws Form/glass blank),
/// then `bitmapImageRepForCachingDisplay` + `cacheDisplay`.
@MainActor
enum SnapshotRunner {
    enum Appearance: String, CaseIterable {
        case light, dark
        var name: NSAppearance.Name { self == .light ? .aqua : .darkAqua }
    }

    /// Surface names (file stem before `-light`/`-dark`), in render order.
    static var surfaceNames: [String] {
        PlayerStateFixtures.allCases.map { "miniplayer-\($0.rawValue)" }
        + SettingsTab.allCases.map { "settings-\($0.rawValue)" } + ["about"]
    }

    static func run(outDir: URL) -> Int32 {
        do { try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true) }
        catch { fputs("SNAPSHOT FAIL cannot create \(outDir.path): \(error)\n", stderr); return 1 }

        // Isolated defaults: nothing here may touch the user's real settings.
        let suite = "amazonmusic.snapshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let web = WebController(settings: settings) // constructs a WKWebView but never loads (no start())
        let notifications = NotificationController(state: PlayerState(), settings: settings, dryRun: true)

        var failures = 0
        func emit(_ stem: String, _ size: NSSize?, chrome: Bool = false, _ make: (Appearance) -> NSView) {
            for appearance in Appearance.allCases {
                let url = outDir.appendingPathComponent("\(stem)-\(appearance.rawValue).png")
                if let png = render(make(appearance), size: size, appearance: appearance, chrome: chrome) {
                    do { try png.write(to: url); print("SNAPSHOT \(url.path)") }
                    catch { fputs("SNAPSHOT FAIL \(url.path): \(error)\n", stderr); failures += 1 }
                } else {
                    fputs("SNAPSHOT FAIL \(stem)-\(appearance.rawValue): render failed\n", stderr); failures += 1
                }
            }
        }

        for f in PlayerStateFixtures.allCases {
            let (s, b) = f.make()
            emit("miniplayer-\(f.rawValue)", nil) { _ in
                NSHostingView(rootView: MiniPlayerView(upNextExpanded: f.upNextExpanded).environment(s).environment(b))
            }
        }
        let (ps, pb) = PlayerStateFixtures.playing.make()
        for tab in SettingsTab.allCases {
            emit("settings-\(tab.rawValue)", nil, chrome: true) { _ in
                NSHostingView(rootView: SettingsView(tab: tab, loginItem: FakeLoginItem(status: .disabled))
                    .environment(settings).environment(web).environment(ps).environment(pb).environment(notifications))
            }
        }
        emit("about", nil) { _ in aboutView() }

        print(failures == 0 ? "SNAPSHOT done \(outDir.path)" : "SNAPSHOT finished with \(failures) failure(s)")
        return failures == 0 ? 0 : 1
    }

    static func render(_ view: NSView, size: NSSize?, appearance: Appearance, chrome: Bool = false) -> Data? {
        let nsAppearance = NSAppearance(named: appearance.name)
        view.appearance = nsAppearance
        let fit = view.fittingSize
        let s = size ?? NSSize(width: max(fit.width, 1), height: max(fit.height, 1))
        _ = chrome
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: s), styleMask: chrome ? [.titled] : [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = nsAppearance
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = false
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        view.frame = NSRect(origin: .zero, size: s)
        window.contentView = view
        if chrome { window.makeKeyAndOrderFront(nil) } // key window: selected tab/segment draws in its active style
        else { window.orderFrontRegardless() } // offscreen but ordered in, so materials/Forms actually draw
        pump(chrome ? 1.0 : 0.4)
        if chrome { window.display() }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        // chrome: capture the whole window frame (title bar / tab strip), not just the content view.
        let target: NSView = chrome ? (view.superview?.superview ?? view) : view
        target.displayIfNeeded()
        guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else { window.close(); return nil }
        target.cacheDisplay(in: target.bounds, to: rep)
        window.close()
        return rep.representation(using: .png, properties: [:])
    }

    static func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Native-looking About content (icon, name, version, credits), built from `AboutInfo`/`AboutPanel.credits`.
    private static func aboutView() -> NSView {
        let info = AboutInfo.current(bridgeVersion: "1.0.0")
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 96).isActive = true
        let name = NSTextField(labelWithString: "Amazon Music")
        name.font = .systemFont(ofSize: 16, weight: .bold)
        let version = NSTextField(labelWithString: "Version \(info.versionLine)")
        version.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        version.textColor = .secondaryLabelColor
        let credits = NSTextField(labelWithAttributedString: AboutPanel.credits(info))
        credits.alignment = .center
        credits.maximumNumberOfLines = 0
        credits.preferredMaxLayoutWidth = 300
        credits.lineBreakMode = .byWordWrapping
        let stack = BackgroundStackView(views: [icon, name, version, credits])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        return stack
    }
}

/// Stack view that paints the window background itself (cacheDisplay of a bare content view skips the window's frame view).
private final class BackgroundStackView: NSStackView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        super.draw(dirtyRect)
    }
}
