import Foundation
import Testing
import ThreadDomain
import ThreadEngine
import ThreadDecisions
import ThreadPersistence

struct TransitionApplicationTests {
    @Test func automaticActivationAndOneShotReviewPersistSeparatelyFromUserSelection() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let journal = TransitionApplicationJournal(archive: database, onFailure: { _ in Issue.record("Unexpected transition recording failure") })
        await journal.prepare()
        let graph = ThreadGraphStore()
        let runtime = ActivityRuntimeTests()
        let decisions = DecisionRecordBuffer(archive: database, onFailure: { _ in Issue.record("Unexpected inference recording failure") })
        let hybrid = HybridDecisionEngine(onDecision: { await decisions.record($0) }, onFallback: { _ in })
        let engine = ActivityEngine(graph: graph, decisions: hybrid, policy: runtime.policy,
            transitionPolicy: TransitionPolicy(dwell: 0.01, cooldown: 0.03),
            onTransitionApplication: { await journal.record($0) })
        do {
            let session = TerminalSessionIdentity(rawValue: UUID())
            await runtime.sendProject("/work/A", sequence: 1, session: session, to: engine)
            let first = try await runtime.waitForOverview(engine.updates()) { $0.active != nil }
            let a = try #require(first.active)
            await runtime.sendProject("/work/B", sequence: 2, session: session, to: engine)
            let second = try await runtime.waitForOverview(engine.updates()) { $0.active != nil && $0.active != a }
            let b = try #require(second.active)
            let token = try await engine.beginRestoration(a)
            try await engine.endRestoration(token)
            await engine.stop()
            await decisions.flush()
            await journal.flush()
            let reopened = ThreadDatabase(directory: directory)
            try await reopened.prepare()
            let records = try await reopened.transitionApplications(since: .distantPast, limit: 100)
            #expect(records.map(\.outcome) == [.switched, .deferred, .activated])
            #expect(records.map(\.phase) == [.review, .context, .context])
            #expect(records.first?.previous == a && records.first?.target == b)
            #expect(records.last?.previous == nil && records.last?.target == a)
            #expect(records.allSatisfy { $0.decisionRecordID != nil })
            #expect(records[0].decisionRecordID == records[1].decisionRecordID)
            #expect(records[0].decisionRecordID != records[2].decisionRecordID)
            let inferences = try await reopened.decisions(since: .distantPast, limit: 100).filter { $0.decision.kind == .transition }
            #expect(Set(records.compactMap(\.decisionRecordID)) == Set(inferences.map(\.id)))
        } catch { await engine.stop(); throw error }
    }

    @Test func invalidBatchIsAtomicAndRetentionAndDuplicateIdsAreBounded() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let now = Date(timeIntervalSince1970: 100), target = ThreadID(rawValue: UUID())
        let records = [-20.0, -2, -1, 0].map { offset in
            TransitionApplicationRecord(id: .init(rawValue: UUID()), timestamp: now.addingTimeInterval(offset),
                phase: .context, outcome: .activated, previous: nil, target: target)
        }
        let invalid = TransitionApplicationRecord(id: .init(rawValue: UUID()), timestamp: now,
            phase: .review, outcome: .switched, previous: target, target: target)
        await #expect(throws: HistoryStorageError.invalidState) {
            try await database.append(transitions: [records[0], invalid], at: now, retention: DecisionRetentionPolicy())
        }
        #expect(try await database.transitionApplications(since: .distantPast, limit: 100).isEmpty)
        let retention = DecisionRetentionPolicy(lifetime: 10, maximumRecords: 2)
        for _ in 0..<2 { try await database.append(transitions: records, at: now, retention: retention) }
        #expect(try await database.transitionApplications(since: .distantPast, limit: 100) == Array(records.suffix(2).reversed()))
        try await database.append(transitions: [], at: now.addingTimeInterval(20), retention: retention)
        #expect(try await database.transitionApplications(since: .distantPast, limit: 100).isEmpty)
    }
}

actor TransitionApplicationsProbe {
    private(set) var records: [TransitionApplicationRecord] = []
    func record(_ value: TransitionApplicationRecord) { records.append(value) }
}
