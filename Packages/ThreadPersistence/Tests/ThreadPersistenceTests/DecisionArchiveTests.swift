import Foundation
import Testing
import ThreadDomain
import ThreadPersistence

struct DecisionArchiveTests {
    private let now = Date(timeIntervalSince1970: 100)
    private func record(at time: Date, origin: DecisionOrigin = .local) -> DecisionRecord {
        DecisionRecord(id: DecisionRecordID(rawValue: UUID()), timestamp: time, origin: origin,
            elapsedMilliseconds: 12, decision: .membership(MembershipDecision(target: .newThread, confidence: 0.97)))
    }

    @Test func decisionsReopenIdempotentlyAndApplyAgeAndCountRetention() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record("Decision archive fixture cleanup failed") }
        }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let old = record(at: now.addingTimeInterval(-20))
        let first = record(at: now.addingTimeInterval(-2), origin: .remote)
        let second = record(at: now.addingTimeInterval(-1), origin: .localFallback)
        let last = record(at: now)
        let retention = DecisionRetentionPolicy(lifetime: 10, maximumRecords: 2)
        for _ in 0..<2 {
            try await database.append(decisions: [old, first, second, last], at: now, retention: retention)
        }
        let reopened = ThreadDatabase(directory: directory)
        try await reopened.prepare()
        #expect(try await reopened.decisions(since: .distantPast, limit: 100) == [last, second])
        #expect(try await reopened.decisions(since: now, limit: 100) == [last])
        try await reopened.append(decisions: [], at: now.addingTimeInterval(20), retention: retention)
        #expect(try await reopened.decisions(since: .distantPast, limit: 100).isEmpty)
    }

    @Test func invalidRecordPreventsPartialBatchWrite() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record("Decision archive fixture cleanup failed") }
        }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let invalid = DecisionRecord(id: DecisionRecordID(rawValue: UUID()), timestamp: now, origin: .local,
            elapsedMilliseconds: 1, decision: .membership(MembershipDecision(target: .existing(ThreadID(rawValue: UUID())), confidence: 1)))
        await #expect(throws: HistoryStorageError.invalidState) {
            try await database.append(decisions: [record(at: now), invalid], at: now, retention: DecisionRetentionPolicy())
        }
        #expect(try await database.decisions(since: .distantPast, limit: 100).isEmpty)
    }

    @Test func recordedPayloadCannotContainContextOrResourceIdentity() throws {
        let candidate = ThreadID(rawValue: UUID())
        let value = DecisionRecord(id: DecisionRecordID(rawValue: UUID()), timestamp: now, origin: .remote,
            elapsedMilliseconds: 12, decision: .membership(MembershipDecision(target: .existing(candidate), confidence: 0.97)),
            candidates: [candidate])
        let data = try JSONEncoder().encode(value)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["id", "timestamp", "origin", "elapsedMilliseconds", "decision", "candidates"])
        #expect(value.isValid)
        let decoded = try JSONDecoder().decode(DecisionRecord.self, from: data)
        #expect(decoded == value)
    }
}
