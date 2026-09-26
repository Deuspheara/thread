import Foundation
import ThreadDomain

/// Owns replaceable remote inference and cancels requests when its configuration changes.
public actor RemoteDecisionConnection: DecisionEngine {
    private enum Reply: Sendable {
        case membership(MembershipDecision)
        case transition(TransitionDecision)
        case persistence(PersistenceDecision)
    }
    private var engine: (any DecisionEngine)?
    private var revision = UUID()
    private var pending: [UUID: Task<Reply, Error>] = [:]

    public init() {}

    public func configure(_ engine: (any DecisionEngine)?) {
        revision = UUID()
        self.engine = engine
        for task in pending.values { task.cancel() }
    }

    public func availableEngine() -> (any DecisionEngine)? {
        engine == nil ? nil : self
    }

    public func classifyMembership(context: ActivityContext, candidates: [ScoredThreadCandidate]) async throws -> MembershipDecision {
        let reply = try await perform { engine in
            .membership(try await engine.classifyMembership(context: context, candidates: candidates))
        }
        guard case .membership(let value) = reply else { throw RemoteDecisionError.invalidResponse }
        return value
    }

    public func detectTransition(context: ActivityContext, active: ThreadID?, membership: MembershipDecision) async throws -> TransitionDecision {
        let reply = try await perform { engine in
            .transition(try await engine.detectTransition(context: context, active: active, membership: membership))
        }
        guard case .transition(let value) = reply else { throw RemoteDecisionError.invalidResponse }
        return value
    }

    public func classifyPersistence(resource: Resource, context: ActivityContext) async throws -> PersistenceDecision {
        let reply = try await perform { engine in
            .persistence(try await engine.classifyPersistence(resource: resource, context: context))
        }
        guard case .persistence(let value) = reply else { throw RemoteDecisionError.invalidResponse }
        return value
    }

    private func perform(_ request: @escaping @Sendable (any DecisionEngine) async throws -> Reply) async throws -> Reply {
        try Task.checkCancellation()
        guard let engine else { throw RemoteDecisionError.transportUnavailable }
        guard pending.count < 8 else { throw RemoteDecisionError.rateLimited }
        let id = UUID()
        let startedRevision = revision
        let task = Task { try await request(engine) }
        pending[id] = task
        defer { pending.removeValue(forKey: id) }
        do {
            let result = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            try Task.checkCancellation()
            guard startedRevision == revision else { throw RemoteDecisionError.transportUnavailable }
            return result
        } catch {
            try Task.checkCancellation()
            // Configuration cancellation should fall back locally; caller cancellation still propagates.
            if startedRevision != revision { throw RemoteDecisionError.transportUnavailable }
            throw error
        }
    }
}
