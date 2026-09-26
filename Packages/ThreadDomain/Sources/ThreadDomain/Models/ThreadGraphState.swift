import Foundation

public struct ResourceCorrection: Equatable, Codable, Sendable {
    public let resource: ResourceID
    public let thread: ThreadID
    public init(resource: ResourceID, thread: ThreadID) { self.resource = resource; self.thread = thread }
}

/// Captures durable graph relationships and correction overrides together for atomic persistence.
public struct ThreadGraphState: Equatable, Codable, Sendable {
    public let threads: [ThreadDetail]
    public let corrections: [ResourceCorrection]
    public init(threads: [ThreadDetail], corrections: [ResourceCorrection]) {
        self.threads = threads
        self.corrections = corrections
    }
}
