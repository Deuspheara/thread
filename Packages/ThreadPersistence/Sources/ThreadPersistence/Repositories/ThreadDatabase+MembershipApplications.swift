import Foundation
import GRDB
import ThreadDomain

extension ThreadDatabase: MembershipApplicationArchive {
    public func append(applications: [MembershipApplicationRecord], at time: Date, retention: DecisionRetentionPolicy) throws {
        guard time.timeIntervalSinceReferenceDate.isFinite, applications.count <= 256,
              applications.allSatisfy(\.isValid) else { throw HistoryStorageError.invalidState }
        let connection = try preparedConnection()
        do {
            try connection.write { database in
                for record in applications {
                    try database.execute(sql: """
                        INSERT INTO membership_applications(id, timestamp, outcome, thread_id, decision_record_id) VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO NOTHING
                        """, arguments: [record.id.rawValue.uuidString, record.timestamp.timeIntervalSince1970,
                            record.outcome.rawValue, record.thread?.rawValue.uuidString, record.decisionRecordID?.rawValue.uuidString])
                }
                try database.execute(sql: "DELETE FROM membership_applications WHERE timestamp < ?",
                    arguments: [time.addingTimeInterval(-retention.lifetime).timeIntervalSince1970])
                try database.execute(sql: """
                    DELETE FROM membership_applications WHERE id IN (
                        SELECT id FROM membership_applications ORDER BY timestamp DESC, id DESC LIMIT -1 OFFSET ?
                    )
                    """, arguments: [retention.maximumRecords])
            }
        } catch { throw HistoryStorageError.writeFailed }
    }

    public func membershipApplications(since time: Date, limit: Int) throws -> [MembershipApplicationRecord] {
        guard time.timeIntervalSinceReferenceDate.isFinite else { throw HistoryStorageError.invalidState }
        let connection = try preparedConnection()
        do {
            return try connection.read { database in
                try Row.fetchAll(database, sql: """
                    SELECT id, timestamp, outcome, thread_id, decision_record_id FROM membership_applications
                    WHERE timestamp >= ? ORDER BY timestamp DESC, id DESC LIMIT ?
                    """, arguments: [time.timeIntervalSince1970, min(max(limit, 0), 1000)]).map(Self.applicationRecord)
            }
        } catch { throw HistoryStorageError.readFailed }
    }

    private static func applicationRecord(_ row: Row) throws -> MembershipApplicationRecord {
        guard let id = UUID(uuidString: row["id"]), let outcome = MembershipApplicationOutcome(rawValue: row["outcome"]) else {
            throw HistoryStorageError.invalidState
        }
        let rawThread: String? = row["thread_id"]
        let thread = rawThread.flatMap(UUID.init(uuidString:)).map(ThreadID.init(rawValue:))
        guard rawThread == nil || thread != nil else { throw HistoryStorageError.invalidState }
        let rawDecision: String? = row["decision_record_id"]
        let decision = rawDecision.flatMap(UUID.init(uuidString:)).map(DecisionRecordID.init(rawValue:))
        guard rawDecision == nil || decision != nil else { throw HistoryStorageError.invalidState }
        let record = MembershipApplicationRecord(id: MembershipApplicationID(rawValue: id),
            timestamp: Date(timeIntervalSince1970: row["timestamp"]), outcome: outcome, thread: thread, decisionRecordID: decision)
        guard record.isValid else { throw HistoryStorageError.invalidState }
        return record
    }
}
