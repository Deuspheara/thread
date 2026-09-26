import Foundation

public struct ActivityEventID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public struct ActivitySourceID: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Encodes each event with its required typed context, avoiding mismatched kind/payload pairs.
public enum ActivityEventKind: Equatable, Codable, Sendable {
    case observationCleared
    case applicationActivated(ApplicationContext)
    case applicationLaunched(ApplicationContext)
    case applicationTerminated(ApplicationContext)
    case windowFocused(WindowContext)
    case windowUpdated(WindowContext)
    case windowOpened(WindowContext)
    case windowClosed(WindowIdentity, ApplicationContext)
    case windowUnavailable(ApplicationContext, WindowAvailability)
    case browserTabOpened(BrowserTabContext)
    case browserTabActivated(BrowserTabContext)
    case browserTabUpdated(BrowserTabContext)
    case browserTabClosed(BrowserTabIdentity)
    case browserDisconnected(BrowserConnectionIdentity)
    case browserFocusCleared(BrowserConnectionIdentity)
    case branchChanged(RepositoryObservation)
    case repositoryChanged(RepositoryObservation)
    case terminalDirectoryChanged(TerminalContext)
    case terminalCommandCompleted(TerminalContext, Int32)
    case terminalSessionEnded(TerminalSessionIdentity)
    case accessibilityPermissionChanged(AccessibilityPermission)
}

/// Normalizes external observations into platform-independent, timestamped values.
public struct ActivityEvent: Equatable, Codable, Sendable {
    public let id: ActivityEventID
    public let timestamp: Date
    public let source: ActivitySourceID
    public let kind: ActivityEventKind

    public init(id: ActivityEventID, timestamp: Date, source: ActivitySourceID, kind: ActivityEventKind) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.kind = kind
    }
}
