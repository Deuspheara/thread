import Foundation
import Testing
import ThreadDomain
import ThreadEngine
import ThreadDecisions
import ThreadPersistence

struct DurableRuntimeTests {
    let runtime = ActivityRuntimeTests()

    @Test func liveInferenceSurvivesDatabaseAndEngineRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("thread-runtime-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let engine = ActivityEngine(graph: ThreadGraphStore(), decisions: HeuristicDecisionEngine(), repository: database, archive: database, policy: runtime.policy)
        try await engine.prepareHistory()
        await runtime.sendProject("/durable/project", sequence: 1, session: TerminalSessionIdentity(rawValue: UUID()), to: engine)
        let observed = try await runtime.waitForOverview(engine.updates()) { $0.threads.count == 1 && $0.history == .saved }
        let stopped = await engine.stop()
        #expect(stopped == .saved)
        let threadID = try #require(observed.threads.first?.thread.id)
        #expect(try await database.snapshots(for: threadID, limit: 10).count == 1)
        #expect(try await database.events(since: .distantPast, limit: 100).count >= 2)
        let reopened = ThreadDatabase(directory: directory)
        try await reopened.prepare()
        let restored = ActivityEngine(graph: ThreadGraphStore(), decisions: HeuristicDecisionEngine(), repository: reopened, archive: reopened, policy: runtime.policy)
        try await restored.prepareHistory()
        let loaded = try await runtime.waitForOverview(restored.updates()) { $0.threads.count == 1 }
        let durable = observed.threads.map { ThreadDetail(thread: $0.thread, resources: $0.resources.filter { $0.persistence == .durable }) }
        #expect(loaded.threads == durable)
        #expect(observed.threads.flatMap(\.resources).contains { $0.persistence == .sessionOnly })
        #expect(loaded.threads.flatMap(\.resources).allSatisfy { $0.persistence == .durable })
        #expect(loaded.history == .saved)
        await restored.stop()
    }

    @Test func failedLoadCannotOverwriteUnreadHistoryAndRetryPreservesQueuedWork() async throws {
        let repository = FailingHistory()
        let id = ThreadID(rawValue: UUID())
        let time = Date(timeIntervalSince1970: 100)
        let old = ThreadDetail(thread: ThreadDomain.Thread(id: id, title: "Earlier", createdAt: time, lastActiveAt: time), resources: [])
        await repository.configure(state: ThreadGraphState(threads: [old], corrections: []), failLoad: true)
        let engine = ActivityEngine(graph: ThreadGraphStore(), decisions: HeuristicDecisionEngine(), repository: repository, policy: runtime.policy)
        await #expect(throws: FailingHistory.Failure.self) { try await engine.prepareHistory() }
        await runtime.sendProject("/new/project", sequence: 1, session: TerminalSessionIdentity(rawValue: UUID()), to: engine)
        try await Task.sleep(for: .milliseconds(60))
        #expect(await repository.writeAttempts == 0)
        await repository.allowLoads()
        try await engine.prepareHistory()
        let overview = try await runtime.waitForOverview(engine.updates()) { $0.threads.count == 2 && $0.history == .saved }
        #expect(overview.threads.contains { $0.thread.id == id })
        await engine.stop()
    }

    @Test func archiveFailureRetriesTheSameSnapshotWithoutLosingLiveHistory() async throws {
        let repository = FailingHistory()
        let archive = FailingArchive()
        let engine = ActivityEngine(graph: ThreadGraphStore(), decisions: HeuristicDecisionEngine(), repository: repository,
                                    archive: archive, policy: runtime.policy)
        try await engine.prepareHistory()
        await runtime.sendProject("/archive/project", sequence: 1, session: TerminalSessionIdentity(rawValue: UUID()), to: engine)
        let failed = try await runtime.waitForOverview(engine.updates()) { $0.history == .unsaved }
        #expect(failed.threads.count == 1)
        let originalIDs = await archive.snapshotAttempts.first
        await archive.allowWrites()
        try await engine.prepareHistory()
        let saved = try await runtime.waitForOverview(engine.updates()) { $0.history == .saved && !$0.threads.isEmpty }
        #expect(saved.threads == failed.threads)
        #expect(await archive.snapshotAttempts.last == originalIDs)
        #expect(await archive.savedSnapshots.count == 1)
        await engine.stop()
    }

    @Test func editSaveFailureReportsUnsavedAndRetryKeepsUserTitle() async throws {
        let repository = FailingHistory()
        let id = ThreadID(rawValue: UUID())
        let time = Date(timeIntervalSince1970: 100)
        let detail = ThreadDetail(thread: ThreadDomain.Thread(id: id, title: "Original", createdAt: time, lastActiveAt: time), resources: [])
        await repository.configure(state: ThreadGraphState(threads: [detail], corrections: []), failLoad: false)
        let engine = ActivityEngine(graph: ThreadGraphStore(), decisions: HeuristicDecisionEngine(), repository: repository)
        try await engine.prepareHistory()
        await repository.failWrites()
        #expect(try await engine.edit(.rename(id, title: "User title")) == .unsaved)
        #expect(await repository.state.threads.first?.thread.title == "Original")
        await repository.allowWrites()
        try await engine.prepareHistory()
        #expect(await repository.state.threads.first?.thread.title == "User title")
        await engine.stop()
    }

    @Test func failedSaveKeepsLiveGraphAndExplicitRetryPersistsIt() async throws {
        let repository = FailingHistory()
        await repository.failWrites()
        let engine = ActivityEngine(graph: ThreadGraphStore(), decisions: HeuristicDecisionEngine(), repository: repository, policy: runtime.policy)
        try await engine.prepareHistory()
        await runtime.sendProject("/retry/project", sequence: 1, session: TerminalSessionIdentity(rawValue: UUID()), to: engine)
        let failed = try await runtime.waitForOverview(engine.updates()) { $0.history == .unsaved }
        #expect(failed.threads.count == 1)
        await repository.allowWrites()
        try await engine.prepareHistory()
        let saved = try await runtime.waitForOverview(engine.updates()) { $0.history == .saved && !$0.threads.isEmpty }
        #expect(saved.threads == failed.threads)
        #expect(await repository.state.threads.count == 1)
        await engine.stop()
    }
}

private actor FailingHistory: ThreadRepository {
    enum Failure: Error { case unavailable }
    private(set) var state = ThreadGraphState(threads: [], corrections: [])
    private(set) var writeAttempts = 0
    private var loadFails = false
    private var writeFails = false
    func configure(state: ThreadGraphState, failLoad: Bool) { self.state = state; loadFails = failLoad }
    func allowLoads() { loadFails = false }
    func allowWrites() { writeFails = false }
    func failWrites() { writeFails = true }
    func loadGraph() throws -> ThreadGraphState {
        if loadFails { throw Failure.unavailable }
        return state
    }
    func saveGraph(_ state: ThreadGraphState) throws {
        writeAttempts += 1
        if writeFails { throw Failure.unavailable }
        self.state = state
    }
}

private actor FailingArchive: ActivityArchive {
    private var fails = true
    private(set) var snapshotAttempts: [[ThreadSnapshotID]] = []
    private(set) var savedSnapshots: [ThreadSnapshot] = []
    private var savedEvents: [ArchivedActivityEvent] = []
    func allowWrites() { fails = false }
    func append(events: [ArchivedActivityEvent], snapshots: [ThreadSnapshot], at time: Date, retention: HistoryRetentionPolicy) throws {
        if events.isEmpty && snapshots.isEmpty { return }
        snapshotAttempts.append(snapshots.map(\.id))
        if fails { throw FailingHistory.Failure.unavailable }
        savedSnapshots += snapshots
        savedEvents += events
    }
    func snapshots(for thread: ThreadID, limit: Int) -> [ThreadSnapshot] { Array(savedSnapshots.filter { $0.thread == thread }.prefix(limit)) }
    func events(since time: Date, limit: Int) -> [ArchivedActivityEvent] { Array(savedEvents.filter { $0.event.timestamp >= time }.prefix(limit)) }
}
