import Foundation

public struct DecisionRecordID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public enum DecisionOrigin: String, Codable, Sendable { case local, remote, localFallback }
public enum RecordedDecisionKind: String, Codable, Sendable { case membership, transition, persistence }

/// Keeps decision results without copying activity context, resource identities or provider inputs.
public enum RecordedDecision: Equatable, Codable, Sendable {
    case membership(MembershipDecision)
    case transition(TransitionDecision)
    case persistence(ResourceKind, PersistenceDecision)

    public var kind: RecordedDecisionKind {
        switch self { case .membership: .membership; case .transition: .transition; case .persistence: .persistence }
    }
    public var confidence: Double {
        switch self {
        case .membership(let decision): decision.confidence
        case .transition(let decision): decision.confidence
        case .persistence(_, let decision): decision.confidence
        }
    }
}

/// Captures the selected inference result and routing metadata, not policy authorization or graph application.
public struct DecisionRecord: Equatable, Codable, Sendable {
    public let id: DecisionRecordID
    public let timestamp: Date
    public let origin: DecisionOrigin
    public let elapsedMilliseconds: Double
    public let decision: RecordedDecision
    public let candidates: [ThreadID]
    public init(id: DecisionRecordID, timestamp: Date, origin: DecisionOrigin, elapsedMilliseconds: Double,
                decision: RecordedDecision, candidates: [ThreadID] = []) {
        self.id = id
        self.timestamp = timestamp
        self.origin = origin
        self.elapsedMilliseconds = elapsedMilliseconds
        self.decision = decision
        self.candidates = candidates
    }

    public var isValid: Bool {
        guard timestamp.timeIntervalSinceReferenceDate.isFinite, elapsedMilliseconds.isFinite,
              (0...3_600_000).contains(elapsedMilliseconds), decision.confidence.isFinite,
              (0...1).contains(decision.confidence), candidates.count <= 8,
              Set(candidates).count == candidates.count else { return false }
        if case .membership(let result) = decision, case .existing(let id) = result.target {
            return candidates.contains(id)
        }
        return true
    }
}

/// Bounds decision metadata independently of graph and normalized observation retention.
public struct DecisionRetentionPolicy: Sendable {
    public let lifetime: TimeInterval
    public let maximumRecords: Int
    public init(lifetime: TimeInterval = 30 * 24 * 60 * 60, maximumRecords: Int = 100_000) {
        precondition(lifetime.isFinite && lifetime > 0 && maximumRecords > 0)
        self.lifetime = lifetime
        self.maximumRecords = maximumRecords
    }
}
