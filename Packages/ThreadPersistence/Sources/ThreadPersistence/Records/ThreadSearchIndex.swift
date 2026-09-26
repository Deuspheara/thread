import Foundation
import GRDB
import ThreadDomain

/// Maintains searchable metadata in the same transaction as graph changes.
enum ThreadSearchIndex {
    static func update(_ state: ThreadGraphState, in database: Database) throws {
        for detail in state.threads {
            let metadata = Set(detail.resources.filter { $0.status == .confirmed }.map { text($0.resource) })
                .filter { !$0.isEmpty }.sorted().joined(separator: "\n")
            try database.execute(sql: """
                INSERT INTO thread_search_documents(thread_id, title, resources) VALUES (?, ?, ?)
                ON CONFLICT(thread_id) DO UPDATE SET title=excluded.title, resources=excluded.resources
                WHERE title != excluded.title OR resources != excluded.resources
                """, arguments: [detail.thread.id.rawValue.uuidString, detail.thread.title, metadata])
        }
    }

    private static func text(_ resource: Resource) -> String {
        switch resource {
        case .application(let app): app.name
        case .window(let window): window.title ?? ""
        case .browserPage(let page): page.title + "\n" + page.domain
        case .terminal(let terminal): basename(terminal.workingDirectory)
        case .workingDirectory(let path): basename(path)
        case .repository(let repository): basename(repository.rootPath) + "\n" + (repository.branch ?? "")
        case .branch(_, let branch): branch
        case .file(let file): basename(file.path)
        }
    }
    private static func basename(_ path: String) -> String { URL(fileURLWithPath: path).lastPathComponent }
}
