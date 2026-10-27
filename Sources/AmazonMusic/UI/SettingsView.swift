import AppKit
import SwiftUI
import UserNotifications

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            NotificationSettings().tabItem { Label("Notifications", systemImage: "bell") }
            AdvancedSettings().tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 480, height: 340)
    }
}

private struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings
    @State private var draft = ""
    @State private var error: String?
    private static let custom = "custom"

    var body: some View {
        @Bindable var settings = settings
        Form {
            Toggle("Show menu bar icon", isOn: $settings.showMenuBar)
            Toggle("Hide podcasts", isOn: $settings.hidePodcasts)
            Toggle("Hide Audible", isOn: $settings.hideAudible)
            Toggle("Hide 'Get App' button", isOn: $settings.hideGetApp)
            Toggle("Hide Home page banner", isOn: $settings.hideHomeBanner)
            Text("Hides podcast and Audible (audiobook) tabs, sections and links in the Amazon Music web UI. Depends on Amazon's page layout and may need updating if it changes.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Region", selection: Binding(
                get: { SettingsValidation.presetHost(for: settings.startURL) ?? Self.custom },
                set: { if $0 != Self.custom { commit($0) } })) {
                ForEach(SettingsValidation.presetHosts, id: \.self) { Text($0).tag($0) }
                Text("Custom").tag(Self.custom)
            }
            TextField("Start URL", text: $draft)
                .onSubmit { commit(draft) }
                .autocorrectionDisabled()
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Button("Apply") { commit(draft) }
                Button("Reset to default") { commit(AppSettings.defaultStartURL) }
            }
            Text("Changing the start URL loads it immediately.").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear { draft = settings.startURL }
        .onChange(of: settings.startURL) { _, new in if error == nil { draft = new } }
    }

    private func commit(_ input: String) {
        switch SettingsValidation.validateStartURL(input) {
        case .success(let url):
            error = nil
            settings.startURL = url.absoluteString
            draft = url.absoluteString
        case .failure(let e):
            error = e.localizedDescription // invalid values are never saved
        }
    }
}

private struct NotificationSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(NotificationController.self) private var notifications

    var body: some View {
        @Bindable var settings = settings
        Form {
            Toggle("Show a notification when the track changes", isOn: $settings.notificationsEnabled)
            Toggle("Notify even when the app is frontmost", isOn: $settings.notifyWhenFrontmost)
                .disabled(!settings.notificationsEnabled)
            LabeledContent("Permission", value: Self.describe(notifications.authorizationStatus))
            if notifications.authorizationStatus == .denied {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Text("Ad-hoc signed builds may have notifications suppressed by macOS.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .task { await notifications.refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await notifications.refreshStatus() }
        }
    }

    static func describe(_ s: UNAuthorizationStatus) -> String {
        switch s {
        case .notDetermined: "Not requested yet"
        case .denied: "Denied"
        case .authorized: "Allowed"
        case .provisional: "Provisional"
        case .ephemeral: "Ephemeral"
        @unknown default: "Unknown"
        }
    }
}

private struct AdvancedSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(WebController.self) private var web
    @Environment(PlayerState.self) private var player
    @State private var uaDraft = ""
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("User agent") {
                TextField("Override (empty = Safari)", text: $uaDraft, axis: .vertical)
                    .lineLimit(1...3)
                    .onSubmit(applyUA)
                HStack {
                    Button("Apply & Reload", action: applyUA)
                    Button("Use Safari UA") { uaDraft = ""; applyUA() }
                }
                Text("Effective: \(web.effectiveUserAgent)").font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Section("Website data") {
                Button("Reset website data…", role: .destructive) { confirmReset = true }
            }
            Section("Bridge") {
                LabeledContent("Version", value: player.bridgeVersion ?? "—")
                LabeledContent("Health", value: player.bridgeHealthy ? "Healthy" : "Unhealthy")
                if let e = player.lastError { LabeledContent("Last error", value: e) }
            }
        }
        .formStyle(.grouped)
        .onAppear { uaDraft = settings.customUserAgent ?? "" }
        .confirmationDialog("Reset website data?", isPresented: $confirmReset) {
            Button("Reset and Sign Out", role: .destructive) { Task { await web.resetWebsiteData() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all cookies and site data and signs you out of Amazon Music.")
        }
    }

    private func applyUA() {
        let t = uaDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.customUserAgent = t.isEmpty ? nil : t // WebController observes and applies + reloads
    }
}
