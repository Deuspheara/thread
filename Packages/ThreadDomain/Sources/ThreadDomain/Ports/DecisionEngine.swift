import Foundation

/// Isolates replaceable inference from deterministic scheduling, graph mutation, and restoration.
public protocol DecisionEngine: Sendable {
    func classifyMembership(context: ActivityContext, candidates: [ScoredThreadCandidate]) async throws -> MembershipDecision
    func detectTransition(context: ActivityContext, active: ThreadID?, membership: MembershipDecision) async throws -> TransitionDecision
    func classifyPersistence(resource: Resource, context: ActivityContext) async throws -> PersistenceDecision
}
