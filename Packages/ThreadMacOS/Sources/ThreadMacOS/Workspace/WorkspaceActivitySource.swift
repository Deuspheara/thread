import AppKit
import OSLog
import ThreadDomain

/// Translates workspace lifecycle notifications into normalized application events.
@MainActor
public final class WorkspaceActivitySource: ActivitySource {
    private nonisolated let stream: AsyncStream<ActivityEvent>
    private let continuation: AsyncStream<ActivityEvent>.Continuation
    private let workspace: NSWorkspace
    private let excludedBundleID: String
    private let now: @Sendable () -> Date
    private let source = ActivitySourceID(rawValue: "macos.workspace")
    private let logger = Logger(subsystem: "app.thread.desktop", category: "activity")
    private var tokens: [NSObjectProtocol] = []
    private var started = false
    private var stopped = false

    public init(excluding bundleID: String, workspace: NSWorkspace = .shared, now: @escaping @Sendable () -> Date = Date.init) {
        let channel = AsyncStream<ActivityEvent>.makeStream(bufferingPolicy: .bufferingNewest(128))
        stream = channel.stream
        continuation = channel.continuation
        excludedBundleID = bundleID
        self.workspace = workspace
        self.now = now
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    public nonisolated func events() -> AsyncStream<ActivityEvent> { stream }

    public func start() {
        guard !started, !stopped else { return }
        started = true
        observe(NSWorkspace.didActivateApplicationNotification, kind: ActivityEventKind.applicationActivated)
        observe(NSWorkspace.didLaunchApplicationNotification, kind: ActivityEventKind.applicationLaunched)
        observe(NSWorkspace.didTerminateApplicationNotification, kind: ActivityEventKind.applicationTerminated)
        logger.info("Workspace observation started")
        refresh()
    }

    public func refresh() {
        guard started, !stopped, let application = workspace.frontmostApplication,
              let value = RunningApplicationSnapshot.capture(application, excluding: excludedBundleID) else { return }
        emit(.applicationActivated(value))
    }

    isolated deinit { stop() }

    public func stop() {
        guard !stopped else { return }
        stopped = true
        for token in tokens { workspace.notificationCenter.removeObserver(token) }
        tokens.removeAll()
        continuation.finish()
    }

    private func observe(_ name: Notification.Name, kind: @escaping @Sendable (ApplicationContext) -> ActivityEventKind) {
        let token = workspace.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self, excludedBundleID] note in
            guard let application = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let value = RunningApplicationSnapshot.capture(application, excluding: excludedBundleID) else { return }
            // The NotificationCenter contract delivers this callback on the main queue.
            MainActor.assumeIsolated {
                self?.emit(kind(value))
            }
        }
        tokens.append(token)
    }

    private func emit(_ kind: ActivityEventKind) {
        let event = ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: now(), source: source, kind: kind)
        if case .dropped = continuation.yield(event) {
            logger.error("Workspace event buffer overflow")
            // Restore the latest foreground fact after pressure may have discarded an activation.
            if let app = workspace.frontmostApplication,
               let current = RunningApplicationSnapshot.capture(app, excluding: excludedBundleID) {
                continuation.yield(ActivityEvent(
                    id: ActivityEventID(rawValue: UUID()), timestamp: now(), source: source,
                    kind: .applicationActivated(current)
                ))
            }
        }
    }
}
