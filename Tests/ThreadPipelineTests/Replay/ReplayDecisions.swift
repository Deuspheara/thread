import Foundation
import ThreadDomain
import ThreadDecisions

/// Captures only the latest membership output while exercising actual decision implementations.
actor ReplayDecisions: DecisionEngine {
    private let unavailable: UnavailableReplayProvider?
    private let upstream: any DecisionEngine
    private(set) var membership: MembershipDecision?
    init(remoteUnavailable: Bool) {
        if remoteUnavailable {
            let provider = UnavailableReplayProvider()
            unavailable = provider
            upstream = HybridDecisionEngine(remote: provider, onFallback: { _ in })
        } else { unavailable = nil; upstream = HeuristicDecisionEngine() }
    }
    func remoteCalls() async -> Int { await unavailable?.calls ?? 0 }
    func classifyMembership(context: ActivityContext, candidates: [ScoredThreadCandidate]) async throws -> MembershipDecision {
        let result = try await upstream.classifyMembership(context: context, candidates: candidates)
        membership = result
        return result
    }
    func detectTransition(context: ActivityContext, active: ThreadID?, membership: MembershipDecision) async throws -> TransitionDecision {
        try await upstream.detectTransition(context: context, active: active, membership: membership)
    }
    func classifyPersistence(resource: Resource, context: ActivityContext) async throws -> PersistenceDecision {
        try await upstream.classifyPersistence(resource: resource, context: context)
    }
}

/// Simulates backend unavailability without opening any network connection.
private actor UnavailableReplayProvider: DecisionEngine {
    private(set) var calls = 0
    func classifyMembership(context: ActivityContext, candidates: [ScoredThreadCandidate]) throws -> MembershipDecision {
        calls += 1
        throw RemoteDecisionError.transportUnavailable
    }
    func detectTransition(context: ActivityContext, active: ThreadID?, membership: MembershipDecision) throws -> TransitionDecision {
        calls += 1
        throw RemoteDecisionError.transportUnavailable
    }
    func classifyPersistence(resource: Resource, context: ActivityContext) throws -> PersistenceDecision {
        calls += 1
        throw RemoteDecisionError.transportUnavailable
    }
}
