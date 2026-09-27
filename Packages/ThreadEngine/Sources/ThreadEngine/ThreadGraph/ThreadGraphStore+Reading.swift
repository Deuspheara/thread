import Foundation
import ThreadDomain

extension ThreadGraphStore: ThreadReading {
    func summaryRows(limit: Int) -> [ThreadSummary] {
        orderedThreads().filter { !$0.isArchived }.prefix(limit).map { thread in
            let edges = relationships[thread.id, default: [:]].values.filter { $0.status == .confirmed }
            let names = Set(edges.compactMap { edge -> String? in
                guard case .application(let app) = edge.resource else { return nil }
                return app.name
            }).sorted().prefix(3)
            return ThreadSummary(thread: thread, resourceCount: edges.count, applications: Array(names),
                                 work: ThreadWorkSummary(makeDetail(thread)))
        }
    }


    public func recentSummaries(limit: Int) -> [ThreadSummary] {
        summaryRows(limit: min(max(limit, 0), 20))
    }

    public func destinations(query: String, excluding thread: ThreadID, limit: Int) -> [ThreadDomain.Thread] {
        destinationRows(query: query, excluding: thread, limit: min(max(limit, 0), 20))
    }

    /// Supplies the same alias-aware bounded targets used by restoration and launcher previews.
    public func resumePlan(_ thread: ThreadID) throws -> ThreadResumePlan? {
        guard let detail = detail(thread) else { return nil }
        guard detail.resources.count <= 512 else { throw ThreadReadError.unavailable }
        return ThreadResumePlan(detail, directoryIdentity: resumeDirectoryIdentity)
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
        return ThreadDetailPage(thread: detail.thread, resources: rows, totalResourceCount: detail.resources.count, next: next,
            resumePlan: detail.resources.count <= 512 ? try resumePlan(thread) : nil)
    }
}
