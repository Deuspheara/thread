import Foundation

public enum AccessibilityPermission: String, Codable, Sendable {
    case unknown
    case notGranted
    case granted
}

public enum WindowAvailability: String, Codable, Sendable {
    case waiting
    case available
    case permissionRequired
    case noFocusedWindow
    case unsupported
    case temporarilyUnavailable
}

/// Presents the latest foreground observation, independently of inferred work Threads.
public struct CurrentContext: Equatable, Codable, Sendable {
    public var browserTab: BrowserTabContext?
    public var repository: RepositoryResolution?
    public var terminal: TerminalContext?
    public var terminalExitStatus: Int32?
    public var application: ApplicationContext?
    public var window: WindowContext?
    public var permission: AccessibilityPermission
    public var windowAvailability: WindowAvailability
    public var updatedAt: Date?

    public init(
        browserTab: BrowserTabContext? = nil,
        repository: RepositoryResolution? = nil,
        terminal: TerminalContext? = nil,
        terminalExitStatus: Int32? = nil,
        application: ApplicationContext? = nil,
        window: WindowContext? = nil,
        permission: AccessibilityPermission = .unknown,
        windowAvailability: WindowAvailability = .waiting,
        updatedAt: Date? = nil
    ) {
        self.browserTab = browserTab
        self.repository = repository
        self.terminal = terminal
        self.terminalExitStatus = terminalExitStatus
        self.application = application
        self.window = window
        self.permission = permission
        self.windowAvailability = windowAvailability
        self.updatedAt = updatedAt
    }
}
