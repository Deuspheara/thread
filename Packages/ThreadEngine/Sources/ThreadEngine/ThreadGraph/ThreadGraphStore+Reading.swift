import Foundation
import ThreadDomain

extension ThreadGraphStore: ThreadReading {
    public func recentSummaries(limit: Int) -> [ThreadSummary] {
        summaryRows(limit: min(max(limit, 0), 20))
    }

    public func destinations(query: String, excluding thread: ThreadID, limit: Int) -> [ThreadDomain.Thread] {
        destinationRows(query: query, excluding: thread, limit: min(max(limit, 0), 20))
    }

    public func detailPage(_ thread: ThreadID, after resource: ResourceID?, limit: Int) throws -> ThreadDetailPage? {
        guard let detail = detail(thread) else { return nil }
        let start: Int
        if let resource {
            guard let index = detail.resources.firstIndex(where: { $0.resource.id == resource }) else { throw ThreadReadError.stalePage }
            start = index + 1
        } else { start = 0 }
        let count = min(max(limit, 1), 64)
        let rows = Array(detail.resources.dropFirst(start).prefix(count))
        let next = start + rows.count < detail.resources.count ? rows.last?.resource.id : nil
        return ThreadDetailPage(thread: detail.thread, resources: rows, totalResourceCount: detail.resources.count, next: next)
    }
}
