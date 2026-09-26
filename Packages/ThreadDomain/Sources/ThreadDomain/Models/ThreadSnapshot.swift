import Foundation

public struct ThreadSnapshotID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// Freezes confirmed per-Thread metadata for later capability-based restoration.
public struct ThreadSnapshot: Equatable, Codable, Sendable {
    public let id: ThreadSnapshotID
    public let thread: ThreadID
    public let capturedAt: Date
    public let title: String
    public let resources: [ThreadResource]
    public init(id: ThreadSnapshotID, thread: ThreadID, capturedAt: Date, title: String, resources: [ThreadResource]) {
        self.id = id
        self.thread = thread
        self.capturedAt = capturedAt
        self.title = title
        self.resources = resources
    }
}

/// Attaches a normalized event to a Thread only when that attribution is known.
public struct ArchivedActivityEvent: Equatable, Codable, Sendable {
    public let event: ActivityEvent
    public let thread: ThreadID?
    public init(event: ActivityEvent, thread: ThreadID? = nil) { self.event = event; self.thread = thread }
}
