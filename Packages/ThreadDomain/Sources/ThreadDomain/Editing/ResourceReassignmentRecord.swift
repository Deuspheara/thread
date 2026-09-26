import Foundation

public struct ResourceReassignmentID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public enum ReassignmentOrigin: String, Codable, Sendable { case inferred, explicit }
public enum ReassignmentOutcome: String, Codable, Sendable { case moved, confirmed }

/// Attributes an explicit reassignment to its selected prior edge, without copying resource identity.
public struct ResourceReassignmentRecord: Equatable, Codable, Sendable {
    public let id: ResourceReassignmentID
    public let timestamp: Date
    public let resourceKind: ResourceKind
    public let origin: ReassignmentOrigin
    public let status: MembershipStatus
    public let outcome: ReassignmentOutcome
    public let source: ThreadID
    public let target: ThreadID
    public let decisionRecordID: DecisionRecordID?

    public init(id: ResourceReassignmentID, timestamp: Date, resourceKind: ResourceKind,
                origin: ReassignmentOrigin, status: MembershipStatus, source: ThreadID, target: ThreadID,
                decisionRecordID: DecisionRecordID? = nil) {
        self.id = id; self.timestamp = timestamp; self.resourceKind = resourceKind
        self.origin = origin; self.status = status; self.source = source; self.target = target
        outcome = source == target ? .confirmed : .moved
        self.decisionRecordID = decisionRecordID
    }

    public var isValid: Bool {
        timestamp.timeIntervalSinceReferenceDate.isFinite
            && (outcome == .confirmed ? source == target : source != target)
            && (origin != .explicit || decisionRecordID == nil)
    }
}

public protocol ResourceReassignmentArchive: Sendable {
    func append(reassignments: [ResourceReassignmentRecord], at time: Date, retention: DecisionRetentionPolicy) async throws
    func resourceReassignments(since time: Date, limit: Int) async throws -> [ResourceReassignmentRecord]
}
