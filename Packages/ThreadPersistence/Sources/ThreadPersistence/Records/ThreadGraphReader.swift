import Foundation
import GRDB
import ThreadDomain

/// Reconstructs typed graph checkpoints and fails closed on corrupt identities or payloads.
enum ThreadGraphReader {
    static func load(from database: Database) throws -> ThreadGraphState {
        var details: [ThreadDetail] = []
        for row in try Row.fetchAll(database, sql: "SELECT id, payload FROM threads ORDER BY last_active_at DESC, id") {
            let thread = try GraphRecordCodec.decode(ThreadDomain.Thread.self, row["payload"])
            guard thread.id.rawValue.uuidString == row["id"] as String else { throw HistoryStorageError.invalidState }
            var resources: [ThreadResource] = []
            for edgeRow in try Row.fetchAll(database, sql: "SELECT resource_id, payload FROM thread_resources WHERE thread_id = ? ORDER BY first_seen, resource_id", arguments: [thread.id.rawValue.uuidString]) {
                let edge = try GraphRecordCodec.decode(ThreadResource.self, edgeRow["payload"])
                guard try GraphRecordCodec.key(edge.resource.id) == edgeRow["resource_id"] as String else { throw HistoryStorageError.invalidState }
                resources.append(edge)
            }
            details.append(ThreadDetail(thread: thread, resources: resources))
        }
        let corrections = try Row.fetchAll(database, sql: "SELECT resource_id, thread_id FROM user_corrections ORDER BY resource_id").map { row in
            let key: String = row["resource_id"]
            let rawID: String = row["thread_id"]
            guard let uuid = UUID(uuidString: rawID) else { throw HistoryStorageError.invalidState }
            return ResourceCorrection(resource: try GraphRecordCodec.decode(ResourceID.self, Data(key.utf8)), thread: ThreadID(rawValue: uuid))
        }
        let state = ThreadGraphState(threads: details, corrections: corrections)
        try GraphRecordCodec.validate(state)
        return state
    }
}
