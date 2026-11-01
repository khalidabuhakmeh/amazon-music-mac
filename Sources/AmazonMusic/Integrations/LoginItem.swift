import ServiceManagement

enum LoginItemStatus: Equatable, Sendable {
    case enabled, disabled, requiresApproval, notFound
}

@MainActor
protocol LoginItemService {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

/// Thin wrapper over `SMAppService.mainApp`. State is always read from the system, never stored.
struct SystemLoginItem: LoginItemService {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        case .notRegistered: .disabled
        @unknown default: .disabled
        }
    }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// Deterministic stand-in for snapshots/tests; never touches the real service.
@MainActor
final class FakeLoginItem: LoginItemService {
    var status: LoginItemStatus
    var failure: Error?
    init(status: LoginItemStatus = .disabled, failure: Error? = nil) { self.status = status; self.failure = failure }
    func register() throws { if let failure { throw failure }; status = .enabled }
    func unregister() throws { if let failure { throw failure }; status = .disabled }
}

/// Pure status → UI mapping.
struct LoginItemPresentation: Equatable {
    var isOn: Bool
    var canToggle: Bool
    var needsApproval: Bool
    var caption: String?

    init(_ s: LoginItemStatus) {
        isOn = s == .enabled || s == .requiresApproval
        canToggle = s != .notFound
        needsApproval = s == .requiresApproval
        caption = switch s {
        case .requiresApproval: "Approve Amazon Music in System Settings › General › Login Items."
        case .notFound: "Launch at login isn't available for this build."
        default: nil
        }
    }
}
