import Foundation
import Testing
import ThreadDomain
import ThreadEngine
import ThreadPersistence
import ThreadDecisions

struct ResourceReassignmentTests {
    @Test func editsCapturePriorEdgeBeforeMutationAndOnlySuccessfulReassignmentsAreRecorded() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let time = Date(timeIntervalSince1970: 100)
        let a = ThreadID(rawValue: UUID()), b = ThreadID(rawValue: UUID())
        let resource = Resource.workingDirectory("/fixture/private-path")
        let receipt = DecisionRecordID(rawValue: UUID())
        let edge = ThreadResource(resource: resource, confidence: 0.8, firstSeen: time, lastSeen: time,
            source: ActivitySourceID(rawValue: "fixture"), status: .provisional, membershipRecordID: receipt)
        try await database.saveGraph(ThreadGraphState(threads: [
            ThreadDetail(thread: .init(id: a, title: "A", createdAt: time, lastActiveAt: time), resources: [edge]),
            ThreadDetail(thread: .init(id: b, title: "B", createdAt: time, lastActiveAt: time), resources: [])
        ], corrections: []))
        let journal = ResourceReassignmentJournal(archive: database, now: { time }, onFailure: { _ in Issue.record("Unexpected reassignment recording failure") })
        let engine = ActivityEngine(graph: ThreadGraphStore(), decisions: HeuristicDecisionEngine(), repository: database,
            onResourceReassignment: { await journal.record($0) }, now: { time })
        do {
            try await engine.prepareHistory()
            _ = try await engine.edit(.reassign(resource.id, from: a, to: b))
            _ = try await engine.edit(.reassign(resource.id, from: b, to: b))
            _ = try await engine.edit(.reassign(resource.id, from: b, to: a))
            _ = try await engine.edit(.rename(a, title: "Renamed"))
            await #expect(throws: ThreadEditError.resourceDisappeared) {
                try await engine.edit(.reassign(resource.id, from: b, to: a))
            }
            await engine.stop()
            await journal.flush()
            let reopened = ThreadDatabase(directory: directory)
            try await reopened.prepare()
            let records = try await reopened.resourceReassignments(since: .distantPast, limit: 100)
            #expect(records.count == 3 && Set(records.map(\.id)).count == 3)
            #expect(records.allSatisfy { $0.timestamp == time && $0.resourceKind == .workingDirectory })
            let inferred = try #require(records.first { $0.origin == .inferred })
            #expect(inferred.source == a && inferred.target == b && inferred.status == .provisional && inferred.outcome == .moved)
            #expect(inferred.decisionRecordID == receipt)
            #expect(records.filter { $0.origin == .explicit }.allSatisfy { $0.decisionRecordID == nil })
            #expect(records.filter { $0.origin == .explicit && $0.outcome == .confirmed }.count == 1)
            #expect(records.filter { $0.origin == .explicit && $0.outcome == .moved && $0.status == .confirmed }.count == 1)
            #expect(try await reopened.loadGraph().corrections == [ResourceCorrection(resource: resource.id, thread: a)])
        } catch { await engine.stop(); throw error }
    }

    @Test func archiveRejectsInvalidBatchAndAppliesIdempotentCountAndAgeRetention() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let now = Date(timeIntervalSince1970: 100), a = ThreadID(rawValue: UUID()), b = ThreadID(rawValue: UUID())
        func record(at time: Date) -> ResourceReassignmentRecord {
            .init(id: .init(rawValue: UUID()), timestamp: time, resourceKind: .file,
                origin: .inferred, status: .confirmed, source: a, target: b)
        }
        let records = [-20.0, -2, -1, 0].map { record(at: now.addingTimeInterval($0)) }
        let invalidManual = ResourceReassignmentRecord(id: .init(rawValue: UUID()), timestamp: now, resourceKind: .file,
            origin: .explicit, status: .confirmed, source: a, target: b, decisionRecordID: .init(rawValue: UUID()))
        for invalid in [record(at: Date(timeIntervalSince1970: .nan)), invalidManual] {
            await #expect(throws: HistoryStorageError.invalidState) {
                try await database.append(reassignments: [records[0], invalid], at: now, retention: DecisionRetentionPolicy())
            }
        }
        #expect(try await database.resourceReassignments(since: .distantPast, limit: 100).isEmpty)
        let retention = DecisionRetentionPolicy(lifetime: 10, maximumRecords: 2)
        for _ in 0..<2 { try await database.append(reassignments: records, at: now, retention: retention) }
        #expect(try await database.resourceReassignments(since: .distantPast, limit: 100) == Array(records.suffix(2).reversed()))
        try await database.append(reassignments: [], at: now.addingTimeInterval(20), retention: retention)
        #expect(try await database.resourceReassignments(since: .distantPast, limit: 100).isEmpty)
    }
}
