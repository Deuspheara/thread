import Foundation
import Testing
import ThreadDomain
import ThreadDecisions

struct HybridDecisionTests {
    private let context = ActivityContext(startedAt: Date(timeIntervalSince1970: 1),
        endedAt: Date(timeIntervalSince1970: 2), resources: [])

    @Test func offlineAndClearDecisionsNeverRequestRemote() async throws {
        let remote = Probe()
        let local = Probe(membership: MembershipDecision(target: .newThread, confidence: 0.97))
        let hybrid = HybridDecisionEngine(local: local, remote: remote, onFallback: { _ in Issue.record("Unexpected fallback") })
        #expect(try await hybrid.classifyMembership(context: context, candidates: []).target == .newThread)
        #expect(await remote.calls == 0)
        let offline = HybridDecisionEngine(onFallback: { _ in Issue.record("Offline operation is not a failure") })
        #expect(try await offline.classifyMembership(context: context, candidates: []).target == .undetermined)
    }

    @Test func ambiguityUsesRemoteButMalformedAndUnknownTargetsFallBack() async throws {
        let local = Probe()
        let remote = Probe(membership: MembershipDecision(target: .newThread, confidence: 0.95))
        let notices = Notices()
        var iterator = notices.stream.makeAsyncIterator()
        let hybrid = HybridDecisionEngine(local: local, remote: remote, onFallback: { notices.record($0) })
        #expect(try await hybrid.classifyMembership(context: context, candidates: []).target == .newThread)
        await remote.setMembership(MembershipDecision(target: .existing(ThreadID(rawValue: UUID())), confidence: 1))
        #expect(try await hybrid.classifyMembership(context: context, candidates: []).target == .undetermined)
        await remote.setMembership(MembershipDecision(target: .newThread, confidence: .nan))
        #expect(try await hybrid.classifyMembership(context: context, candidates: []).target == .undetermined)
        #expect(await iterator.next() == .invalidResponse)
        #expect(await iterator.next() == .invalidResponse)
    }

    @Test func transportFailureFallsBackButCancellationPropagates() async throws {
        let remote = Probe()
        let notices = Notices()
        var iterator = notices.stream.makeAsyncIterator()
        let hybrid = HybridDecisionEngine(local: Probe(), remote: remote, onFallback: { notices.record($0) })
        await remote.setFailure(.unavailable)
        #expect(try await hybrid.classifyMembership(context: context, candidates: []).target == .undetermined)
        #expect(await iterator.next() == .remoteUnavailable)
        await remote.setFailure(.cancelled)
        await #expect(throws: CancellationError.self) {
            try await hybrid.classifyMembership(context: context, candidates: [])
        }
        notices.finish()
        #expect(await iterator.next() == nil)
    }

    @Test func transitionAndPersistenceRouting() async throws {
        let remote = Probe()
        let hybrid = HybridDecisionEngine(local: Probe(), remote: remote, onFallback: { _ in Issue.record("Unexpected fallback") })
        let membership = MembershipDecision(target: .existing(ThreadID(rawValue: UUID())), confidence: 0.94)
        _ = try await hybrid.detectTransition(context: context, active: nil, membership: membership)
        _ = try await hybrid.classifyPersistence(resource: .workingDirectory("/work"), context: context)
        #expect(await remote.calls == 2)
    }
}

private actor Probe: DecisionEngine {
    enum Failure { case unavailable, cancelled }
    struct Unavailable: Error {}
    var calls = 0
    private var membership: MembershipDecision
    private var failure: Failure?
    init(membership: MembershipDecision = MembershipDecision(target: .undetermined, confidence: 0.5)) {
        self.membership = membership
    }
    func setMembership(_ value: MembershipDecision) { membership = value }
    func setFailure(_ value: Failure) { failure = value }
    func classifyMembership(context: ActivityContext, candidates: [ScoredThreadCandidate]) throws -> MembershipDecision {
        calls += 1
        switch failure {
        case .unavailable: throw Unavailable()
        case .cancelled: throw CancellationError()
        case nil: return membership
        }
    }
    func detectTransition(context: ActivityContext, active: ThreadID?, membership: MembershipDecision) -> TransitionDecision {
        calls += 1
        return TransitionDecision(shouldTransition: true, confidence: 0.5)
    }
    func classifyPersistence(resource: Resource, context: ActivityContext) -> PersistenceDecision {
        calls += 1
        return PersistenceDecision(disposition: .durable, confidence: 0.5)
    }
}

private struct Notices: Sendable {
    let stream: AsyncStream<DecisionFallback>
    private let continuation: AsyncStream<DecisionFallback>.Continuation
    init() {
        (stream, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(8))
    }
    func record(_ value: DecisionFallback) { continuation.yield(value) }
    func finish() { continuation.finish() }
}
