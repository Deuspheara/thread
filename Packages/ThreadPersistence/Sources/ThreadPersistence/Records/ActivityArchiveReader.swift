import Foundation
import GRDB
import ThreadDomain

/// Reads bounded typed history, checking stored IDs against decoded payloads.
enum ActivityArchiveReader {
    static func snapshots(thread: ThreadID, limit: Int, in database: Database) throws -> [ThreadSnapshot] {
        try Row.fetchAll(database, sql: "SELECT id, payload FROM snapshots WHERE thread_id = ? ORDER BY captured_at DESC, id DESC LIMIT ?",
                         arguments: [thread.rawValue.uuidString, min(100, max(0, limit))]).map { row in
            let snapshot = try GraphRecordCodec.decode(ThreadSnapshot.self, row["payload"])
            guard snapshot.thread == thread, snapshot.id.rawValue.uuidString == row["id"] as String else { throw HistoryStorageError.invalidState }
            try ActivityArchiveWriter.validate(events: [], snapshots: [snapshot], time: snapshot.capturedAt)
            return snapshot
        }
    }

    static func events(since time: Date, limit: Int, in database: Database) throws -> [ArchivedActivityEvent] {
        try Row.fetchAll(database, sql: "SELECT id, thread_id, payload FROM events WHERE timestamp >= ? ORDER BY timestamp DESC, id DESC LIMIT ?",
                         arguments: [time.timeIntervalSince1970, min(1000, max(0, limit))]).map { row in
            let event = try GraphRecordCodec.decode(ActivityEvent.self, row["payload"])
            guard event.id.rawValue.uuidString == row["id"] as String else { throw HistoryStorageError.invalidState }
            let rawThread: String? = row["thread_id"]
            let thread: ThreadID?
            if let rawThread {
                guard let uuid = UUID(uuidString: rawThread) else { throw HistoryStorageError.invalidState }
                thread = ThreadID(rawValue: uuid)
            } else { thread = nil }
            return ArchivedActivityEvent(event: event, thread: thread)
        }
    }
}
