import Foundation

/// Bounds quiet-time batching, continuous activity, and retained context evidence.
public struct AggregationPolicy: Sendable {
    public let quietInterval: TimeInterval
    public let maximumBatchInterval: TimeInterval
    public let evidenceLifetime: TimeInterval
    public let maximumResources: Int

    public init(quietInterval: TimeInterval = 2, maximumBatchInterval: TimeInterval = 10,
                evidenceLifetime: TimeInterval = 45, maximumResources: Int = 128) {
        precondition(quietInterval.isFinite && quietInterval > 0)
        precondition(maximumBatchInterval.isFinite && maximumBatchInterval >= quietInterval)
        precondition(evidenceLifetime.isFinite && evidenceLifetime >= maximumBatchInterval)
        precondition(maximumResources > 0)
        self.quietInterval = quietInterval
        self.maximumBatchInterval = maximumBatchInterval
        self.evidenceLifetime = evidenceLifetime
        self.maximumResources = maximumResources
    }
}
