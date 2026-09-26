import ThreadDomain

public enum MembershipAuthorization: Equatable, Sendable {
    case automatic(MembershipTarget)
    case provisional(ThreadID)
    case wait
}

/// Validates inference confidence and candidate scope before permitting membership changes.
public struct DecisionPolicy: Sendable {
    public let automaticThreshold: Double
    public let provisionalThreshold: Double

    public init(automaticThreshold: Double = 0.92, provisionalThreshold: Double = 0.72) {
        precondition((0...1).contains(provisionalThreshold) && (provisionalThreshold...1).contains(automaticThreshold))
        self.automaticThreshold = automaticThreshold
        self.provisionalThreshold = provisionalThreshold
    }

    public func authorize(_ decision: MembershipDecision, candidates: Set<ThreadID>) -> MembershipAuthorization {
        guard decision.confidence.isFinite, (0...1).contains(decision.confidence) else { return .wait }
        switch decision.target {
        case .undetermined: return .wait
        case .existing(let id):
            guard candidates.contains(id) else { return .wait }
            if decision.confidence >= automaticThreshold { return .automatic(.existing(id)) }
            if decision.confidence >= provisionalThreshold { return .provisional(id) }
            return .wait
        case .newThread:
            // Low-confidence guesses must not proliferate provisional Threads.
            return decision.confidence >= automaticThreshold ? .automatic(.newThread) : .wait
        }
    }
}
