/// Searches durable local metadata; no embeddings or remote service are required.
public protocol ThreadSearch: Sendable {
    func search(query: String, includeArchived: Bool, limit: Int) async throws -> [ThreadSearchResult]
}
