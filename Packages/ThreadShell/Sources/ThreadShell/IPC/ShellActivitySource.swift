import Foundation
import OSLog
import ThreadDomain

/// Normalizes local shell datagrams into a bounded single-consumer activity stream.
@MainActor
public final class ShellActivitySource: ActivitySource {
    private nonisolated let stream: AsyncStream<ActivityEvent>
    private let continuation: AsyncStream<ActivityEvent>.Continuation
    private let url: URL
    private let now: @Sendable () -> Date
    private var registry = ShellSessionRegistry()
    private var stopped = false
    private let logger = Logger(subsystem: "app.thread.desktop", category: "shell")
    private lazy var exits = ShellProcessExitObserver { [weak self] session in self?.processEnded(session) }
    private lazy var listener = UnixDatagramListener { [weak self] data in self?.receive(data) }

    public init(url: URL = ShellSocketLocation.defaultURL, now: @escaping @Sendable () -> Date = Date.init) {
        let channel = AsyncStream<ActivityEvent>.makeStream(bufferingPolicy: .bufferingNewest(128))
        stream = channel.stream
        continuation = channel.continuation
        self.url = url
        self.now = now
        continuation.onTermination = { [weak self] _ in Task { @MainActor in self?.stop() } }
    }

    public nonisolated func events() -> AsyncStream<ActivityEvent> { stream }
    public func start() throws {
        guard !stopped else { throw ShellTransportError.unavailable }
        try listener.start(at: url)
        logger.info("Shell observation started")
    }
    isolated deinit { stop() }
    public func stop() {
        stopped = true
        listener.stop()
        exits.stop()
        continuation.finish()
    }

    private func processEnded(_ session: TerminalSessionIdentity) {
        guard !stopped else { return }
        let timestamp = now()
        guard let kind = registry.end(session, at: timestamp) else { return }
        let event = ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: timestamp,
                                  source: ActivitySourceID(rawValue: "shell.zsh"), kind: kind)
        if case .dropped = continuation.yield(event) { logger.error("Shell event buffer overflow") }
    }

    private func receive(_ data: Data) {
        let timestamp = now()
        do {
            guard let kind = try registry.normalize(data, at: timestamp) else { return }
            exits.prune(retaining: registry.retainedSessions)
            switch kind {
            case .terminalDirectoryChanged(let terminal), .terminalCommandCompleted(let terminal, _):
                do { try exits.watch(terminal) }
                catch { logger.error("Shell process exit observation unavailable") }
            case .terminalSessionEnded(let session): exits.forget(session)
            default: break
            }
            let event = ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: timestamp,
                                      source: ActivitySourceID(rawValue: "shell.zsh"), kind: kind)
            if case .dropped = continuation.yield(event) { logger.error("Shell event buffer overflow") }
        } catch {
            logger.error("Rejected invalid shell metadata")
        }
    }
}
