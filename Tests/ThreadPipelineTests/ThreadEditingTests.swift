import Foundation
import Testing
import ThreadDomain
import ThreadEngine
import ThreadDecisions
import ThreadPersistence

struct ThreadEditingTests {
    @Test func editsPersistAndSearchFollowsCorrectionAndArchive() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let first = ThreadID(rawValue: UUID()), second = ThreadID(rawValue: UUID())
        let time = Date(timeIntervalSince1970: 100)
        let resource = Resource.workingDirectory("/work/correctme")
        let edge = ThreadResource(resource: resource, confidence: 0.98, firstSeen: time, lastSeen: time,
                                  source: ActivitySourceID(rawValue: "test"), status: .confirmed)
        let state = ThreadGraphState(threads: [
            ThreadDetail(thread: ThreadDomain.Thread(id: first, title: "First", createdAt: time, lastActiveAt: time), resources: [edge]),
            ThreadDetail(thread: ThreadDomain.Thread(id: second, title: "Second", createdAt: time, lastActiveAt: time), resources: [])
        ], corrections: [])
        try await database.saveGraph(state)
        let engine = ActivityEngine(graph: ThreadGraphStore(), decisions: HeuristicDecisionEngine(), repository: database)
        try await engine.prepareHistory()
        #expect(try await engine.edit(.rename(first, title: "Renamed")) == .saved)
        #expect(try await engine.edit(.reassign(resource.id, from: first, to: second)) == .saved)
        let loaded = try await database.loadGraph()
        #expect(loaded.corrections == [ResourceCorrection(resource: resource.id, thread: second)])
        #expect(loaded.threads.first { $0.thread.id == first }?.resources.isEmpty == true)
        #expect(try await database.search(query: "correctme", includeArchived: false, limit: 10).map(\.id) == [second])
        #expect(try await engine.edit(.archive(second, archived: true)) == .saved)
        #expect(try await database.search(query: "correctme", includeArchived: false, limit: 10).isEmpty)
        #expect(try await database.search(query: "correctme", includeArchived: true, limit: 10).map(\.id) == [second])
        await #expect(throws: ThreadEditError.self) { try await engine.edit(.reassign(resource.id, from: first, to: second)) }
        await engine.stop()
        await #expect(throws: ThreadEditError.self) { try await engine.edit(.rename(first, title: "Stopped")) }
    }
}
