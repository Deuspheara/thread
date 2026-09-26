import Foundation
import ServiceManagement
import ThreadDomain
import OSLog

/// Translates macOS login-item registration into application-facing status and intent.
@MainActor
public struct LoginLaunchRegistration {
    public init() {}

    public var status: LoginLaunchStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        guard status != .unavailable else { throw LoginLaunchError.unavailable }
        if enabled, status == .enabled || status == .requiresApproval { return }
        if !enabled, status == .disabled { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            Logger(subsystem: "app.thread.desktop", category: "settings").error("Login registration change unavailable")
            throw LoginLaunchError.changeFailed
        }
    }

    public func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

public enum LoginLaunchError: Error, Sendable {
    case unavailable
    case changeFailed
}
