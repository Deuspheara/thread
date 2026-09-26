import Foundation
import Testing
import ThreadDomain
@testable import ThreadUI

@MainActor
struct ThreadDetailReadingTests {
    @Test func openingArchivedWorkDoesNotRequireItInRecentPublications() async {
        let reading = DetailFixture()
        let model = ThreadDetailModel(editing: reading, reading: reading)
        model.update(ThreadPresentation(threads: [], active: nil))
        model.open(reading.thread.id)
        await model.refresh()
        #expect(model.selected?.thread.isArchived == true)
        #expect(model.title == "Archived outside recent")
        #expect(model.totalResourceCount == 2)
        #expect(model.selected?.resources.count == 1)
        await model.loadMore()
        #expect(model.selected?.resources.count == 2)
        #expect(model.nextResource == nil)
    }

    @Test func aLateDetailReplyCannotReplaceTheNewlySelectedThread() async {
        let reading = DelayedDetailFixture()
        let model = ThreadDetailModel(editing: DetailFixture(), reading: reading)
        let old = ThreadID(rawValue: UUID()), current = ThreadID(rawValue: UUID())
        model.open(old)
        let first = Task { await model.refresh() }
        await reading.wait(old)
        model.open(current)
        let second = Task { await model.refresh() }
        await reading.wait(current)
        await reading.finish(current)
        await second.value
        await reading.finish(old)
        await first.value
        #expect(model.selected?.thread.id == current)
        #expect(!model.loading)
    }
}

private struct DetailFixture: ThreadReading, ThreadEditing {
    let thread = ThreadDomain.Thread(id: ThreadID(rawValue: UUID()), title: "Archived outside recent",
        createdAt: Date(timeIntervalSince1970: 100), lastActiveAt: Date(timeIntervalSince1970: 100), isArchived: true)
    func recentSummaries(limit: Int) async throws -> [ThreadSummary] { [] }
    func destinations(query: String, excluding thread: ThreadID, limit: Int) async throws -> [ThreadDomain.Thread] { [] }
    func edit(_ edit: ThreadEdit) async throws -> HistoryStatus { .saved }
    func detailPage(_ id: ThreadID, after resource: ResourceID?, limit: Int) async throws -> ThreadDetailPage? {
        let edge = ThreadResource(resource: .workingDirectory(resource == nil ? "/first" : "/second"),
            confidence: 0.99, firstSeen: thread.createdAt, lastSeen: thread.lastActiveAt,
            source: ActivitySourceID(rawValue: "fixture"), status: .confirmed)
        return ThreadDetailPage(thread: thread, resources: [edge], totalResourceCount: 2,
            next: resource == nil ? edge.resource.id : nil)
    }
}

private actor DelayedDetailFixture: ThreadReading {
    private var requests: [ThreadID: CheckedContinuation<ThreadDetailPage?, Never>] = [:]
    private var observers: [ThreadID: CheckedContinuation<Void, Never>] = [:]
    func recentSummaries(limit: Int) async throws -> [ThreadSummary] { [] }
    func destinations(query: String, excluding thread: ThreadID, limit: Int) async throws -> [ThreadDomain.Thread] { [] }
    func detailPage(_ thread: ThreadID, after resource: ResourceID?, limit: Int) async throws -> ThreadDetailPage? {
        await withCheckedContinuation { continuation in
            requests[thread] = continuation
            observers.removeValue(forKey: thread)?.resume()
        }
    }
    func wait(_ thread: ThreadID) async {
        if requests[thread] != nil { return }
        await withCheckedContinuation { observers[thread] = $0 }
    }
    func finish(_ id: ThreadID) {
        let thread = ThreadDomain.Thread(id: id, title: "Selected", createdAt: Date(timeIntervalSince1970: 100),
                                        lastActiveAt: Date(timeIntervalSince1970: 100))
        requests.removeValue(forKey: id)?.resume(returning: ThreadDetailPage(thread: thread,
            resources: [], totalResourceCount: 0, next: nil))
    }
}
