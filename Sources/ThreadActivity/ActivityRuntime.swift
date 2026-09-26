import Foundation
import ThreadDomain
import ThreadEngine
import OSLog

/// Owns observation, history preparation and inference recording independently of presentation.
@MainActor
public final class ActivityRuntime {
    public struct Availability {
        public let shell: Bool
        public let browser: Bool
    }

    public let reading: any ThreadReading
    public let editing: any ThreadEditing
    private let engine: ActivityEngine
    private let sources: ObservationSources
    private let session: ObservationSession
    private let prepareStorage: @MainActor @Sendable () async throws -> Void
    private let flushRecords: @Sendable () async -> Void
    private let publications: AsyncStream<ThreadPresentation>
    private let continuation: AsyncStream<ThreadPresentation>.Continuation
    private var eventsTask: Task<Void, Never>?
    private var publicationTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Error>?
    private var preparationGeneration = 0
    private var stopped = false

    init(sources: ObservationSources, session: ObservationSession, engine: ActivityEngine, reading: any ThreadReading,
         prepareStorage: @escaping @MainActor @Sendable () async throws -> Void,
         flushRecords: @escaping @Sendable () async -> Void) {
        self.sources = sources
        self.session = session
        self.engine = engine
        editing = engine
        self.reading = reading
        self.prepareStorage = prepareStorage
        self.flushRecords = flushRecords
        let channel = AsyncStream<ThreadPresentation>.makeStream(bufferingPolicy: .bufferingNewest(1))
        publications = channel.stream
        continuation = channel.continuation
    }

    public func contexts() -> AsyncStream<CurrentContext> { session.contexts() }
    public func updates() -> AsyncStream<ThreadPresentation> { publications }

    public func start() -> Availability? {
        guard !stopped, eventsTask == nil, let startup = sources.start() else { return nil }
        eventsTask = Task { [session] in await session.run(sources: startup.events) }
        publicationTask = Task { [engine, reading, continuation, flushRecords] in
            var previousCount = -1
            var previousFailure: ActivityFailure?
            var previousHistory: HistoryStatus?
            for await overview in engine.updates() {
                guard !Task.isCancelled else { return }
                if overview.history == .unsaved, previousHistory != .unsaved {
                    Logger(subsystem: "app.thread.desktop", category: "persistence").error("History save unavailable")
                }
                if overview.failure != nil, overview.failure != previousFailure {
                    Logger(subsystem: "app.thread.desktop", category: "classification").error("Activity inference degraded")
                }
                previousHistory = overview.history
                previousFailure = overview.failure
                if overview.threads.count != previousCount {
                    Logger(subsystem: "app.thread.desktop", category: "classification").info("Inferred Thread count: \(overview.threads.count)")
                    previousCount = overview.threads.count
                }
                do {
                    let summaries = try await reading.recentSummaries(limit: 20)
                    continuation.yield(ThreadPresentation(threads: summaries, active: overview.active,
                        failure: overview.failure, history: overview.history))
                } catch {
                    Logger(subsystem: "app.thread.desktop", category: "persistence").error("Recent work publication unavailable")
                }
                await flushRecords()
            }
        }
        _ = preparation()
        return Availability(shell: startup.shellAvailable, browser: startup.browserAvailable)
    }

    public func prepare() async throws {
        guard !stopped else { throw CancellationError() }
        let task = preparation()
        let generation = preparationGeneration
        do {
            try await task.value
            guard !stopped else { throw CancellationError() }
        } catch {
            if generation == preparationGeneration { preparationTask = nil }
            throw error
        }
    }

    public func shutdown() async {
        stop()
        await eventsTask?.value
        await publicationTask?.value
        if let preparationTask {
            do { try await preparationTask.value }
            catch {
                if !(error is CancellationError) {
                    Logger(subsystem: "app.thread.desktop", category: "persistence").error("History preparation unavailable at shutdown")
                }
            }
        }
        await sources.cancelPendingLookups()
        if await engine.stop() == .unsaved {
            Logger(subsystem: "app.thread.desktop", category: "persistence").error("Final history save unavailable")
        }
        await flushRecords()
    }

    public func stop() {
        guard !stopped else { return }
        stopped = true
        sources.stop()
        eventsTask?.cancel()
        publicationTask?.cancel()
        preparationTask?.cancel()
        continuation.finish()
    }

    isolated deinit { stop() }

    private func preparation() -> Task<Void, Error> {
        if let preparationTask { return preparationTask }
        preparationGeneration += 1
        let task = Task { [prepareStorage] in try await prepareStorage() }
        preparationTask = task
        return task
    }
}
