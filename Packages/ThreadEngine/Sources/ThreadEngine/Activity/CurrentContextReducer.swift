import Foundation
import ThreadDomain

/// Maintains foreground state while rejecting stale or unrelated window notifications.
public struct CurrentContextReducer: Sendable {
    public private(set) var context = CurrentContext()
    private var terminalTime = Date.distantPast
    private var activationTime = Date.distantPast
    private var windowTime = Date.distantPast
    private var permissionTime = Date.distantPast

    public init() {}

    public mutating func apply(_ event: ActivityEvent) {
        let previous = context
        defer {
            if context != previous { context.updatedAt = max(previous.updatedAt ?? .distantPast, event.timestamp) }
        }
        switch event.kind {
        case .observationCleared:
            context = CurrentContext(permission: context.permission, updatedAt: event.timestamp)
            terminalTime = event.timestamp
            activationTime = event.timestamp
            windowTime = event.timestamp
        case .applicationActivated(let application):
            activate(application, at: event.timestamp)
        case .applicationTerminated(let application):
            guard isCurrent(application), event.timestamp >= activationTime else { return }
            context.application = nil
            context.window = nil
            context.windowAvailability = .waiting
            context.updatedAt = event.timestamp
            activationTime = event.timestamp
        case .windowFocused(let window):
            accept(window, at: event.timestamp, establishesFocus: true)
        case .windowUpdated(let window):
            accept(window, at: event.timestamp, establishesFocus: false)
        case .windowClosed(let identity, let application):
            guard context.window?.identity == identity else { return }
            clearWindow(application, reason: .noFocusedWindow, at: event.timestamp)
        case .windowUnavailable(let application, let reason):
            guard event.timestamp >= activationTime else { return }
            if !isCurrent(application) { activate(application, at: event.timestamp) }
            clearWindow(application, reason: reason, at: event.timestamp)
        case .accessibilityPermissionChanged(let permission):
            setPermission(permission, at: event.timestamp)
        case .browserTabActivated(let tab):
            context.browserTab = tab
        case .browserTabUpdated(let tab):
            if context.browserTab?.identity == tab.identity { context.browserTab = tab }
        case .browserTabClosed(let identity):
            if context.browserTab?.identity == identity { context.browserTab = nil }
        case .browserDisconnected(let connection), .browserFocusCleared(let connection):
            if context.browserTab?.identity.connection == connection { context.browserTab = nil }
        case .browserTabOpened: break
        case .repositoryChanged(let observation), .branchChanged(let observation):
            guard let terminal = context.terminal, terminal.session == observation.terminal,
                  terminal.sequence == observation.sequence else { return }
            context.repository = observation.resolution
        case .terminalDirectoryChanged(let terminal):
            updateTerminal(terminal, status: nil, at: event.timestamp)
        case .terminalCommandCompleted(let terminal, let status):
            updateTerminal(terminal, status: status, at: event.timestamp)
        case .terminalSessionEnded(let session):
            guard context.terminal?.session == session, event.timestamp >= terminalTime else { return }
            context.repository = nil
            context.terminal = nil
            context.terminalExitStatus = nil
            terminalTime = event.timestamp
        case .applicationLaunched, .windowOpened:
            break // Opening a resource does not establish foreground focus.
        }
    }

    private mutating func updateTerminal(_ terminal: TerminalContext, status: Int32?, at timestamp: Date) {
        guard timestamp >= terminalTime else { return }
        if let previous = context.terminal, previous.session == terminal.session,
           terminal.sequence <= previous.sequence { return }
        context.repository = nil
        context.terminal = terminal
        context.terminalExitStatus = status
        terminalTime = timestamp
    }

    private mutating func activate(_ application: ApplicationContext, at timestamp: Date) {
        guard timestamp >= activationTime else { return }
        if !isCurrent(application) {
            context.window = nil
            context.windowAvailability = context.permission == .granted ? .waiting : .permissionRequired
            windowTime = timestamp
        }
        context.application = application
        context.updatedAt = timestamp
        activationTime = timestamp
    }

    private mutating func accept(_ window: WindowContext, at timestamp: Date, establishesFocus: Bool) {
        guard context.permission == .granted, timestamp >= activationTime else { return }
        if establishesFocus, !isCurrent(window.application) { activate(window.application, at: timestamp) }
        guard isCurrent(window.application),
              timestamp >= activationTime, timestamp >= windowTime, timestamp >= permissionTime else { return }
        context.window = window
        context.windowAvailability = .available
        context.updatedAt = timestamp
        windowTime = timestamp
    }

    private mutating func clearWindow(_ application: ApplicationContext, reason: WindowAvailability, at timestamp: Date) {
        guard isCurrent(application), timestamp >= activationTime, timestamp >= windowTime,
              timestamp >= permissionTime else { return }
        context.window = nil
        context.windowAvailability = context.permission == .granted ? reason : .permissionRequired
        context.updatedAt = timestamp
        windowTime = timestamp
    }

    private mutating func setPermission(_ permission: AccessibilityPermission, at timestamp: Date) {
        guard timestamp >= permissionTime else { return }
        permissionTime = timestamp
        context.permission = permission
        if permission != .granted {
            context.window = nil
            context.windowAvailability = .permissionRequired
        } else if context.window == nil {
            context.windowAvailability = .waiting
        }
    }

    private func isCurrent(_ application: ApplicationContext) -> Bool {
        context.application?.isSameInstance(as: application) == true
    }
}
