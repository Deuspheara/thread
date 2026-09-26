import Foundation

/// Describes the system's registration state for launching Thread at login.
public enum LoginLaunchStatus: Sendable, Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}
