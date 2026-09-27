import Foundation

/// Reads bounded live graph metadata independently of classification and persistence implementations.
public protocol ThreadReading: Sendable {
    func recentSummaries(limit: Int) async throws -> [ThreadSummary]
    func detailPage(_ thread: ThreadID, after resource: ResourceID?, limit: Int) async throws -> ThreadDetailPage?
    func destinations(query: String, excluding thread: ThreadID, limit: Int) async throws -> [Thread]
}

public enum ThreadReadError: Error, Codable, Sendable { case stalePage, unavailable }

public struct ThreadDetailPage: Codable, Sendable {
    public let thread: Thread
    public let resources: [ThreadResource]
    public let totalResourceCount: Int
    public let next: ResourceID?
    public let resumePlan: ThreadResumePlan?
    public init(thread: Thread, resources: [ThreadResource], totalResourceCount: Int, next: ResourceID?, resumePlan: ThreadResumePlan? = nil) {
        self.thread = thread
        self.resources = resources
        self.totalResourceCount = totalResourceCount
        self.next = next
        self.resumePlan = resumePlan
    }
}
