import Foundation
import Testing
import ThreadDomain
import ThreadEngine
import ThreadDecisions
import ThreadPersistence

struct ThreadPinningTests {
    @Test func pinOrderingPersistsAndUnpinRestoresRecencyWithoutSelectingWork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record("Pinning fixture cleanup failed") }
        }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let older = ThreadID(rawValue: UUID()), newer = ThreadID(rawValue: UUID())
        let time = Date(timeIntervalSince1970: 100)
        let old = ThreadDomain.Thread(id: older, title: "Older", createdAt: time, lastActiveAt: time)
        let new = ThreadDomain.Thread(id: newer, title: "Newer", createdAt: time, lastActiveAt: time.addingTimeInterval(10))
        try await database.saveGraph(ThreadGraphState(threads: [ThreadDetail(thread: old, resources: []),
                                                               ThreadDetail(thread: new, resources: [])], corrections: []))
        let graph = ThreadGraphStore()
        let engine = ActivityEngine(graph: graph, decisions: HeuristicDecisionEngine(), repository: database)
        try await engine.prepareHistory()
        #expect(try await engine.edit(.pin(older, pinned: true)) == .saved)
        #expect(await graph.details().map { $0.thread.id } == [older, newer])
        #expect(await graph.detail(older)?.thread.lastActiveAt == time)
        await engine.stop()
        for await overview in engine.updates() { #expect(overview.active == nil) }
        let reopened = ThreadDatabase(directory: directory)
        try await reopened.prepare()
        let restored = ThreadGraphStore()
        try await restored.restore(reopened.loadGraph())
        #expect(await restored.details().first?.thread.isPinned == true)
        try await restored.pin(older, pinned: false)
        #expect(await restored.details().map { $0.thread.id } == [newer, older])
        #expect(await restored.detail(older)?.thread.lastActiveAt == time)
    }

    @Test func legacyPayloadDefaultsUnpinned() throws {
        let time = Date(timeIntervalSince1970: 100)
        let thread = ThreadDomain.Thread(id: ThreadID(rawValue: UUID()), title: "Existing", createdAt: time, lastActiveAt: time)
        let encoded = try JSONEncoder().encode(thread)
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "isPinned")
        let decoded = try JSONDecoder().decode(ThreadDomain.Thread.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(!decoded.isPinned)
        #expect(decoded.id == thread.id)
    }
}
