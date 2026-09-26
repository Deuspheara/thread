import ThreadDomain

/// Authorizes retention decisions without treating uncertain inference as durable consent.
public struct ResourcePersistencePolicy: Sendable {
    private let minimumConfidence: Double
    public init(minimumConfidence: Double = 0.92) {
        precondition(minimumConfidence.isFinite && (0...1).contains(minimumConfidence))
        self.minimumConfidence = minimumConfidence
    }
    public func authorize(_ decision: PersistenceDecision) -> PersistenceDisposition {
        guard decision.confidence.isFinite, (0...1).contains(decision.confidence),
              decision.confidence >= minimumConfidence else { return .sessionOnly }
        return decision.disposition
    }
}
