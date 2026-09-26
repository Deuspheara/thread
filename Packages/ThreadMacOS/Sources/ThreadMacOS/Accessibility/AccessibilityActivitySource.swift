import AppKit
import ApplicationServices
import OSLog
import ThreadDomain

/// Observes the foreground app's window metadata and reports authorization changes without polling.
@MainActor
public final class AccessibilityActivitySource: ActivitySource {
    private nonisolated let stream: AsyncStream<ActivityEvent>
    private let continuation: AsyncStream<ActivityEvent>.Continuation
    private let source = ActivitySourceID(rawValue: "macos.accessibility")
    private let excludedBundleID: String
    private let workspace: NSWorkspace
    private let authorization = AccessibilityAuthorization()
    private let identities = WindowIdentityRegistry()
    private let titlePolicy = WindowTitlePolicy()
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: "app.thread.desktop", category: "permissions")
    private var tokens: [NSObjectProtocol] = []
    private var application: ApplicationContext?
    private var lastWindow: WindowContext?
    private var permission: AccessibilityPermission = .unknown
    private var started = false
    private var stopped = false
    private var subscribed = false
    private lazy var subscription = AXWindowSubscription { [weak self] name, element in
        self?.windowNotification(name, element: element)
    }

    public init(excluding bundleID: String, workspace: NSWorkspace = .shared, now: @escaping @Sendable () -> Date = Date.init) {
        let channel = AsyncStream<ActivityEvent>.makeStream(bufferingPolicy: .bufferingNewest(128))
        stream = channel.stream
        continuation = channel.continuation
        excludedBundleID = bundleID
        self.workspace = workspace
        self.now = now
        continuation.onTermination = { [weak self] _ in Task { @MainActor in self?.stop() } }
    }

    public nonisolated func events() -> AsyncStream<ActivityEvent> { stream }

    public func start() {
        guard !started, !stopped else { return }
        started = true
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didTerminateApplicationNotification] {
            tokens.append(workspace.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let terminatedPID = name == NSWorkspace.didTerminateApplicationNotification
                    ? (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier : nil
                MainActor.assumeIsolated {
                    if let terminatedPID { self?.applicationTerminated(terminatedPID) }
                    self?.refresh()
                }
            })
        }
        refresh()
    }

    public func requestPermission() {
        authorization.request()
        refresh()
    }

    public func openPermissionSettings() -> Bool { authorization.openSettings() }

    public func refresh() {
        guard started, !stopped else { return }
        updatePermission()
        guard let running = workspace.frontmostApplication,
              let current = RunningApplicationSnapshot.capture(running, excluding: excludedBundleID) else { return }
        if application?.isSameInstance(as: current) != true {
            subscription.stop()
            subscribed = false
            application = current
            lastWindow = nil
        }
        guard permission == .granted else {
            emit(.windowUnavailable(current, .permissionRequired))
            return
        }
        if !subscribed { subscribed = subscription.start(processIdentifier: current.processIdentifier) }
        captureWindow(current)
    }

    isolated deinit { stop() }

    public func stop() {
        guard !stopped else { return }
        stopped = true
        subscription.stop()
        for token in tokens { workspace.notificationCenter.removeObserver(token) }
        tokens.removeAll()
        continuation.finish()
    }

    private func applicationTerminated(_ processIdentifier: Int32) {
        identities.remove(processIdentifier: processIdentifier)
        guard application?.processIdentifier == processIdentifier else { return }
        subscription.stop()
        subscribed = false
        application = nil
        lastWindow = nil
    }

    private func updatePermission() {
        let updated = authorization.status
        guard updated != permission else { return }
        permission = updated
        if updated == .granted { logger.info("Accessibility access granted") }
        else { logger.info("Accessibility access not granted") }
        emit(.accessibilityPermissionChanged(updated))
        if updated != .granted {
            subscription.stop()
            subscribed = false
            lastWindow = nil
        }
    }

    private func captureWindow(_ current: ApplicationContext) {
        switch FocusedWindowReader(identities: identities, titlePolicy: titlePolicy).read(application: current) {
        case .window(let element, let window):
            subscription.observeWindow(element)
            let previous = lastWindow
            lastWindow = window
            if window.identity != previous?.identity {
                emit(.windowFocused(window))
            } else if window != previous {
                emit(.windowUpdated(window))
            }
        case .unavailable(let reason):
            subscription.observeWindow(nil)
            lastWindow = nil
            emit(.windowUnavailable(current, reason))
        }
    }

    private func windowNotification(_ name: String, element: AXUIElement) {
        if name == kAXUIElementDestroyedNotification {
            if let lastWindow, identities.identity(for: element, application: lastWindow.application) == lastWindow.identity {
                emit(.windowClosed(lastWindow.identity, lastWindow.application))
                self.lastWindow = nil
            }
            identities.remove(element)
        }
        refresh()
    }

    private func recoverLatestState() {
        // Recovery writes directly to avoid recursively reporting drops in a full queue.
        continuation.yield(makeEvent(.accessibilityPermissionChanged(permission)))
        if permission == .granted, let lastWindow {
            continuation.yield(makeEvent(.windowFocused(lastWindow)))
        } else if let application {
            let reason: WindowAvailability = permission == .granted ? .temporarilyUnavailable : .permissionRequired
            continuation.yield(makeEvent(.windowUnavailable(application, reason)))
        }
    }

    private func makeEvent(_ kind: ActivityEventKind) -> ActivityEvent {
        ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: now(), source: source, kind: kind)
    }

    private func emit(_ kind: ActivityEventKind) {
        let event = makeEvent(kind)
        if case .dropped = continuation.yield(event) {
            logger.error("Accessibility event buffer overflow")
            recoverLatestState()
        }
    }
}
