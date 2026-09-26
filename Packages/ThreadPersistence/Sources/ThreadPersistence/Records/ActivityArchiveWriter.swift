import Foundation
import GRDB
import ThreadDomain

/// Appends idempotent history batches and applies age/count retention in the same transaction.
enum ActivityArchiveWriter {
    static func append(events: [ArchivedActivityEvent], snapshots: [ThreadSnapshot], at time: Date,
                       retention: HistoryRetentionPolicy, in database: Database) throws {
        for entry in events {
            try database.execute(sql: "INSERT INTO events(id, timestamp, thread_id, payload) VALUES (?, ?, ?, ?) ON CONFLICT(id) DO NOTHING",
                arguments: [entry.event.id.rawValue.uuidString, entry.event.timestamp.timeIntervalSince1970,
                            entry.thread?.rawValue.uuidString, try GraphRecordCodec.encode(entry.event)])
        }
        for snapshot in snapshots {
            try database.execute(sql: "INSERT INTO snapshots(id, thread_id, captured_at, payload) VALUES (?, ?, ?, ?) ON CONFLICT(id) DO NOTHING",
                arguments: [snapshot.id.rawValue.uuidString, snapshot.thread.rawValue.uuidString,
                            snapshot.capturedAt.timeIntervalSince1970, try GraphRecordCodec.encode(snapshot)])
        }
        try database.execute(sql: "DELETE FROM events WHERE timestamp < ?", arguments: [time.addingTimeInterval(-retention.eventLifetime).timeIntervalSince1970])
        try database.execute(sql: """
            DELETE FROM events WHERE id IN (
                SELECT id FROM events ORDER BY timestamp DESC, id DESC LIMIT -1 OFFSET ?
            )
            """, arguments: [retention.maximumEvents])
        try database.execute(sql: """
            DELETE FROM snapshots WHERE id IN (
                SELECT id FROM (
                    SELECT id, ROW_NUMBER() OVER (PARTITION BY thread_id ORDER BY captured_at DESC, id DESC) AS rank
                    FROM snapshots
                ) WHERE rank > ?
            )
            """, arguments: [retention.snapshotsPerThread])
    }

    static func validate(events: [ArchivedActivityEvent], snapshots: [ThreadSnapshot], time: Date) throws {
        guard time.timeIntervalSinceReferenceDate.isFinite, events.count <= 512, snapshots.count <= 64,
              events.allSatisfy({ $0.event.timestamp.timeIntervalSinceReferenceDate.isFinite }) else { throw HistoryStorageError.invalidState }
        for snapshot in snapshots {
            guard snapshot.capturedAt.timeIntervalSinceReferenceDate.isFinite, !snapshot.title.isEmpty,
                  snapshot.title.count <= 160, (1...512).contains(snapshot.resources.count),
                  Set(snapshot.resources.map { $0.resource.id }).count == snapshot.resources.count else { throw HistoryStorageError.invalidState }
            for edge in snapshot.resources {
                guard edge.persistence == .durable, edge.status == .confirmed, edge.confidence.isFinite, (0...1).contains(edge.confidence),
                      edge.firstSeen.timeIntervalSinceReferenceDate.isFinite, edge.lastSeen.timeIntervalSinceReferenceDate.isFinite,
                      edge.firstSeen <= edge.lastSeen, edge.lastSeen <= snapshot.capturedAt else { throw HistoryStorageError.invalidState }
            }
        }
    }
}
