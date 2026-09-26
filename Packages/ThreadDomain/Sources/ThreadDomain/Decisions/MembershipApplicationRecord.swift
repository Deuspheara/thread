import Foundation

public struct MembershipApplicationID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public enum MembershipApplicationOutcome: String, Codable, Sendable {
    case waiting, confirmedAttachment, provisionalAttachment, noAttachment
}

/// Records membership acceptance in the live graph, not durable commit or assignment accuracy.
public struct MembershipApplicationRecord: Equatable, Codable, Sendable {
    public let id: MembershipApplicationID
    public let timestamp: Date
    public let outcome: MembershipApplicationOutcome
    public let thread: ThreadID?
    public let decisionRecordID: DecisionRecordID?

    public init(id: MembershipApplicationID, timestamp: Date, outcome: MembershipApplicationOutcome, thread: ThreadID?,
                decisionRecordID: DecisionRecordID? = nil) {
        self.id = id; self.timestamp = timestamp; self.outcome = outcome; self.thread = thread
        self.decisionRecordID = decisionRecordID
    }

    public var isValid: Bool {
        guard timestamp.timeIntervalSinceReferenceDate.isFinite else { return false }
        switch outcome {
        case .waiting, .noAttachment: return thread == nil
        case .confirmedAttachment, .provisionalAttachment: return thread != nil
        }
    }
}

/// Persists local membership outcomes without copying context or resource identities.
public protocol MembershipApplicationArchive: Sendable {
    func append(applications: [MembershipApplicationRecord], at time: Date, retention: DecisionRetentionPolicy) async throws
    func membershipApplications(since time: Date, limit: Int) async throws -> [MembershipApplicationRecord]
}
