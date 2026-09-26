import Foundation
import Testing
import ThreadDomain
@testable import ThreadUI

@MainActor
struct SwitcherModelTests {
    @Test func returningToRecentWorkRejectsAnAlreadyRunningSearchResult() async throws {
        let search = DelayedSearch()
        let model = SwitcherModel(search: search)
        model.query = "old"
        let pending = Task { await model.refresh() }
        await search.waitUntilRequested()
        model.reset()
        let id = ThreadID(rawValue: UUID())
        await search.finish([ThreadSearchResult(id: id, title: "Stale", lastActiveAt: Date(), resourceCount: 1, isArchived: false)])
        await pending.value
        #expect(model.query.isEmpty)
        #expect(model.rows.isEmpty)
        #expect(model.selection == nil)
        #expect(!model.loading)
    }

    @Test func archivedSearchIsExplicitAndResetReturnsToRecentWork() async {
        let search = DelayedSearch()
        let model = SwitcherModel(search: search)
        model.query = "archived"
        model.includeArchived = true
        let pending = Task { await model.refresh() }
        await search.waitUntilRequested()
        #expect(await search.includesArchived())
        let id = ThreadID(rawValue: UUID())
        await search.finish([ThreadSearchResult(id: id, title: "Archived", lastActiveAt: Date(),
                                               resourceCount: 1, isArchived: true)])
        await pending.value
        #expect(model.rows.first?.isArchived == true)
        #expect(model.selection == id)
        model.reset()
        #expect(!model.includeArchived)
        #expect(model.rows.isEmpty)
    }

    @Test func pinReorderingPreservesKeyboardSelection() {
        let model = SwitcherModel(search: DelayedSearch())
        let time = Date(timeIntervalSince1970: 100)
        let first = ThreadDomain.Thread(id: ThreadID(rawValue: UUID()), title: "First", createdAt: time, lastActiveAt: time)
        var second = ThreadDomain.Thread(id: ThreadID(rawValue: UUID()), title: "Second", createdAt: time, lastActiveAt: time)
        model.update(ThreadPresentation(threads: [ThreadSummary(thread: first, resourceCount: 0, applications: []), ThreadSummary(thread: second, resourceCount: 0, applications: [])],
                                    active: nil, failure: nil, history: .saved))
        #expect(model.selection == first.id)
        second.isPinned = true
        model.update(ThreadPresentation(threads: [ThreadSummary(thread: second, resourceCount: 0, applications: []), ThreadSummary(thread: first, resourceCount: 0, applications: [])],
                                    active: nil, failure: nil, history: .saved))
        #expect(model.rows.first?.id == second.id)
        #expect(model.selection == first.id)
    }

    @Test func archivedOrRemovedSelectionFallsBackToAvailableRecentWork() {
        let model = SwitcherModel(search: DelayedSearch())
        let first = ThreadID(rawValue: UUID()), second = ThreadID(rawValue: UUID())
        let time = Date(timeIntervalSince1970: 100)
        let a = ThreadSummary(thread: ThreadDomain.Thread(id: first, title: "A", createdAt: time, lastActiveAt: time), resourceCount: 0, applications: [])
        let b = ThreadSummary(thread: ThreadDomain.Thread(id: second, title: "B", createdAt: time, lastActiveAt: time), resourceCount: 0, applications: [])
        model.update(ThreadPresentation(threads: [a, b], active: first, failure: nil, history: .saved))
        model.move(1)
        #expect(model.selection == second)
        model.update(ThreadPresentation(threads: [a], active: first, failure: nil, history: .saved))
        #expect(model.selection == first)
        model.move(-1)
        #expect(model.selection == first)
    }
}

private actor DelayedSearch: ThreadSearch {
    private var archived = false
    func includesArchived() -> Bool { archived }
    private var request: CheckedContinuation<[ThreadSearchResult], Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func waitUntilRequested() async {
        if request != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func search(query: String, includeArchived: Bool, limit: Int) async throws -> [ThreadSearchResult] {
        archived = includeArchived
        return await withCheckedContinuation { request in
            self.request = request
            observer?.resume()
            observer = nil
        }
    }
    func finish(_ results: [ThreadSearchResult]) {
        request?.resume(returning: results)
        request = nil
    }
}
