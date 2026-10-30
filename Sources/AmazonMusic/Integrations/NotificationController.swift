import AppKit
import Observation
import OSLog
import UserNotifications

/// Pure decision: should a track-change banner be posted?
enum NotificationPolicy {
    static func shouldNotify(enabled: Bool, appIsFrontmostAndMainWindowKey: Bool,
                             notifyWhenFrontmost: Bool, isSameTrackAsLast: Bool) -> Bool {
        guard enabled else { return false }                                  // skip: toggle off
        if appIsFrontmostAndMainWindowKey && !notifyWhenFrontmost { return false } // skip: user is looking at app
        if isSameTrackAsLast { return false }                                // skip: duplicate
        return true
    }
}

@MainActor @Observable
final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
    static let debounce: Duration = .seconds(1)
    static let threadID = "com.khalidabuhakmeh.amazonmusic.track"
    private static let log = Logger(subsystem: "com.khalidabuhakmeh.amazonmusic", category: "notifications")

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    /// Set by the App; opens/focuses the main window on notification click.
    @ObservationIgnored var onOpenMainWindow: (() -> Void)?

    @ObservationIgnored private let state: PlayerState
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var lastIdentity: String?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var consumer: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var center: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil
    }

    init(state: PlayerState, settings: AppSettings) {
        self.state = state
        self.settings = settings
        super.init()
    }

    func start() {
        guard !started else { return }
        started = true
        center?.delegate = self
        Task { await refreshStatus() }
        observeSettings()
        let stream = state.trackChanged
        consumer = Task { [weak self] in
            for await track in stream { self?.trackChanged(track) }
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.notificationsEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.settings.notificationsEnabled { await self.requestAuthorizationIfNeeded() }
                self.observeSettings()
            }
        }
    }

    func refreshStatus() async {
        guard let center else { return }
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    /// Prompts only when status is .notDetermined; call when the user turns the toggle on.
    func requestAuthorizationIfNeeded() async {
        guard let center else { Self.log.notice("not running from an app bundle; notifications unavailable"); return }
        await refreshStatus()
        guard authorizationStatus == .notDetermined else { return }
        do { _ = try await center.requestAuthorization(options: [.alert]) }
        catch { Self.log.error("authorization failed: \(error.localizedDescription, privacy: .public)") }
        await refreshStatus()
    }

    // MARK: Track changes

    private func trackChanged(_ track: TrackInfo) {
        pending?.cancel()
        // Debounce: only the last track of a quick burst survives the 1s wait.
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            await self.deliver(track)
        }
    }

    private func deliver(_ track: TrackInfo) async {
        let frontKey = NSApp.isActive && (NSApp.keyWindow?.identifier?.rawValue.contains("main") ?? false)
        let same = track.identity == lastIdentity
        guard NotificationPolicy.shouldNotify(enabled: settings.notificationsEnabled,
                                              appIsFrontmostAndMainWindowKey: frontKey,
                                              notifyWhenFrontmost: settings.notifyWhenFrontmost,
                                              isSameTrackAsLast: same) else { return }
        guard let center, authorizationStatus == .authorized || authorizationStatus == .provisional else {
            Self.log.notice("skipping notification; authorization status \(self.authorizationStatus.rawValue)")
            return
        }
        lastIdentity = track.identity

        let content = UNMutableNotificationContent()
        content.title = track.title ?? "Now Playing"
        content.body = [track.artist, track.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
        content.threadIdentifier = Self.threadID
        var attachmentFile: URL?
        if let url = track.artworkURL, let cached = await ArtworkCache.shared.fileURL(for: url),
           let (attachment, tmp) = Self.attachment(copying: cached) {
            content.attachments = [attachment]
            attachmentFile = tmp
        }
        guard !Task.isCancelled else {
            if let attachmentFile { try? FileManager.default.removeItem(at: attachmentFile) }
            return
        }
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.content.threadIdentifier == Self.threadID }
            .map(\.request.identifier))
        do {
            try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        } catch {
            Self.log.error("post failed: \(error.localizedDescription, privacy: .public)")
            if let attachmentFile { try? FileManager.default.removeItem(at: attachmentFile) }
        }
    }

    /// UNNotificationAttachment moves the file, so give it a unique temp copy with an image extension.
    private static func attachment(copying file: URL) -> (UNNotificationAttachment, URL)? {
        let ext = file.pathExtension.isEmpty ? "jpg" : file.pathExtension
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        do {
            try FileManager.default.copyItem(at: file, to: tmp)
            return (try UNNotificationAttachment(identifier: "artwork", url: tmp), tmp)
        } catch {
            log.debug("attachment failed: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: tmp)
            return nil
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            NSApp.activate()
            if let onOpenMainWindow { onOpenMainWindow() }
            else { NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil) } // fallback until App wires openWindow
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let allow = await MainActor.run { settings.notifyWhenFrontmost }
        return allow ? [.banner] : []
    }
}
