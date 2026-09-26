import Foundation
import Testing
import ThreadDomain
import ThreadEngine
import ThreadDecisions
import ThreadPersistence

struct ThreadSplitTests {
    @Test func splitPersistsExclusiveCorrectionsAndKeepsOriginalHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record("Split fixture cleanup failed") }
        }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let source = ThreadID(rawValue: UUID()), target = ThreadID(rawValue: UUID()), other = ThreadID(rawValue: UUID())
        let time = Date(timeIntervalSince1970: 100)
        let kept = edge(.workingDirectory("/original"), at: time)
        let moved = edge(.file(FileIdentity(path: "/original/separate.swift")), at: time)
        let original = ThreadDetail(thread: ThreadDomain.Thread(id: source, title: "Original", createdAt: time, lastActiveAt: time, isPinned: true),
                                    resources: [kept, moved])
        let related = ThreadDetail(thread: ThreadDomain.Thread(id: other, title: "Related", createdAt: time, lastActiveAt: time), resources: [moved])
        try await database.saveGraph(ThreadGraphState(threads: [original, related], corrections: []))
        let snapshot = try #require(SnapshotBuilder().build(original, at: time))
        try await database.append(events: [], snapshots: [snapshot], at: time, retention: HistoryRetentionPolicy())
        let graph = ThreadGraphStore()
        let engine = ActivityEngine(graph: graph, decisions: HeuristicDecisionEngine(), repository: database, now: { time })
        try await engine.prepareHistory()
        #expect(try await engine.edit(.split(source, into: target, title: "  Separate  ", resources: [moved.resource.id])) == .saved)
        await engine.stop()
        let reopened = ThreadDatabase(directory: directory)
        try await reopened.prepare()
        let saved = try await reopened.loadGraph()
        let split = try #require(saved.threads.first { $0.thread.id == target })
        #expect(split.thread.title == "Separate")
        #expect(!split.thread.isPinned)
        #expect(split.resources.first?.userCorrected == true)
        #expect(split.resources.first?.confidence == 1)
        #expect(saved.corrections == [ResourceCorrection(resource: moved.resource.id, thread: target)])
        #expect(saved.threads.first { $0.thread.id == source }?.resources == [kept])
        #expect(saved.threads.first { $0.thread.id == source }?.thread.isPinned == true)
        #expect(saved.threads.first { $0.thread.id == other }?.resources.isEmpty == true)
        #expect(try await reopened.snapshots(for: source, limit: 1).first?.id == snapshot.id)
        #expect(try await reopened.search(query: "separate", includeArchived: false, limit: 10).map(\.id) == [target])
        let resumed = ThreadGraphStore()
        try await resumed.restore(saved)
        let context = ActivityContext(startedAt: time, endedAt: time, resources: [ResourceEvidence(resource: moved.resource,
            firstSeen: time, lastSeen: time, source: ActivitySourceID(rawValue: "fixture"))])
        _ = try await resumed.apply(.automatic(.existing(source)), confidence: 0.99, context: context)
        #expect(await resumed.detail(source)?.resources == [kept])
    }

    @Test func invalidSelectionAndIdentityCollisionCannotPartiallyMoveResources() async throws {
        let graph = ThreadGraphStore()
        let source = ThreadID(rawValue: UUID()), target = ThreadID(rawValue: UUID())
        let time = Date(timeIntervalSince1970: 100)
        let first = edge(.workingDirectory("/first"), at: time), second = edge(.workingDirectory("/second"), at: time)
        try await graph.restore(ThreadGraphState(threads: [ThreadDetail(thread: ThreadDomain.Thread(id: source, title: "Original",
            createdAt: time, lastActiveAt: time), resources: [first, second])], corrections: []))
        let before = await graph.checkpoint()
        for selection: Set<ResourceID> in [[], [first.resource.id, second.resource.id], [.file(FileIdentity(path: "/missing"))]] {
            await #expect(throws: ThreadEditError.self) {
                try await graph.split(source, into: target, title: "Separate", resources: selection, at: time)
            }
            #expect(await graph.checkpoint() == before)
        }
        await #expect(throws: ThreadGraphError.self) {
            try await graph.split(source, into: source, title: "Collision", resources: [first.resource.id], at: time)
        }
        #expect(await graph.checkpoint() == before)
    }

    private func edge(_ resource: Resource, at time: Date) -> ThreadResource {
        ThreadResource(resource: resource, confidence: 0.98, firstSeen: time, lastSeen: time,
                       source: ActivitySourceID(rawValue: "fixture"), status: .confirmed)
    }
}
