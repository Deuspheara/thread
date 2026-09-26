import Foundation
import OSLog
import ThreadDomain

/// Normalizes local browser datagrams into a bounded single-consumer activity stream.
@MainActor
public final class BrowserActivitySource: ActivitySource {
    private nonisolated let stream: AsyncStream<ActivityEvent>
    private let continuation: AsyncStream<ActivityEvent>.Continuation
    private let url: URL
    private let now: @Sendable () -> Date
    private var registry = BrowserConnectionRegistry()
    private var stopped = false
    private let logger = Logger(subsystem: "app.thread.desktop", category: "browser")
    private lazy var listener = UnixDatagramListener { [weak self] data in self?.receive(data) }

    public init(url: URL = BrowserSocketLocation.defaultURL, now: @escaping @Sendable () -> Date = Date.init) {
        let channel = AsyncStream<ActivityEvent>.makeStream(bufferingPolicy: .bufferingNewest(128))
        stream = channel.stream
        continuation = channel.continuation
        self.url = url
        self.now = now
        continuation.onTermination = { [weak self] _ in Task { @MainActor in self?.stop() } }
    }

    public func isConnected(_ id: UUID) -> Bool { !stopped && registry.isConnected(id) }

    public nonisolated func events() -> AsyncStream<ActivityEvent> { stream }
    public func start() throws {
        guard !stopped else { throw BrowserTransportError.unavailable }
        try listener.start(at: url)
        logger.info("Browser observation started")
    }
    isolated deinit { stop() }
    public func stop() {
        stopped = true
        listener.stop()
        continuation.finish()
    }

    private func receive(_ data: Data) {
        let timestamp = now()
        do {
            guard let kind = try registry.normalize(data, at: timestamp) else { return }
            let event = ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: timestamp,
                                      source: ActivitySourceID(rawValue: "browser.native"), kind: kind)
            if case .dropped = continuation.yield(event) { logger.error("Browser event buffer overflow") }
        } catch {
            logger.error("Rejected invalid browser metadata")
        }
    }
}
