import Foundation
import GRDB
import Testing
import ThreadDomain
import ThreadPersistence

struct ThreadGraphStorageTests {
    let epoch = Date(timeIntervalSince1970: 100)
    func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("thread-db-" + UUID().uuidString) }
    func state(title: String = "Work") -> ThreadGraphState {
        let id = ThreadID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let resource = Resource.file(FileIdentity(path: "/work/design.swift"))
        let edge = ThreadResource(resource: resource, confidence: 1, firstSeen: epoch, lastSeen: epoch,
                                  source: ActivitySourceID(rawValue: "user"), status: .confirmed, pinned: true, userCorrected: true)
        let thread = ThreadDomain.Thread(id: id, title: title, createdAt: epoch, lastActiveAt: epoch, isArchived: true)
        return ThreadGraphState(threads: [ThreadDetail(thread: thread, resources: [edge])],
                                corrections: [ResourceCorrection(resource: resource.id, thread: id)])
    }

    @Test func graphAndCorrectionMetadataSurviveReopenAndUnchangedSaveDoesNotRewriteRows() async throws {
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let database = ThreadDatabase(directory: path)
        try await database.prepare()
        let original = state()
        try await database.saveGraph(original)
        let inspector = try DatabaseQueue(path: path.appendingPathComponent("Thread.sqlite").path)
        try await inspector.write { db in
            try db.execute(sql: "CREATE TABLE updates(count INTEGER NOT NULL); INSERT INTO updates VALUES(0)")
            for table in ["threads", "resources", "thread_resources", "user_corrections"] {
                try db.execute(sql: "CREATE TRIGGER count_\(table) AFTER UPDATE ON \(table) BEGIN UPDATE updates SET count = count + 1; END")
            }
        }
        try await database.saveGraph(original)
        let updates = try await inspector.read { try Int.fetchOne($0, sql: "SELECT count FROM updates") }
        #expect(updates == 0)
        let reopened = ThreadDatabase(directory: path)
        try await reopened.prepare()
        #expect(try await reopened.loadGraph() == original)
    }

    @Test func sharedTerminalRetainsPerThreadDirectoriesAfterDatabaseReopen() async throws {
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let database = ThreadDatabase(directory: path)
        try await database.prepare()
        let session = TerminalSessionIdentity(rawValue: UUID())
        let details = ["/work/A", "/work/B"].enumerated().map { index, cwd in
            let time = epoch.addingTimeInterval(Double(index))
            let thread = ThreadDomain.Thread(id: ThreadID(rawValue: UUID()), title: cwd, createdAt: time, lastActiveAt: time)
            let terminal = Resource.terminal(TerminalContext(session: session, processIdentifier: 1, workingDirectory: cwd,
                                                              terminalApplication: nil, sequence: UInt64(index + 1)))
            let edge = ThreadResource(resource: terminal, confidence: 0.97, firstSeen: time, lastSeen: time,
                                      source: ActivitySourceID(rawValue: "shell"), status: .confirmed)
            return ThreadDetail(thread: thread, resources: [edge])
        }
        try await database.saveGraph(ThreadGraphState(threads: details, corrections: []))
        let reopened = ThreadDatabase(directory: path)
        try await reopened.prepare()
        let loaded = try await reopened.loadGraph()
        for original in details {
            #expect(loaded.threads.first { $0.thread.id == original.thread.id } == original)
        }
    }

    @Test func failedTransactionRollsBackThreadRenameAndRetainsPriorGraph() async throws {
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let database = ThreadDatabase(directory: path)
        try await database.prepare()
        let original = state()
        try await database.saveGraph(original)
        let inspector = try DatabaseQueue(path: path.appendingPathComponent("Thread.sqlite").path)
        try await inspector.write { db in
            try db.execute(sql: "CREATE TRIGGER fail_edge BEFORE INSERT ON thread_resources BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        }
        await #expect(throws: HistoryStorageError.writeFailed) { try await database.saveGraph(state(title: "Changed")) }
        #expect(try await database.loadGraph() == original)
    }

    @Test func removingRelationshipsAndCorrectionsPrunesOrphanResourcesAtomically() async throws {
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let database = ThreadDatabase(directory: path)
        try await database.prepare()
        try await database.saveGraph(state())
        try await database.saveGraph(ThreadGraphState(threads: [], corrections: []))
        #expect(try await database.loadGraph().threads.isEmpty)
        let inspector = try DatabaseQueue(path: path.appendingPathComponent("Thread.sqlite").path)
        let count = try await inspector.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM resources") }
        #expect(count == 0)
    }

    @Test func invalidCorrectionsAndCorruptPayloadsFailWithoutReplacingValidHistory() async throws {
        let path = directory()
        defer { try? FileManager.default.removeItem(at: path) }
        let database = ThreadDatabase(directory: path)
        try await database.prepare()
        let original = state()
        try await database.saveGraph(original)
        let invalid = ThreadGraphState(threads: original.threads, corrections: [])
        await #expect(throws: HistoryStorageError.invalidState) { try await database.saveGraph(invalid) }
        #expect(try await database.loadGraph() == original)
        let inspector = try DatabaseQueue(path: path.appendingPathComponent("Thread.sqlite").path)
        try await inspector.write { try $0.execute(sql: "UPDATE thread_resources SET payload = X'00'") }
        await #expect(throws: HistoryStorageError.readFailed) { try await database.loadGraph() }
    }
}
