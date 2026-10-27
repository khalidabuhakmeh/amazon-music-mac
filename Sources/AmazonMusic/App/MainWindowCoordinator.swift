import AppKit
import SwiftUI
import WebKit

/// Single entry point for "show the main window", used by the Dock reopen handler,
/// notification clicks and the menu bar "Open Amazon Music" button.
///
/// How playback survives window close (no private API):
///  * `WebController` (owned by the App struct) owns the only WKWebView, so it is never deallocated.
///  * When the main window closes we reparent the web view into `parkingWindow`, a tiny borderless,
///    fully transparent, click-through window that stays *ordered in* (on-screen from WebKit's view),
///    so the web view stays in a visible window hierarchy and is not treated as detached/hidden.
///  * On reopen, `MusicWebView.makeNSView` returns the same instance (SwiftUI re-parents it) and
///    `reattach` also re-parents it explicitly. No reload happens anywhere in this path.
///  * The main NSWindow has `isReleasedWhenClosed = false`, so close only hides it.
@MainActor
final class MainWindowCoordinator {
    static let shared = MainWindowCoordinator()

    private(set) weak var mainWindow: NSWindow?
    /// Set from the SwiftUI scene (captures `openWindow`), used when the window was torn down.
    var openWindowAction: (() -> Void)?
    private var closeObserver: NSObjectProtocol?
    private weak var webView: WKWebView?

    private lazy var parkingWindow: NSWindow = {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.alphaValue = 0
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.isExcludedFromWindowsMenu = true
        w.setAccessibilityElement(false)
        w.level = .normal
        w.collectionBehavior = [.transient, .ignoresCycle, .stationary, .canJoinAllSpaces]
        w.setFrameOrigin(NSPoint(x: -20000, y: -20000)) // off-screen; still "ordered in"
        return w
    }()

    /// Called by the window accessor once the main NSWindow exists.
    func register(window: NSWindow, webView: WKWebView) {
        self.webView = webView
        guard mainWindow !== window else { return }
        mainWindow = window
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("MainWindow") // fallback frame persistence for Window scenes
        if let o = closeObserver { NotificationCenter.default.removeObserver(o) }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.park() }
        }
    }

    private func park() {
        guard let webView else { return }
        let host = parkingWindow
        if webView.window !== host {
            webView.removeFromSuperview()
            webView.frame = host.contentView?.bounds ?? .zero
            webView.autoresizingMask = [.width, .height]
            host.contentView?.addSubview(webView)
        }
        host.orderFrontRegardless()
    }

    var isMainWindowVisible: Bool { mainWindow?.isVisible ?? false }

    func open() {
        NSApp.activate()
        if let w = mainWindow {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
        } else if let open = openWindowAction {
            open()
        } else {
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
    }
}

/// Invisible helper that hands the hosting NSWindow to the coordinator.
struct WindowAccessor: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> NSView { AccessorView(webView: webView) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class AccessorView: NSView {
        let webView: WKWebView
        init(webView: WKWebView) { self.webView = webView; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            let wv = webView
            Task { @MainActor in MainWindowCoordinator.shared.register(window: window, webView: wv) }
        }
    }
}
