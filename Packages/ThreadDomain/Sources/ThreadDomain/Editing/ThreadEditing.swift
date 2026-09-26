import Foundation

public enum ThreadEdit: Codable, Sendable {
    case split(ThreadID, into: ThreadID, title: String, resources: Set<ResourceID>)
    case merge(ThreadID, into: ThreadID)
    case pin(ThreadID, pinned: Bool)
    case rename(ThreadID, title: String)
    case archive(ThreadID, archived: Bool)
    case reassign(ResourceID, from: ThreadID, to: ThreadID)
}

public enum ThreadEditError: Error, Codable, Sendable {
    case unavailable, busy, resourceDisappeared, invalidDestination, invalidSelection
}

/// Applies explicit corrections and reports whether their local persistence succeeded.
public protocol ThreadEditing: Sendable {
    func edit(_ edit: ThreadEdit) async throws -> HistoryStatus
}
