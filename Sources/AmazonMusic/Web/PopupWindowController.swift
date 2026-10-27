import AppKit
import WebKit

/// Child window hosting a popup (window.open) web view that shares the parent configuration.
@MainActor
final class PopupWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    let webView: WKWebView
    var onClose: ((PopupWindowController) -> Void)?

    init(configuration: WKWebViewConfiguration, userAgent: String?,
         navigationDelegate: WKNavigationDelegate, uiDelegate: WKUIDelegate) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = navigationDelegate
        webView.uiDelegate = uiDelegate
        webView.customUserAgent = userAgent
        #if DEBUG
        webView.isInspectable = true
        #endif
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        super.init()
        window.contentView = webView
        window.title = "Amazon Music Sign In"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window.close() }

    func windowWillClose(_ notification: Notification) {
        window.delegate = nil
        onClose?(self)
    }
}
