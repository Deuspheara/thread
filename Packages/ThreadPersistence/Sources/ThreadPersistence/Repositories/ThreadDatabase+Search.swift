import Foundation
import GRDB
import ThreadDomain

/// Provides literal prefix-token search with explicit limits and archive filtering.
extension ThreadDatabase: ThreadSearch {
    public func search(query: String, includeArchived: Bool, limit: Int) throws -> [ThreadSearchResult] {
        let connection = try preparedConnection()
        let bounded = String(query.prefix(256))
        let tokens = bounded.split { !$0.isLetter && !$0.isNumber }.prefix(12)
        if !bounded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, tokens.isEmpty { return [] }
        let expression = tokens.map { "\"\($0)\"*" }.joined(separator: " AND ")
        do {
            return try connection.read { database in
                let columns = """
                    SELECT threads.id, threads.title, threads.last_active_at, threads.archived,
                        (SELECT COUNT(*) FROM thread_resources WHERE thread_id=threads.id AND status='confirmed') AS resource_count
                    FROM threads
                    """
                let rows: [Row]
                if expression.isEmpty {
                    rows = try Row.fetchAll(database, sql: columns + " WHERE (? OR archived=0) ORDER BY last_active_at DESC, id LIMIT ?",
                                            arguments: [includeArchived, min(100, max(0, limit))])
                } else {
                    rows = try Row.fetchAll(database, sql: columns + """
                         JOIN thread_search_documents ON thread_search_documents.thread_id=threads.id
                         JOIN thread_search_fts ON thread_search_fts.rowid=thread_search_documents.rowid
                         WHERE (? OR threads.archived=0) AND thread_search_fts MATCH ?
                         ORDER BY bm25(thread_search_fts, 4.0, 1.0), threads.last_active_at DESC, threads.id LIMIT ?
                        """, arguments: [includeArchived, expression, min(100, max(0, limit))])
                }
                return try rows.map { row in
                    let id: String = row["id"]
                    guard let uuid = UUID(uuidString: id) else { throw HistoryStorageError.invalidState }
                    return ThreadSearchResult(id: ThreadID(rawValue: uuid), title: row["title"],
                        lastActiveAt: Date(timeIntervalSince1970: row["last_active_at"]), resourceCount: row["resource_count"], isArchived: row["archived"])
                }
            }
        } catch { throw HistoryStorageError.readFailed }
    }
}
