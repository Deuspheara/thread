import Foundation
import GRDB
import ThreadDomain

extension ThreadDatabase: TransitionApplicationArchive {
    public func append(transitions: [TransitionApplicationRecord], at time: Date, retention: DecisionRetentionPolicy) throws {
        guard time.timeIntervalSinceReferenceDate.isFinite, transitions.count <= 256,
              transitions.allSatisfy(\.isValid) else { throw HistoryStorageError.invalidState }
        let connection = try preparedConnection()
        do {
            try connection.write { database in
                for record in transitions {
                    try database.execute(sql: """
                        INSERT INTO transition_applications(id, timestamp, phase, outcome, previous_thread_id, target_thread_id, decision_record_id) VALUES (?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO NOTHING
                        """, arguments: [record.id.rawValue.uuidString, record.timestamp.timeIntervalSince1970,
                            record.phase.rawValue, record.outcome.rawValue, record.previous?.rawValue.uuidString, record.target.rawValue.uuidString,
                            record.decisionRecordID?.rawValue.uuidString])
                }
                try database.execute(sql: "DELETE FROM transition_applications WHERE timestamp < ?",
                    arguments: [time.addingTimeInterval(-retention.lifetime).timeIntervalSince1970])
                try database.execute(sql: """
                    DELETE FROM transition_applications WHERE id IN (
                        SELECT id FROM transition_applications ORDER BY timestamp DESC, id DESC LIMIT -1 OFFSET ?
                    )
                    """, arguments: [retention.maximumRecords])
            }
        } catch { throw HistoryStorageError.writeFailed }
    }

    public func transitionApplications(since time: Date, limit: Int) throws -> [TransitionApplicationRecord] {
        guard time.timeIntervalSinceReferenceDate.isFinite else { throw HistoryStorageError.invalidState }
        let connection = try preparedConnection()
        do {
            return try connection.read { database in
                try Row.fetchAll(database, sql: """
                    SELECT id, timestamp, phase, outcome, previous_thread_id, target_thread_id, decision_record_id FROM transition_applications
                    WHERE timestamp >= ? ORDER BY timestamp DESC, id DESC LIMIT ?
                    """, arguments: [time.timeIntervalSince1970, min(max(limit, 0), 1000)]).map(Self.transitionRecord)
            }
        } catch { throw HistoryStorageError.readFailed }
    }

    private static func transitionRecord(_ row: Row) throws -> TransitionApplicationRecord {
        guard let id = UUID(uuidString: row["id"]), let outcome = TransitionApplicationOutcome(rawValue: row["outcome"]) else {
            throw HistoryStorageError.invalidState
        }
        guard let phase = TransitionApplicationPhase(rawValue: row["phase"]),
              let target = UUID(uuidString: row["target_thread_id"]) else { throw HistoryStorageError.invalidState }
        let rawPrevious: String? = row["previous_thread_id"]
        let previous = rawPrevious.flatMap(UUID.init(uuidString:)).map(ThreadID.init(rawValue:))
        guard rawPrevious == nil || previous != nil else { throw HistoryStorageError.invalidState }
        let rawDecision: String? = row["decision_record_id"]
        let decision = rawDecision.flatMap(UUID.init(uuidString:)).map(DecisionRecordID.init(rawValue:))
        guard rawDecision == nil || decision != nil else { throw HistoryStorageError.invalidState }
        let record = TransitionApplicationRecord(id: TransitionApplicationID(rawValue: id),
            timestamp: Date(timeIntervalSince1970: row["timestamp"]), phase: phase, outcome: outcome,
            previous: previous, target: ThreadID(rawValue: target), decisionRecordID: decision)
        guard record.isValid else { throw HistoryStorageError.invalidState }
        return record
    }
}
