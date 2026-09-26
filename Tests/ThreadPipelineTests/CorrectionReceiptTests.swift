import Foundation
import Testing
import ThreadDomain
import ThreadEngine
import ThreadDecisions
import ThreadPersistence

struct CorrectionReceiptTests {
    // Keep the complete inference -> saved edge -> reopened graph -> correction scenario visible in one test.
    @Test(arguments: [DecisionOrigin.local, .remote, .localFallback])
    func correctionReferencesTheExactSelectedInferenceAcrossGraphReload(_ origin: DecisionOrigin) async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let time = Date(timeIntervalSince1970: 100)
        let a = ThreadID(rawValue: UUID()), b = ThreadID(rawValue: UUID())
        let folder = Resource.workingDirectory("/fixture/A"), file = Resource.file(FileIdentity(path: "/fixture/A/file"))
        let graph = ThreadGraphStore()
        try await graph.restore(ThreadGraphState(threads: [
            ThreadDetail(thread: .init(id: a, title: "A", createdAt: time, lastActiveAt: time), resources: [
                ThreadResource(resource: folder, confidence: 0.99, firstSeen: time, lastSeen: time,
                    source: .init(rawValue: "fixture"), status: .confirmed)]),
            ThreadDetail(thread: .init(id: b, title: "B", createdAt: time, lastActiveAt: time), resources: [])
        ], corrections: []))
        let records = DecisionRecordBuffer(archive: database, now: { time }, onFailure: { _ in Issue.record("Recording failed") })
        let decisions = HybridDecisionEngine(local: ReceiptDecisions(target: a, ambiguous: origin != .local),
            remote: ReceiptDecisions(target: a, unavailable: origin == .localFallback),
            onDecision: { await records.record($0) }, onFallback: { _ in })
        let context = ActivityContext(startedAt: time, endedAt: time, resources: [folder, file].map {
            ResourceEvidence(resource: $0, firstSeen: time, lastSeen: time, source: .init(rawValue: "fixture"))
        })
        _ = try await ActivityInference(graph: graph, decisions: decisions).process(context, active: nil)
        await records.flush()
        try await database.saveGraph(graph.checkpoint())
        let receipt = try #require(await graph.detail(a)?.resources.first { $0.resource.id == file.id }?.membershipRecordID)
        let journal = ResourceReassignmentJournal(archive: database, now: { time }, onFailure: { _ in Issue.record("Correction recording failed") })
        let restored = ThreadGraphStore()
        let engine = ActivityEngine(graph: restored, decisions: decisions, repository: database,
            onResourceReassignment: { await journal.record($0) }, now: { time })
        do {
            try await engine.prepareHistory()
            _ = try await engine.edit(.reassign(file.id, from: a, to: b))
            await engine.stop()
            await journal.flush()
            let correction = try #require(try await database.resourceReassignments(since: .distantPast, limit: 100).first)
            let inference = try #require(try await database.decisions(since: .distantPast, limit: 100).first { $0.id == receipt })
            #expect(correction.decisionRecordID == inference.id && inference.origin == origin)
            #expect(inference.decision.kind == .membership)
            #expect(correction.status == (origin == .localFallback ? .provisional : .confirmed))
            #expect(await restored.detail(b)?.resources.first?.membershipRecordID == nil)
        } catch { await engine.stop(); throw error }
    }
}

private struct ReceiptDecisions: DecisionEngine {
    let target: ThreadID
    var ambiguous = false
    var unavailable = false
    func classifyMembership(context: ActivityContext, candidates: [ScoredThreadCandidate]) throws -> MembershipDecision {
        if unavailable { throw RemoteDecisionError.transportUnavailable }
        return MembershipDecision(target: .existing(target), confidence: ambiguous ? 0.8 : 0.99)
    }
    func classifyPersistence(resource: Resource, context: ActivityContext) -> PersistenceDecision {
        PersistenceDecision(disposition: .durable, confidence: 1)
    }
    func detectTransition(context: ActivityContext, active: ThreadID?, membership: MembershipDecision) -> TransitionDecision {
        TransitionDecision(shouldTransition: false, confidence: 1)
    }
}
