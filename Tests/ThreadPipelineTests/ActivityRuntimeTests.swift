import Foundation
import Testing
import ThreadDomain
import ThreadEngine
import ThreadDecisions

struct ActivityRuntimeTests {
    enum Timeout: Error { case expired }
    let policy = AggregationPolicy(quietInterval: 0.02, maximumBatchInterval: 0.1, evidenceLifetime: 1)

    func sendProject(_ path: String, sequence: UInt64, session: TerminalSessionIdentity, to engine: ActivityEngine) async {
        let terminal = TerminalContext(session: session, processIdentifier: 1, workingDirectory: path, terminalApplication: nil, sequence: sequence)
        let repository = RepositoryContext(identity: RepositoryIdentity(commonDirectory: path + "/.git"), rootPath: path,
            gitDirectory: path + "/.git", branch: "fix", head: nil, dirty: RepositoryDirtySummary(changedTrackedFiles: 0, conflictedFiles: 0))
        for kind in [ActivityEventKind.terminalDirectoryChanged(terminal), .repositoryChanged(
            RepositoryObservation(terminal: session, sequence: sequence, resolution: .available(repository)))] {
            await engine.ingest(ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: Date(),
                source: ActivitySourceID(rawValue: "runtime-test"), kind: kind))
        }
    }

    func waitForOverview(_ stream: AsyncStream<ThreadOverview>, matching: @escaping @Sendable (ThreadOverview) -> Bool) async throws -> ThreadOverview {
        try await withThrowingTaskGroup(of: ThreadOverview.self) { group in
            group.addTask {
                for await overview in stream where matching(overview) { return overview }
                throw Timeout.expired
            }
            group.addTask { try await Task.sleep(for: .seconds(2)); throw Timeout.expired }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    @Test func quietDeadlinePublishesAThreadWithoutAnotherIncomingEvent() async throws {
        let engine = ActivityEngine(graph: ThreadGraphStore(), decisions: HeuristicDecisionEngine(), policy: policy)
        await sendProject("/work/A", sequence: 1, session: TerminalSessionIdentity(rawValue: UUID()), to: engine)
        do {
            let overview = try await waitForOverview(engine.updates()) { !$0.threads.isEmpty }
            #expect(overview.threads.first?.thread.title == "A · fix")
            #expect(overview.active == overview.threads.first?.thread.id)
            #expect(overview.failure == nil)
        } catch { await engine.stop(); throw error }
        await engine.stop()
        var iterator = engine.updates().makeAsyncIterator()
        #expect(await iterator.next() == nil)
    }

    @Test func delayedOldInferenceCannotSelectActiveWorkAfterNewEvents() async throws {
        let decisions = GatedDecisions()
        let graph = ThreadGraphStore()
        let records = TransitionApplicationsProbe()
        let engine = ActivityEngine(graph: graph, decisions: decisions, policy: policy,
            onTransitionApplication: { await records.record($0) })
        let session = TerminalSessionIdentity(rawValue: UUID())
        await sendProject("/work/A", sequence: 1, session: session, to: engine)
        // The gate deliberately delays only the first provider response.
        await decisions.waitUntilEntered()
        await sendProject("/work/B", sequence: 2, session: session, to: engine)
        await decisions.release()
        do {
            let overview = try await waitForOverview(engine.updates()) { $0.threads.count == 2 && $0.active != nil }
            #expect(overview.threads.first { $0.thread.id == overview.active }?.thread.title == "B · fix")
        } catch { await engine.stop(); throw error }
        await engine.stop()
        #expect(await records.records.map(\.outcome) == [.obsoleteContext, .activated])
    }
}

private actor GatedDecisions: DecisionEngine {
    private let base = HeuristicDecisionEngine()
    private var entered = false
    private var waiting: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() { waiting?.resume(); waiting = nil }
    func classifyMembership(context: ActivityContext, candidates: [ScoredThreadCandidate]) async throws -> MembershipDecision {
        if !entered {
            entered = true
            await withCheckedContinuation { continuation in
                waiting = continuation
                observer?.resume()
                observer = nil
            }
        }
        return try await base.classifyMembership(context: context, candidates: candidates)
    }
    func detectTransition(context: ActivityContext, active: ThreadID?, membership: MembershipDecision) async throws -> TransitionDecision {
        try await base.detectTransition(context: context, active: active, membership: membership)
    }
    func classifyPersistence(resource: Resource, context: ActivityContext) async throws -> PersistenceDecision {
        try await base.classifyPersistence(resource: resource, context: context)
    }
}
