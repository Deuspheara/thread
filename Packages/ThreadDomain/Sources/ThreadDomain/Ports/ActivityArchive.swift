import Foundation

/// Stores bounded normalized history and immutable snapshots behind a typed persistence boundary.
public protocol ActivityArchive: Sendable {
    func append(events: [ArchivedActivityEvent], snapshots: [ThreadSnapshot], at time: Date, retention: HistoryRetentionPolicy) async throws
    func snapshots(for thread: ThreadID, limit: Int) async throws -> [ThreadSnapshot]
    func events(since time: Date, limit: Int) async throws -> [ArchivedActivityEvent]
}
