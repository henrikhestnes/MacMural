import Foundation

public enum LoginItemStatus {
    case notRegistered, enabled, requiresApproval, notFound
    public var isRequested: Bool { self == .enabled || self == .requiresApproval }
}

public protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

/// Preference policy is separate from the native service so tests never change login items.
public final class LaunchAtLoginController {
    private let service: LoginItemService
    private let defaults: UserDefaults
    private static let configuredKey = "launchAtLogin.defaultConfigured"
    private static let welcomeKey = "startup.hasShownWelcome"
    public private(set) var errorMessage: String?
    public var status: LoginItemStatus { service.status }

    public init(service: LoginItemService, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
    }

    public func configureDefaultIfNeeded(isInstalled: Bool) {
        guard isInstalled, !defaults.bool(forKey: Self.configuredKey) else { return }
        // Record the attempt even if denied, so later launches never override a user's choice.
        defaults.set(true, forKey: Self.configuredKey)
        if !status.isRequested { setEnabled(true) }
    }

    public func setEnabled(_ enabled: Bool) {
        defaults.set(true, forKey: Self.configuredKey)
        errorMessage = nil
        do {
            if enabled {
                if !status.isRequested { try service.register() }
            } else if status.isRequested {
                try service.unregister()
            }
        } catch {
            // The system's actual state wins over errors such as "already registered".
            if enabled && status.isRequested { return }
            if !enabled && !status.isRequested { return }
            errorMessage = error.localizedDescription
        }
    }

    public func shouldShowWelcome(isLoginLaunch: Bool) -> Bool {
        !isLoginLaunch && !defaults.bool(forKey: Self.welcomeKey)
    }
    public func markWelcomeShown() { defaults.set(true, forKey: Self.welcomeKey) }
}
