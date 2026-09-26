import Foundation
import OSLog
import ThreadDomain

/// Forwards shell events immediately and enriches the newest terminal observation asynchronously.
public actor GitActivitySource: ActivitySource {
    private nonisolated let stream: AsyncStream<ActivityEvent>
    private let continuation: AsyncStream<ActivityEvent>.Continuation
    private let upstream: any ActivitySource
    private let resolver: GitRepositoryResolver
    private let now: @Sendable () -> Date
    private var lookup: Task<Void, Never>?
    private var lookupTerminal: TerminalSessionIdentity?
    private var lastRepository: RepositoryContext?
    private var started = false
    private let logger = Logger(subsystem: "app.thread.desktop", category: "git")

    public init(upstream: any ActivitySource, resolver: GitRepositoryResolver = GitRepositoryResolver(),
                now: @escaping @Sendable () -> Date = Date.init) {
        let channel = AsyncStream<ActivityEvent>.makeStream(bufferingPolicy: .bufferingNewest(128))
        stream = channel.stream
        continuation = channel.continuation
        self.upstream = upstream
        self.resolver = resolver
        self.now = now
    }

    public nonisolated func events() -> AsyncStream<ActivityEvent> { stream }

    public func run() async {
        guard !started else { return }
        started = true
        defer { lookup?.cancel(); continuation.finish() }
        for await event in upstream.events() {
            guard !Task.isCancelled else { return }
            yield(event)
            switch event.kind {
            case .terminalDirectoryChanged(let terminal): schedule(terminal, refresh: false)
            case .terminalCommandCompleted(let terminal, _): schedule(terminal, refresh: true)
            case .terminalSessionEnded(let session):
                if session == lookupTerminal { lookup?.cancel() }
            default: break
            }
        }
    }

    public func cancelPendingLookups() async {
        let pending = lookup
        lookup = nil
        pending?.cancel()
        await pending?.value
    }

    private func schedule(_ terminal: TerminalContext, refresh: Bool) {
        lookup?.cancel()
        lookupTerminal = terminal.session
        lookup = Task { [resolver] in
            do {
                try await Task.sleep(for: .milliseconds(150))
                let result = try await resolver.resolve(directory: terminal.workingDirectory, refresh: refresh)
                try Task.checkCancellation()
                publish(result, for: terminal)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Git metadata lookup unavailable")
                publish(.unavailable, for: terminal)
            }
        }
    }

    private func publish(_ resolution: RepositoryResolution, for terminal: TerminalContext) {
        let observation = RepositoryObservation(terminal: terminal.session, sequence: terminal.sequence, resolution: resolution)
        var kind = ActivityEventKind.repositoryChanged(observation)
        if case .available(let current) = resolution {
            if let previous = lastRepository, previous.gitDirectory == current.gitDirectory, previous.branch != current.branch {
                kind = .branchChanged(observation)
            }
            lastRepository = current
        } else { lastRepository = nil }
        yield(ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: now(), source: ActivitySourceID(rawValue: "git.local"),
                            kind: kind))
    }

    private func yield(_ event: ActivityEvent) {
        if case .dropped = continuation.yield(event) { logger.error("Git enrichment event buffer overflow") }
    }
}
