import Foundation

/// Describes inferred work independently of its graph relationships and live applications.
public struct Thread: Equatable, Codable, Sendable {
    public let id: ThreadID
    public var title: String
    public let createdAt: Date
    public var lastActiveAt: Date
    public var isPinned: Bool
    public var isArchived: Bool

    public init(id: ThreadID, title: String, createdAt: Date, lastActiveAt: Date, isArchived: Bool = false, isPinned: Bool = false) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.isArchived = isArchived
        self.isPinned = isPinned
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, lastActiveAt, isArchived, isPinned
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(ThreadID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        lastActiveAt = try values.decode(Date.self, forKey: .lastActiveAt)
        isArchived = try values.decode(Bool.self, forKey: .isArchived)
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}

public enum MembershipStatus: String, Codable, Sendable { case provisional, confirmed }

/// Preserves per-Thread resource metadata so a reused terminal cannot rewrite another Thread's cwd.
public struct ThreadResource: Equatable, Codable, Sendable {
    public var resource: Resource
    public var confidence: Double
    public let firstSeen: Date
    public var lastSeen: Date
    public var source: ActivitySourceID
    public var status: MembershipStatus
    public var pinned: Bool
    public var userCorrected: Bool
    public var persistence: PersistenceDisposition
    /// The latest accepted inferred membership record; absent after explicit reassignment.
    public var membershipRecordID: DecisionRecordID?
    public var restoreApplication: RestoreApplication?

    public init(resource: Resource, confidence: Double, firstSeen: Date, lastSeen: Date, source: ActivitySourceID,
                status: MembershipStatus, pinned: Bool = false, userCorrected: Bool = false,
                persistence: PersistenceDisposition = .durable, membershipRecordID: DecisionRecordID? = nil, restoreApplication: RestoreApplication? = nil) {
        self.resource = resource
        self.confidence = confidence
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.source = source
        self.status = status
        self.pinned = pinned
        self.userCorrected = userCorrected
        self.persistence = persistence
        self.membershipRecordID = membershipRecordID
        self.restoreApplication = restoreApplication
    }

    private enum CodingKeys: String, CodingKey {
        case resource, confidence, firstSeen, lastSeen, source, status, pinned, userCorrected, persistence, membershipRecordID, restoreApplication
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        resource = try values.decode(Resource.self, forKey: .resource)
        confidence = try values.decode(Double.self, forKey: .confidence)
        firstSeen = try values.decode(Date.self, forKey: .firstSeen)
        lastSeen = try values.decode(Date.self, forKey: .lastSeen)
        source = try values.decode(ActivitySourceID.self, forKey: .source)
        status = try values.decode(MembershipStatus.self, forKey: .status)
        pinned = try values.decode(Bool.self, forKey: .pinned)
        userCorrected = try values.decode(Bool.self, forKey: .userCorrected)
        persistence = try values.decodeIfPresent(PersistenceDisposition.self, forKey: .persistence) ?? .durable
        membershipRecordID = try values.decodeIfPresent(DecisionRecordID.self, forKey: .membershipRecordID)
        restoreApplication = try values.decodeIfPresent(RestoreApplication.self, forKey: .restoreApplication)
    }

}

/// Publishes one graph node with its explicit relationships to application-facing consumers.
public struct ThreadDetail: Equatable, Codable, Sendable {
    public let thread: Thread
    public let resources: [ThreadResource]
    public init(thread: Thread, resources: [ThreadResource]) { self.thread = thread; self.resources = resources }
}
