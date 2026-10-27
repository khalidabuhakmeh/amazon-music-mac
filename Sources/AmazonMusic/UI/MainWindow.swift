import SwiftUI

struct MainWindow: View {
    @Environment(WebController.self) private var web
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MusicWebView(controller: web)
            .frame(minWidth: 900, minHeight: 600)
            .background(WindowAccessor(webView: web.webView))
            .onAppear { MainWindowCoordinator.shared.openWindowAction = { [openWindow] in openWindow(id: "main") } }
            .navigationTitle("Amazon Music")
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button { web.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                        .disabled(!web.canGoBack)
                    Button { web.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                        .disabled(!web.canGoForward)
                }
                ToolbarItemGroup {
                    Button { web.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                    Button { web.goHome() } label: { Label("Home", systemImage: "house") }
                }
            }
    }
}
