import Foundation
import GRDB
import ThreadDomain

extension ThreadDatabase: DecisionArchive {
    public func append(decisions: [DecisionRecord], at time: Date, retention: DecisionRetentionPolicy) throws {
        guard time.timeIntervalSinceReferenceDate.isFinite, decisions.count <= 256,
              decisions.allSatisfy(\.isValid) else { throw HistoryStorageError.invalidState }
        let connection = try preparedConnection()
        do {
            try connection.write { database in
                for record in decisions { try Self.insert(record, in: database) }
                try database.execute(sql: "DELETE FROM decision_records WHERE timestamp < ?",
                    arguments: [time.addingTimeInterval(-retention.lifetime).timeIntervalSince1970])
                try database.execute(sql: """
                    DELETE FROM decision_records WHERE id IN (
                        SELECT id FROM decision_records ORDER BY timestamp DESC, id DESC LIMIT -1 OFFSET ?
                    )
                    """, arguments: [retention.maximumRecords])
            }
        } catch { throw HistoryStorageError.writeFailed }
    }

    public func decisions(since time: Date, limit: Int) throws -> [DecisionRecord] {
        guard time.timeIntervalSinceReferenceDate.isFinite else { throw HistoryStorageError.invalidState }
        let connection = try preparedConnection()
        do {
            return try connection.read { database in
                try Data.fetchAll(database, sql: "SELECT payload FROM decision_records WHERE timestamp >= ? ORDER BY timestamp DESC, id DESC LIMIT ?",
                    arguments: [time.timeIntervalSince1970, min(max(limit, 0), 1000)]).map {
                        let record = try GraphRecordCodec.decode(DecisionRecord.self, $0)
                        guard record.isValid else { throw HistoryStorageError.invalidState }
                        return record
                    }
            }
        } catch { throw HistoryStorageError.readFailed }
    }

    private static func insert(_ record: DecisionRecord, in database: Database) throws {
        try database.execute(sql: """
            INSERT INTO decision_records(id, timestamp, origin, kind, confidence, elapsed_milliseconds, payload)
            VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO NOTHING
            """, arguments: [record.id.rawValue.uuidString, record.timestamp.timeIntervalSince1970,
                record.origin.rawValue, record.decision.kind.rawValue, record.decision.confidence,
                record.elapsedMilliseconds, try GraphRecordCodec.encode(record)])
    }
}
