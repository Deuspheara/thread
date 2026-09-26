import ThreadDomain

/// Removes excluded metadata and tracks shell sessions so delayed Git results stay excluded.
struct ObservationPrivacyFilter {
    var exclusions: ObservationExclusions?
    private var blockedSessions: [TerminalSessionIdentity] = []

    mutating func screen(_ event: ActivityEvent) -> ActivityEvent? {
        guard let exclusions else {
            if case .accessibilityPermissionChanged = event.kind { return event }
            return nil
        }
        switch event.kind {
        case .applicationActivated(let app), .applicationLaunched(let app), .applicationTerminated(let app):
            guard exclusions.excludes(application: app.identity.bundleIdentifier) else { return event }
            if case .applicationActivated = event.kind { return cleared(event) }
            return nil
        case .windowFocused(let window), .windowUpdated(let window), .windowOpened(let window):
            return exclusions.excludes(application: window.application.identity.bundleIdentifier) ? cleared(event) : event
        case .windowClosed(_, let app), .windowUnavailable(let app, _):
            return exclusions.excludes(application: app.identity.bundleIdentifier) ? nil : event
        case .browserTabOpened(let tab), .browserTabActivated(let tab), .browserTabUpdated(let tab):
            let excluded = exclusions.excludes(url: tab.url) || exclusions.excludes(application: tab.application?.bundleIdentifier ?? bundle(for: tab.browser))
            guard excluded else { return event }
            return tab.isActive ? cleared(event) : nil
        case .terminalDirectoryChanged(let terminal), .terminalCommandCompleted(let terminal, _):
            let excluded = terminal.terminalApplication.map(exclusions.excludes(application:)) ?? !exclusions.applications.isEmpty
            blockedSessions.removeAll { $0 == terminal.session }
            if excluded {
                blockedSessions.append(terminal.session)
                if blockedSessions.count > 128 { blockedSessions.removeFirst() }
                return cleared(event)
            }
            return event
        case .repositoryChanged(let observation), .branchChanged(let observation):
            return blockedSessions.contains(observation.terminal) ? nil : event
        case .terminalSessionEnded(let session):
            blockedSessions.removeAll { $0 == session }
            return event
        default: return event
        }
    }

    private func cleared(_ event: ActivityEvent) -> ActivityEvent {
        ActivityEvent(id: event.id, timestamp: event.timestamp, source: event.source, kind: .observationCleared)
    }

    private func bundle(for browser: BrowserKind) -> String {
        switch browser {
        case .chrome: "com.google.chrome"
        case .chromium: "org.chromium.chromium"
        case .brave: "com.brave.browser"
        case .edge: "com.microsoft.edgemac"
        case .safari: "com.apple.safari"
        }
    }
}
