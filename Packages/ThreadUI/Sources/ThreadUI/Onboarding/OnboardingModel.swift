import Observation
import ThreadDomain

/// Presents optional setup and starts observation only after explicit first-run intent.
@MainActor
@Observable
public final class OnboardingModel {
    public private(set) var hasStarted: Bool
    public var permission: AccessibilityPermission { readPermission() }
    public private(set) var rememberFailed = false
    public private(set) var settingsUnavailable = false
    public private(set) var guideUnavailable = false
    public let shellSetup: String
    private let remember: @MainActor () throws -> Void
    private let start: @MainActor () -> Void
    private let readPermission: @MainActor () -> AccessibilityPermission
    private let refreshAccess: @MainActor () -> Void
    private let requestAccess: @MainActor () -> Void
    private let openSettings: @MainActor () -> Bool
    private let openGuide: @MainActor () -> Bool

    public init(complete: Bool, shellSetup: String, remember: @escaping @MainActor () throws -> Void,
                start: @escaping @MainActor () -> Void, readPermission: @escaping @MainActor () -> AccessibilityPermission,
                refreshAccess: @escaping @MainActor () -> Void,
                requestAccess: @escaping @MainActor () -> Void, openSettings: @escaping @MainActor () -> Bool,
                openGuide: @escaping @MainActor () -> Bool) {
        hasStarted = complete
        self.shellSetup = shellSetup
        self.remember = remember
        self.start = start
        self.readPermission = readPermission
        self.refreshAccess = refreshAccess
        self.requestAccess = requestAccess
        self.openSettings = openSettings
        self.openGuide = openGuide
    }

    public func begin() {
        guard !hasStarted else { return }
        do { try remember(); beginSession() }
        catch { rememberFailed = true }
    }

    public func beginSession() {
        guard !hasStarted else { return }
        hasStarted = true
        start()
    }

    public func refreshPermission() {
        guard hasStarted else { return }
        refreshAccess()
    }
    public func requestPermission() { requestAccess(); refreshPermission() }
    public func openPermissionSettings() { settingsUnavailable = !openSettings() }
    public func openSetupGuide() { guideUnavailable = !openGuide() }
}
