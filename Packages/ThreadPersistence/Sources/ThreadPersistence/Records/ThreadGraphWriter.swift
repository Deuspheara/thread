import Foundation
import GRDB
import ThreadDomain

/// Writes one authoritative graph checkpoint, avoiding rewrites of unchanged payloads.
enum ThreadGraphWriter {
    static func save(_ state: ThreadGraphState, in database: Database) throws {
        for detail in state.threads {
            try saveThread(detail.thread, in: database)
            for edge in detail.resources { try saveEdge(edge, thread: detail.thread.id, in: database) }
        }
        try reconcileRemovals(state, in: database)
        for correction in state.corrections {
            try database.execute(sql: """
                INSERT INTO user_corrections(resource_id, thread_id) VALUES (?, ?)
                ON CONFLICT(resource_id) DO UPDATE SET thread_id = excluded.thread_id
                WHERE thread_id != excluded.thread_id
                """, arguments: [try GraphRecordCodec.key(correction.resource), correction.thread.rawValue.uuidString])
        }
        try ThreadSearchIndex.update(state, in: database)
        try database.execute(sql: """
            DELETE FROM resources WHERE identity NOT IN (SELECT resource_id FROM thread_resources)
            AND identity NOT IN (SELECT resource_id FROM user_corrections)
            """)
    }

    private static func saveThread(_ thread: ThreadDomain.Thread, in database: Database) throws {
        try database.execute(sql: """
            INSERT INTO threads(id, title, created_at, last_active_at, archived, payload) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET title=excluded.title, created_at=excluded.created_at, last_active_at=excluded.last_active_at,
                archived=excluded.archived, payload=excluded.payload WHERE payload != excluded.payload
            """, arguments: [thread.id.rawValue.uuidString, thread.title, thread.createdAt.timeIntervalSince1970,
                              thread.lastActiveAt.timeIntervalSince1970, thread.isArchived, try GraphRecordCodec.encode(thread)])
    }

    private static func saveEdge(_ edge: ThreadResource, thread: ThreadID, in database: Database) throws {
        let key = try GraphRecordCodec.key(edge.resource.id)
        try database.execute(sql: """
            INSERT INTO resources(identity, kind, last_seen, payload) VALUES (?, ?, ?, ?)
            ON CONFLICT(identity) DO UPDATE SET kind=excluded.kind, last_seen=excluded.last_seen, payload=excluded.payload
            WHERE excluded.last_seen >= last_seen AND (payload != excluded.payload OR last_seen != excluded.last_seen)
            """, arguments: [key, edge.resource.kind.rawValue, edge.lastSeen.timeIntervalSince1970, try GraphRecordCodec.encode(edge.resource)])
        try database.execute(sql: """
            INSERT INTO thread_resources(thread_id, resource_id, first_seen, last_seen, confidence, status, pinned, user_corrected, payload)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(thread_id, resource_id) DO UPDATE SET first_seen=excluded.first_seen, last_seen=excluded.last_seen,
                confidence=excluded.confidence, status=excluded.status, pinned=excluded.pinned,
                user_corrected=excluded.user_corrected, payload=excluded.payload WHERE payload != excluded.payload
            """, arguments: [thread.rawValue.uuidString, key, edge.firstSeen.timeIntervalSince1970, edge.lastSeen.timeIntervalSince1970,
                              edge.confidence, edge.status.rawValue, edge.pinned, edge.userCorrected, try GraphRecordCodec.encode(edge)])
    }

    private static func reconcileRemovals(_ state: ThreadGraphState, in database: Database) throws {
        let retained = Set(state.threads.map { $0.thread.id.rawValue.uuidString })
        for id in try String.fetchAll(database, sql: "SELECT id FROM threads") where !retained.contains(id) {
            try database.execute(sql: "DELETE FROM threads WHERE id = ?", arguments: [id])
        }
        for detail in state.threads {
            let id = detail.thread.id.rawValue.uuidString
            let resources = try Set(detail.resources.map { try GraphRecordCodec.key($0.resource.id) })
            for key in try String.fetchAll(database, sql: "SELECT resource_id FROM thread_resources WHERE thread_id = ?", arguments: [id]) where !resources.contains(key) {
                try database.execute(sql: "DELETE FROM thread_resources WHERE thread_id = ? AND resource_id = ?", arguments: [id, key])
            }
        }
        let corrected = try Set(state.corrections.map { try GraphRecordCodec.key($0.resource) })
        for key in try String.fetchAll(database, sql: "SELECT resource_id FROM user_corrections") where !corrected.contains(key) {
            try database.execute(sql: "DELETE FROM user_corrections WHERE resource_id = ?", arguments: [key])
        }
    }
}
