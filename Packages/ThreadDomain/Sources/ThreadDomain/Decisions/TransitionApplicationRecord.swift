import Foundation

public struct TransitionApplicationID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public enum TransitionApplicationOutcome: String, Codable, Sendable {
    case activated, switched, deferred, alreadyActive, declined, confidenceRejected, staleTime, obsoleteContext
}

public enum TransitionApplicationPhase: String, Codable, Sendable { case context, review }

/// Records inferred active-focus policy application, independently of graph persistence and user selection.
public struct TransitionApplicationRecord: Equatable, Codable, Sendable {
    public let id: TransitionApplicationID
    public let timestamp: Date
    public let phase: TransitionApplicationPhase
    public let outcome: TransitionApplicationOutcome
    public let previous: ThreadID?
    public let target: ThreadID
    public let decisionRecordID: DecisionRecordID?

    public init(id: TransitionApplicationID, timestamp: Date, phase: TransitionApplicationPhase,
                outcome: TransitionApplicationOutcome, previous: ThreadID?, target: ThreadID,
                decisionRecordID: DecisionRecordID? = nil) {
        self.id = id; self.timestamp = timestamp; self.phase = phase
        self.outcome = outcome; self.previous = previous; self.target = target
        self.decisionRecordID = decisionRecordID
    }

    public var isValid: Bool {
        guard timestamp.timeIntervalSinceReferenceDate.isFinite else { return false }
        switch outcome {
        case .activated: return previous == nil
        case .switched: return previous != nil && previous != target
        case .alreadyActive: return previous == target
        default: return true
        }
    }
}

public protocol TransitionApplicationArchive: Sendable {
    func append(transitions: [TransitionApplicationRecord], at time: Date, retention: DecisionRetentionPolicy) async throws
    func transitionApplications(since time: Date, limit: Int) async throws -> [TransitionApplicationRecord]
}
