import Foundation

/// Bounds retained normalized activity and snapshots; raw integration payloads are never archived.
public struct HistoryRetentionPolicy: Sendable {
    public let eventLifetime: TimeInterval
    public let maximumEvents: Int
    public let snapshotsPerThread: Int
    public init(eventLifetime: TimeInterval = 30 * 24 * 60 * 60, maximumEvents: Int = 100_000, snapshotsPerThread: Int = 20) {
        precondition(eventLifetime.isFinite && eventLifetime > 0)
        precondition(maximumEvents > 0 && snapshotsPerThread > 0)
        self.eventLifetime = eventLifetime
        self.maximumEvents = maximumEvents
        self.snapshotsPerThread = snapshotsPerThread
    }
}
