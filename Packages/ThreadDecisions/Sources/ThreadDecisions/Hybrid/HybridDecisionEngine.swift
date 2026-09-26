import Foundation
import ThreadDomain

public enum DecisionFallback: Sendable, Equatable {
    case remoteUnavailable
    case invalidResponse
}

/// Uses remote inference for uncertain local decisions while preserving offline results.
public struct HybridDecisionEngine: DecisionEngine {
    private let local: any DecisionEngine
    private let remoteProvider: @Sendable () async -> (any DecisionEngine)?
    private let onDecision: (@Sendable (DecisionRecord) async -> Void)?
    private let uptime: @Sendable () -> TimeInterval
    private let onFallback: @Sendable (DecisionFallback) -> Void

    public init(local: any DecisionEngine = HeuristicDecisionEngine(), remote: (any DecisionEngine)? = nil,
                remoteProvider: (@Sendable () async -> (any DecisionEngine)?)? = nil,
                onDecision: (@Sendable (DecisionRecord) async -> Void)? = nil,
                uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                onFallback: @escaping @Sendable (DecisionFallback) -> Void) {
        self.local = local
        self.remoteProvider = remoteProvider ?? { remote }
        self.onFallback = onFallback
        self.onDecision = onDecision
        self.uptime = uptime
    }

    public func classifyMembership(context: ActivityContext, candidates: [ScoredThreadCandidate]) async throws -> MembershipDecision {
        let started = uptime()
        let candidates = Array(candidates.prefix(8))
        let decision = try await local.classifyMembership(context: context, candidates: candidates)
        let clear = decision.target != .undetermined && valid(decision.confidence) && decision.confidence >= 0.92
        let result = try await resolve(decision, clear: clear, request: {
            try await $0.classifyMembership(context: context, candidates: candidates)
        }, accepts: { result in
            guard valid(result.confidence) else { return false }
            if case .existing(let id) = result.target { return candidates.contains { $0.candidate.id == id } }
            return true
        })
        // Local recording owns the receipt, even if an injected decision engine supplies its own ID.
        let value = MembershipDecision(target: result.value.target, confidence: result.value.confidence)
        let receipt = await record(.membership(value), origin: result.origin, context: context, started: started,
            candidates: candidates.map { $0.candidate.id })
        return MembershipDecision(target: value.target, confidence: value.confidence, recordID: receipt)
    }

    public func detectTransition(context: ActivityContext, active: ThreadID?, membership: MembershipDecision) async throws -> TransitionDecision {
        let started = uptime()
        let decision = try await local.detectTransition(context: context, active: active, membership: membership)
        try Task.checkCancellation()
        guard case .existing = membership.target else {
            return await recordTransition(decision, origin: .local, context: context, started: started)
        }
        let result = try await resolve(decision, clear: valid(decision.confidence) && decision.confidence >= 0.96,
            request: { try await $0.detectTransition(context: context, active: active, membership: membership) },
            accepts: { valid($0.confidence) })
        return await recordTransition(result.value, origin: result.origin, context: context, started: started)
    }

    public func classifyPersistence(resource: Resource, context: ActivityContext) async throws -> PersistenceDecision {
        let started = uptime()
        let decision = try await local.classifyPersistence(resource: resource, context: context)
        let result = try await resolve(decision, clear: valid(decision.confidence) && decision.confidence >= 0.92,
            request: { try await $0.classifyPersistence(resource: resource, context: context) },
            accepts: { valid($0.confidence) })
        await record(.persistence(resource.kind, result.value), origin: result.origin, context: context, started: started)
        return result.value
    }

    private func recordTransition(_ value: TransitionDecision, origin: DecisionOrigin,
                                  context: ActivityContext, started: TimeInterval) async -> TransitionDecision {
        let canonical = TransitionDecision(shouldTransition: value.shouldTransition, confidence: value.confidence)
        let receipt = await record(.transition(canonical), origin: origin, context: context, started: started)
        return TransitionDecision(shouldTransition: canonical.shouldTransition, confidence: canonical.confidence, recordID: receipt)
    }

    @discardableResult
    private func record(_ decision: RecordedDecision, origin: DecisionOrigin, context: ActivityContext,
                        started: TimeInterval, candidates: [ThreadID] = []) async -> DecisionRecordID? {
        guard let onDecision else { return nil }
        let elapsed = (uptime() - started) * 1000
        var seen: Set<ThreadID> = []
        let unique = candidates.filter { seen.insert($0).inserted }
        let id = DecisionRecordID(rawValue: UUID())
        await onDecision(DecisionRecord(id: id, timestamp: context.endedAt,
            origin: origin, elapsedMilliseconds: elapsed.isFinite ? min(max(elapsed, 0), 3_600_000) : 0,
            decision: decision, candidates: Array(unique.prefix(8))))
        return id
    }

    private func valid(_ confidence: Double) -> Bool {
        confidence.isFinite && (0...1).contains(confidence)
    }

    private func resolve<Value: Sendable>(_ localValue: Value, clear: Bool,
        request: (any DecisionEngine) async throws -> Value, accepts: (Value) -> Bool) async throws -> (value: Value, origin: DecisionOrigin) {
        try Task.checkCancellation()
        guard !clear, let remote = await remoteProvider() else { return (localValue, .local) }
        try Task.checkCancellation()
        do {
            let value = try await request(remote)
            try Task.checkCancellation()
            guard accepts(value) else {
                onFallback(.invalidResponse)
                return (localValue, .localFallback)
            }
            return (value, .remote)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as RemoteDecisionError {
            try Task.checkCancellation()
            onFallback(error == .invalidResponse || error == .responseTooLarge ? .invalidResponse : .remoteUnavailable)
            return (localValue, .localFallback)
        } catch {
            try Task.checkCancellation()
            onFallback(.remoteUnavailable)
            return (localValue, .localFallback)
        }
    }
}
