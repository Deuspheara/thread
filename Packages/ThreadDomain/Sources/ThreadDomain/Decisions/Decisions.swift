import Foundation

public enum MembershipTarget: Equatable, Codable, Sendable {
    case existing(ThreadID)
    case newThread
    case undetermined
}

/// Expresses inference only; application policy validates confidence and authorizes changes.
public struct MembershipDecision: Equatable, Codable, Sendable {
    public let target: MembershipTarget
    public let confidence: Double
    /// Local recording receipt; never used for policy or sent to a provider.
    public let recordID: DecisionRecordID?
    public init(target: MembershipTarget, confidence: Double, recordID: DecisionRecordID? = nil) {
        self.target = target; self.confidence = confidence; self.recordID = recordID
    }
}

public struct TransitionDecision: Equatable, Codable, Sendable {
    public let shouldTransition: Bool
    public let confidence: Double
    public let recordID: DecisionRecordID?
    public init(shouldTransition: Bool, confidence: Double, recordID: DecisionRecordID? = nil) {
        self.shouldTransition = shouldTransition; self.confidence = confidence; self.recordID = recordID
    }
}

public enum PersistenceDisposition: String, Codable, Sendable { case durable, sessionOnly, discard }

public struct PersistenceDecision: Equatable, Codable, Sendable {
    public let disposition: PersistenceDisposition
    public let confidence: Double
    public init(disposition: PersistenceDisposition, confidence: Double) { self.disposition = disposition; self.confidence = confidence }
}
