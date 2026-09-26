import Foundation
import Testing
import ThreadDomain
import ThreadEngine
import ThreadDecisions
import ThreadPersistence

struct ResourceRetentionPipelineTests {
    @Test func offlineHeuristicsKeepTerminalLiveAndPersistDirectoryForLaterRestoration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record("Retention pipeline cleanup failed") }
        }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let now = Date(timeIntervalSince1970: 100)
        let terminal = Resource.terminal(TerminalContext(session: TerminalSessionIdentity(rawValue: UUID()),
            processIdentifier: 1, workingDirectory: "/work", terminalApplication: nil, sequence: 1))
        let cwd = Resource.workingDirectory("/work")
        let file = Resource.file(FileIdentity(path: "/work/Project.swift"))
        let context = ActivityContext(startedAt: now, endedAt: now, resources: [terminal, cwd, file].map {
            ResourceEvidence(resource: $0, firstSeen: now, lastSeen: now, source: ActivitySourceID(rawValue: "test"))
        })
        let graph = ThreadGraphStore()
        let inference = ActivityInference(graph: graph, decisions: HybridDecisionEngine(onFallback: { _ in
            Issue.record("Offline inference should not report remote failure")
        }))
        let outcome = try await inference.process(context, active: nil)
        let id = try #require(outcome.thread)
        let live = try #require(await graph.detail(id))
        #expect(live.resources.first { $0.resource.id == terminal.id }?.persistence == .sessionOnly)
        try await database.saveGraph(await graph.checkpoint())
        let reopened = ThreadDatabase(directory: directory)
        try await reopened.prepare()
        let saved = try await reopened.loadGraph()
        #expect(Set(saved.threads[0].resources.map { $0.resource.id }) == [cwd.id, file.id])
        let snapshot = try #require(SnapshotBuilder().build(live, at: now))
        try await database.append(events: [], snapshots: [snapshot], at: now, retention: HistoryRetentionPolicy())
        #expect(try await reopened.snapshots(for: id, limit: 1).first?.resources.contains { $0.resource.id == terminal.id } == false)
    }
}
