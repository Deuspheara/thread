import Foundation
import Testing
import ThreadDomain
import ThreadEngine
import ThreadDecisions
import ThreadPersistence

struct ThreadMergeTests {
    @Test func mergePreservesHistoryCorrectionsAndUnrelatedMembershipAfterRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record("Merge fixture cleanup failed") }
        }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let source = ThreadID(rawValue: UUID()), target = ThreadID(rawValue: UUID()), other = ThreadID(rawValue: UUID())
        let time = Date(timeIntervalSince1970: 100)
        let shared = edge(.workingDirectory("/shared"), at: time)
        var corrected = edge(.file(FileIdentity(path: "/source/fix.swift")), at: time)
        corrected.userCorrected = true
        corrected.confidence = 1
        let transient = ThreadResource(resource: .terminal(TerminalContext(session: TerminalSessionIdentity(rawValue: UUID()),
            processIdentifier: 1, workingDirectory: "/source", terminalApplication: nil, sequence: 1)),
            confidence: 0.98, firstSeen: time, lastSeen: time, source: ActivitySourceID(rawValue: "fixture"),
            status: .confirmed, persistence: .sessionOnly)
        let from = ThreadDetail(thread: ThreadDomain.Thread(id: source, title: "Source", createdAt: time, lastActiveAt: time, isPinned: true),
                                resources: [shared, corrected])
        let to = ThreadDetail(thread: ThreadDomain.Thread(id: target, title: "Destination", createdAt: time, lastActiveAt: time.addingTimeInterval(10)),
                              resources: [shared])
        let unrelated = ThreadDetail(thread: ThreadDomain.Thread(id: other, title: "Other", createdAt: time, lastActiveAt: time), resources: [shared])
        try await database.saveGraph(ThreadGraphState(threads: [from, to, unrelated],
                                                      corrections: [ResourceCorrection(resource: corrected.resource.id, thread: source)]))
        let snapshot = try #require(SnapshotBuilder().build(from, at: time))
        try await database.append(events: [], snapshots: [snapshot], at: time, retention: HistoryRetentionPolicy())
        let graph = ThreadGraphStore()
        let engine = ActivityEngine(graph: graph, decisions: HeuristicDecisionEngine(), repository: database, now: { time })
        try await engine.prepareHistory()
        let context = ActivityContext(startedAt: time, endedAt: time, resources: [ResourceEvidence(resource: transient.resource,
            firstSeen: time, lastSeen: time, source: ActivitySourceID(rawValue: "fixture"))])
        _ = try await graph.apply(.automatic(.existing(source)), confidence: 0.98, context: context,
                                 persistence: [transient.resource.id: .sessionOnly])
        let focus = try await engine.beginRestoration(source)
        #expect(try await engine.edit(.merge(source, into: target)) == .saved)
        #expect(await graph.detail(target)?.resources.contains { $0.resource.id == transient.resource.id } == true)
        try await engine.endRestoration(focus)
        await engine.stop()
        for await overview in engine.updates() { #expect(overview.active == target) }
        let reopened = ThreadDatabase(directory: directory)
        try await reopened.prepare()
        let saved = try await reopened.loadGraph()
        let merged = try #require(saved.threads.first { $0.thread.id == target })
        #expect(merged.thread.title == "Destination")
        #expect(merged.thread.isPinned)
        #expect(merged.resources.count == 2)
        #expect(saved.corrections == [ResourceCorrection(resource: corrected.resource.id, thread: target)])
        #expect(saved.threads.first { $0.thread.id == source }?.thread.isArchived == true)
        #expect(saved.threads.first { $0.thread.id == source }?.resources.isEmpty == true)
        #expect(saved.threads.first { $0.thread.id == other }?.resources == [shared])
        #expect(try await reopened.snapshots(for: source, limit: 1).first?.id == snapshot.id)
        #expect(try await reopened.search(query: "fix", includeArchived: false, limit: 10).map(\.id) == [target])
    }

    @Test func invalidMergeLeavesBothThreadsUnchanged() async throws {
        let graph = ThreadGraphStore()
        let source = ThreadID(rawValue: UUID()), target = ThreadID(rawValue: UUID())
        let time = Date(timeIntervalSince1970: 100)
        let state = ThreadGraphState(threads: [ThreadDetail(thread: ThreadDomain.Thread(id: source, title: "Source", createdAt: time,
            lastActiveAt: time), resources: []), ThreadDetail(thread: ThreadDomain.Thread(id: target, title: "Archived", createdAt: time,
            lastActiveAt: time, isArchived: true), resources: [])], corrections: [])
        try await graph.restore(state)
        let before = await graph.checkpoint()
        await #expect(throws: ThreadEditError.self) { try await graph.merge(source, into: target) }
        await #expect(throws: ThreadEditError.self) { try await graph.merge(source, into: source) }
        #expect(await graph.checkpoint() == before)
    }

    private func edge(_ resource: Resource, at time: Date) -> ThreadResource {
        ThreadResource(resource: resource, confidence: 0.98, firstSeen: time, lastSeen: time,
                       source: ActivitySourceID(rawValue: "fixture"), status: .confirmed)
    }
}
