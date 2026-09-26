import Foundation

/// Presents a bounded history search result without loading the complete resource graph.
public struct ThreadSearchResult: Identifiable, Equatable, Codable, Sendable {
    public let id: ThreadID
    public let title: String
    public let lastActiveAt: Date
    public let resourceCount: Int
    public let isArchived: Bool
    public init(id: ThreadID, title: String, lastActiveAt: Date, resourceCount: Int, isArchived: Bool) {
        self.id = id
        self.title = title
        self.lastActiveAt = lastActiveAt
        self.resourceCount = resourceCount
        self.isArchived = isArchived
    }
}
