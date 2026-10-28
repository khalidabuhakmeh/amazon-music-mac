// WebPage vs WKWebView decision (docs/SPIKE.md): SDK `WebPage`/`WebView` has no
// createWebView / window.open hook, so popup sign-in cannot be handled. We use
// WKWebView hosted via NSViewRepresentable with WKUIDelegate.createWebViewWith.
//
// Single instance: `WebController` creates exactly one WKWebView in init and is owned by the
// App struct (@State, created once in App.init). `MusicWebView.makeNSView` returns that same
// instance, so the view outlives windows and is never recreated.

import AppKit
import Observation
import SwiftUI
import WebKit

@MainActor @Observable
final class WebController {
    let webView: WKWebView
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let delegate = WebDelegate()
    @ObservationIgnored private let configuration = WKWebViewConfiguration()
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    /// Extension hook for Tasks 4/5: scripts added before first load are injected into every page.
    func addUserScript(_ script: WKUserScript) {
        userScripts.append(script)
        configuration.userContentController.addUserScript(script)
    }
    @ObservationIgnored private var userScripts: [WKUserScript] = []
    @ObservationIgnored private var hideSectionsSource: String?

    /// Loads hideSections.js from the bundle and registers it (main frame, document start) with the current
    /// settings (hidePodcasts, hideAudible, hideGetApp) baked in. Call before the first load, after the bridge install.
    func installHideSections() {
        guard let url = Bundle.main.url(forResource: "hideSections", withExtension: "js"),
              let src = try? String(contentsOf: url, encoding: .utf8) else { return }
        hideSectionsSource = src
        refreshHideSectionsScript()
    }

    /// WKUserScripts can't be edited, so rebuild the set: bridge/other scripts unchanged + hide script with the
    /// current flag, so future page loads start in the right state without a flash.
    private func refreshHideSectionsScript() {
        guard let src = hideSectionsSource else { return }
        let ucc = configuration.userContentController
        ucc.removeAllUserScripts()
        userScripts.forEach { ucc.addUserScript($0) }
        ucc.addUserScript(WKUserScript(source: HideSectionsScript.source(base: src, podcasts: settings.hidePodcasts, audible: settings.hideAudible, getApp: settings.hideGetApp, homeBanner: settings.hideHomeBanner),
                                       injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    /// Applies the setting to the already-loaded page (live toggle, and after each navigation finishes).
    func applyHideSections() {
        guard hideSectionsSource != nil else { return }
        webView.evaluateJavaScript(HideSectionsScript.applyCall(podcasts: settings.hidePodcasts, audible: settings.hideAudible, getApp: settings.hideGetApp, homeBanner: settings.hideHomeBanner), completionHandler: nil)
    }
    func addMessageHandler(_ handler: WKScriptMessageHandler, name: String) {
        configuration.userContentController.add(handler, name: name)
    }
    /// Host of the configured start URL (lowercased), for bridge origin checks.
    var startHost: String? { URLComponents(string: settings.startURL)?.host?.lowercased() }
    func evaluate(_ js: String) async throws -> Any? { try await webView.evaluateJavaScript(js) }
    /// Runs `body` as an async function body in the page world (awaits Promises) and returns its value.
    /// Commands return a JSON string so bridging to Swift never depends on JS object/Promise conversion.
    func evaluateAsync(_ body: String) async throws -> Any? {
        try await webView.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: .page)
    }

    init(settings: AppSettings) {
        self.settings = settings
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = settings.customUserAgent.flatMap { $0.isEmpty ? nil : $0 } ?? Self.safariUserAgent()
        #if DEBUG
        webView.isInspectable = true
        #endif
        delegate.controller = self
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        observations = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] w, _ in
                MainActor.assumeIsolated { self?.canGoBack = w.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] w, _ in
                MainActor.assumeIsolated { self?.canGoForward = w.canGoForward }
            },
        ]
    }

    /// Call once, AFTER the bridge has installed its user script/handler (scripts only apply to loads after registration).
    func start() {
        goHome()
        observeSettings()
    }

    /// Live apply: re-arms itself after each change. UA change => set customUserAgent + reload;
    /// start URL change => load the new URL.
    @ObservationIgnored private var appliedStartURL: String?
    @ObservationIgnored private var appliedUA: String?
    private struct Hide: Equatable { var podcasts: Bool; var audible: Bool; var getApp: Bool; var homeBanner: Bool }
    @ObservationIgnored private var appliedHide = Hide(podcasts: false, audible: false, getApp: false, homeBanner: false)
    private func observeSettings() {
        appliedHide = Hide(podcasts: settings.hidePodcasts, audible: settings.hideAudible, getApp: settings.hideGetApp, homeBanner: settings.hideHomeBanner)
        appliedStartURL = settings.startURL
        appliedUA = settings.customUserAgent
        withObservationTracking {
            _ = settings.startURL
            _ = settings.customUserAgent
            _ = settings.hidePodcasts
            _ = settings.hideAudible
            _ = settings.hideGetApp
            _ = settings.hideHomeBanner
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.settings.customUserAgent != self.appliedUA {
                    self.applyUserAgent()
                    self.reload()
                }
                if Hide(podcasts: self.settings.hidePodcasts, audible: self.settings.hideAudible, getApp: self.settings.hideGetApp, homeBanner: self.settings.hideHomeBanner) != self.appliedHide {
                    self.refreshHideSectionsScript()
                    self.applyHideSections()
                }
                if self.settings.startURL != self.appliedStartURL { self.goHome() }
                self.observeSettings()
            }
        }
    }

    var effectiveUserAgent: String { settings.customUserAgent.flatMap { $0.isEmpty ? nil : $0 } ?? Self.safariUserAgent() }
    private func applyUserAgent() { webView.customUserAgent = effectiveUserAgent }

    /// Removes all cookies/storage (logs the user out), then reloads.
    func resetWebsiteData() async {
        await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                      modifiedSince: .distantPast)
        goHome()
    }

    @ObservationIgnored var onNavigationStart: (() -> Void)?

    nonisolated static func safariUserAgent() -> String {
        let info = Bundle(path: "/Applications/Safari.app")?.infoDictionary
        let ver = (info?["CFBundleShortVersionString"] as? String) ?? "27.2"
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(ver) Safari/605.1.15"
    }

    func reload() { webView.reload() }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func goHome() {
        load(URL(string: settings.startURL) ?? URL(string: AppSettings.defaultStartURL)!)
    }
    func load(_ url: URL) { webView.load(URLRequest(url: url)) }

    fileprivate var popups: [PopupWindowController] = []
    fileprivate var userAgent: String? { webView.customUserAgent }
}

@MainActor
private final class WebDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var controller: WebController?

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.allow) }
        let mainFrame = action.targetFrame?.isMainFrame ?? true
        if !mainFrame || WebNavigationPolicy.shouldLoadInApp(url) { return decisionHandler(.allow) }
        if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let controller else { return nil }
        let popup = PopupWindowController(configuration: configuration, userAgent: controller.userAgent,
                                          navigationDelegate: self, uiDelegate: self)
        popup.onClose = { [weak controller] p in controller?.popups.removeAll { $0 === p } }
        controller.popups.append(popup)
        return popup.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        controller?.popups.first { $0.webView === webView }?.close()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        controller?.applyHideSections() // page loads/SPA reloads reset in-page state
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        controller?.onNavigationStart?()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }
}

/// Hosts the app's single WKWebView. Never creates a new one.
struct MusicWebView: NSViewRepresentable {
    let controller: WebController
    func makeNSView(context: Context) -> WKWebView { controller.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
