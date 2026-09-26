import Foundation
import GRDB
import ThreadDomain

extension ThreadDatabase: ResourceReassignmentArchive {
    public func append(reassignments: [ResourceReassignmentRecord], at time: Date, retention: DecisionRetentionPolicy) throws {
        guard time.timeIntervalSinceReferenceDate.isFinite, reassignments.count <= 256,
              reassignments.allSatisfy(\.isValid) else { throw HistoryStorageError.invalidState }
        let connection = try preparedConnection()
        do {
            try connection.write { database in
                for record in reassignments {
                    try database.execute(sql: """
                        INSERT INTO resource_reassignments(id, timestamp, resource_kind, origin, status, outcome, source_thread_id, target_thread_id, decision_record_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO NOTHING
                        """, arguments: [record.id.rawValue.uuidString, record.timestamp.timeIntervalSince1970,
                            record.resourceKind.rawValue, record.origin.rawValue, record.status.rawValue, record.outcome.rawValue,
                            record.source.rawValue.uuidString, record.target.rawValue.uuidString, record.decisionRecordID?.rawValue.uuidString])
                }
                try database.execute(sql: "DELETE FROM resource_reassignments WHERE timestamp < ?",
                    arguments: [time.addingTimeInterval(-retention.lifetime).timeIntervalSince1970])
                try database.execute(sql: """
                    DELETE FROM resource_reassignments WHERE id IN (
                        SELECT id FROM resource_reassignments ORDER BY timestamp DESC, id DESC LIMIT -1 OFFSET ?
                    )
                    """, arguments: [retention.maximumRecords])
            }
        } catch { throw HistoryStorageError.writeFailed }
    }

    public func resourceReassignments(since time: Date, limit: Int) throws -> [ResourceReassignmentRecord] {
        guard time.timeIntervalSinceReferenceDate.isFinite else { throw HistoryStorageError.invalidState }
        let connection = try preparedConnection()
        do {
            return try connection.read { database in
                try Row.fetchAll(database, sql: """
                    SELECT id, timestamp, resource_kind, origin, status, outcome, source_thread_id, target_thread_id, decision_record_id FROM resource_reassignments
                    WHERE timestamp >= ? ORDER BY timestamp DESC, id DESC LIMIT ?
                    """, arguments: [time.timeIntervalSince1970, min(max(limit, 0), 1000)]).map(Self.reassignmentRecord)
            }
        } catch { throw HistoryStorageError.readFailed }
    }

    private static func reassignmentRecord(_ row: Row) throws -> ResourceReassignmentRecord {
        guard let id = UUID(uuidString: row["id"]), let kind = ResourceKind(rawValue: row["resource_kind"]),
              let origin = ReassignmentOrigin(rawValue: row["origin"]), let status = MembershipStatus(rawValue: row["status"]),
              let outcome = ReassignmentOutcome(rawValue: row["outcome"]),
              let source = UUID(uuidString: row["source_thread_id"]),
              let target = UUID(uuidString: row["target_thread_id"]) else { throw HistoryStorageError.invalidState }
        let rawDecision: String? = row["decision_record_id"]
        let decision = rawDecision.flatMap(UUID.init(uuidString:)).map(DecisionRecordID.init(rawValue:))
        guard rawDecision == nil || decision != nil else { throw HistoryStorageError.invalidState }
        let record = ResourceReassignmentRecord(id: .init(rawValue: id), timestamp: Date(timeIntervalSince1970: row["timestamp"]),
            resourceKind: kind, origin: origin, status: status, source: .init(rawValue: source), target: .init(rawValue: target),
            decisionRecordID: decision)
        guard record.isValid, record.outcome == outcome else { throw HistoryStorageError.invalidState }
        return record
    }
}
