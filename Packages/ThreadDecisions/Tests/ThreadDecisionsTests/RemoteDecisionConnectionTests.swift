import Foundation
import Testing
import ThreadDomain
import ThreadDecisions

struct RemoteDecisionConnectionTests {
    private let context = ActivityContext(startedAt: Date(timeIntervalSince1970: 1),
        endedAt: Date(timeIntervalSince1970: 2), resources: [])

    @Test func disabledRoutingIsLocalAndEnablingRoutesAllOperations() async throws {
        let connection = RemoteDecisionConnection()
        let hybrid = HybridDecisionEngine(remoteProvider: { await connection.availableEngine() },
            onFallback: { _ in Issue.record("Unexpected fallback") })
        #expect(try await hybrid.classifyMembership(context: context, candidates: []).target == .undetermined)
        await connection.configure(FixedRemote())
        #expect(try await hybrid.classifyMembership(context: context, candidates: []).target == .newThread)
        let membership = MembershipDecision(target: .existing(ThreadID(rawValue: UUID())), confidence: 0.8)
        #expect(try await connection.detectTransition(context: context, active: nil, membership: membership).confidence == 0.99)
        #expect(try await connection.classifyPersistence(resource: .workingDirectory("/fixture"), context: context).confidence == 0.99)
        await connection.configure(nil)
        #expect(try await hybrid.classifyMembership(context: context, candidates: []).target == .undetermined)
    }

    @Test func disablingCancelsTheChildAndRejectsALateResultWhileHybridFallsBack() async throws {
        let gate = DelayedRemote()
        var entered = gate.entered.makeAsyncIterator()
        let connection = RemoteDecisionConnection()
        await connection.configure(gate)
        let hybrid = HybridDecisionEngine(remoteProvider: { await connection.availableEngine() }, onFallback: {
            #expect($0 == .remoteUnavailable)
        })
        let pending = Task { try await hybrid.classifyMembership(context: context, candidates: []) }
        await entered.next()
        await connection.configure(nil)
        await gate.finish()
        #expect(try await pending.value.target == .undetermined)
        #expect(await gate.childCancelled)
    }

    @Test func replacingConfigurationCannotApplyThePreviousServersReply() async throws {
        let gate = DelayedRemote()
        var entered = gate.entered.makeAsyncIterator()
        let connection = RemoteDecisionConnection()
        await connection.configure(gate)
        let pending = Task { try await connection.classifyMembership(context: context, candidates: []) }
        await entered.next()
        await connection.configure(FixedRemote())
        await gate.finish()
        await #expect(throws: RemoteDecisionError.transportUnavailable) { try await pending.value }
        #expect(try await connection.classifyMembership(context: context, candidates: []).target == .newThread)
    }

    @Test func callerCancellationStillPropagatesInsteadOfBecomingALocalFallback() async throws {
        let gate = DelayedRemote()
        var entered = gate.entered.makeAsyncIterator()
        let connection = RemoteDecisionConnection()
        await connection.configure(gate)
        let hybrid = HybridDecisionEngine(remoteProvider: { await connection.availableEngine() },
            onFallback: { _ in Issue.record("Caller cancellation is not fallback") })
        let pending = Task { try await hybrid.classifyMembership(context: context, candidates: []) }
        await entered.next()
        pending.cancel()
        await gate.finish()
        await #expect(throws: CancellationError.self) { try await pending.value }
    }

    @Test func pendingRequestsRemainBoundedUntilCancelledWorkFinishes() async throws {
        let gate = DelayedRemote()
        var entered = gate.entered.makeAsyncIterator()
        let connection = RemoteDecisionConnection()
        await connection.configure(gate)
        let tasks = (0..<8).map { _ in Task { try await connection.classifyMembership(context: context, candidates: []) } }
        for _ in 0..<8 { await entered.next() }
        await #expect(throws: RemoteDecisionError.rateLimited) {
            try await connection.classifyMembership(context: context, candidates: [])
        }
        await connection.configure(nil)
        await gate.finish()
        for task in tasks {
            await #expect(throws: RemoteDecisionError.transportUnavailable) { try await task.value }
        }
    }
}

private struct FixedRemote: DecisionEngine {
    func classifyMembership(context: ActivityContext, candidates: [ScoredThreadCandidate]) -> MembershipDecision {
        MembershipDecision(target: .newThread, confidence: 0.99)
    }
    func detectTransition(context: ActivityContext, active: ThreadID?, membership: MembershipDecision) -> TransitionDecision {
        TransitionDecision(shouldTransition: true, confidence: 0.99)
    }
    func classifyPersistence(resource: Resource, context: ActivityContext) -> PersistenceDecision {
        PersistenceDecision(disposition: .durable, confidence: 0.99)
    }
}

// Deliberately returns after cancellation to exercise stale-result rejection.
private actor DelayedRemote: DecisionEngine {
    nonisolated let entered: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private var pending: [CheckedContinuation<Void, Never>] = []
    private(set) var childCancelled = false

    init() { (entered, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(8)) }

    func classifyMembership(context: ActivityContext, candidates: [ScoredThreadCandidate]) async -> MembershipDecision {
        await withCheckedContinuation { pending.append($0); continuation.yield(()) }
        childCancelled = Task.isCancelled
        return MembershipDecision(target: .newThread, confidence: 1)
    }
    func finish() { for item in pending { item.resume() }; pending.removeAll() }
    func detectTransition(context: ActivityContext, active: ThreadID?, membership: MembershipDecision) -> TransitionDecision {
        TransitionDecision(shouldTransition: true, confidence: 1)
    }
    func classifyPersistence(resource: Resource, context: ActivityContext) -> PersistenceDecision {
        PersistenceDecision(disposition: .durable, confidence: 1)
    }
}
