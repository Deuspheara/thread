import Observation
import ThreadDomain

/// Presents actual login registration state and forwards explicit preference changes.
@MainActor
@Observable
public final class LoginLaunchModel {
    public private(set) var status: LoginLaunchStatus = .unavailable
    public private(set) var changeFailed = false
    private let readStatus: @MainActor () -> LoginLaunchStatus
    private let change: @MainActor (Bool) throws -> Void
    private let showSettings: @MainActor () -> Void

    public init(readStatus: @escaping @MainActor () -> LoginLaunchStatus,
                change: @escaping @MainActor (Bool) throws -> Void,
                showSettings: @escaping @MainActor () -> Void) {
        self.readStatus = readStatus
        self.change = change
        self.showSettings = showSettings
    }

    public var isRequested: Bool { status == .enabled || status == .requiresApproval }

    public func refresh() { status = readStatus() }

    public func setEnabled(_ enabled: Bool) {
        changeFailed = false
        do { try change(enabled) }
        catch { changeFailed = true }
        refresh()
    }

    public func openSystemSettings() { showSettings() }
}
