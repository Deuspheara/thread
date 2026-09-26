import Foundation
import GRDB
import Testing
import ThreadDomain
@testable import ThreadPersistence

struct ThreadSearchTests {
    let epoch = Date(timeIntervalSince1970: 100)
    func detail(id: ThreadID = ThreadID(rawValue: UUID()), title: String = "HomeControl", archived: Bool = false,
                resources: [Resource] = [], status: MembershipStatus = .confirmed) -> ThreadDetail {
        ThreadDetail(thread: ThreadDomain.Thread(id: id, title: title, createdAt: epoch, lastActiveAt: epoch, isArchived: archived),
            resources: resources.map { ThreadResource(resource: $0, confidence: 0.97, firstSeen: epoch, lastSeen: epoch,
                source: ActivitySourceID(rawValue: "test"), status: status) })
    }
    func state(_ threads: [ThreadDetail]) -> ThreadGraphState { ThreadGraphState(threads: threads, corrections: []) }

    @Test func metadataPrefixesMatchWithoutIndexingPrivatePathPrefixesOrRawURLs() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let repository = RepositoryIdentity(commonDirectory: "/private-user/HomeControl/.git")
        let page = BrowserTabContext(identity: BrowserTabIdentity(connection: BrowserConnectionIdentity(rawValue: UUID()), tab: 1),
            browser: .safari, window: 1, url: "https://developer.example.com/unindexedsecret", domain: "developer.example.com", title: "Firmware Docs", isActive: true)
        let work = detail(resources: [.branch(repository, "fix/ota-reconnect"), .file(FileIdentity(path: "/private-user/DeviceSession.swift")), .browserPage(page)])
        try await database.saveGraph(state([work]))
        for query in ["homec", "ota reco", "devicesess", "firmware", "developer.example"] {
            #expect(try await database.search(query: query, includeArchived: false, limit: 10).map(\.id) == [work.thread.id])
        }
        for query in ["private-user", "unindexedsecret", "OR", "\" OR 1=1 --", "***"] {
            #expect(try await database.search(query: query, includeArchived: false, limit: 10).isEmpty)
        }
        #expect(try await database.search(query: "home", includeArchived: false, limit: 10).first?.resourceCount == 3)
    }

    @Test func renameArchiveAndReassignmentRemoveStaleSearchMatches() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let file = Resource.file(FileIdentity(path: "/work/Notifications.swift"))
        let a = detail(title: "Old title", resources: [file]), b = detail(title: "Other")
        try await database.saveGraph(state([a, b]))
        let movedA = detail(id: a.thread.id, title: "New title", archived: true)
        let movedB = detail(id: b.thread.id, title: "Other", resources: [file])
        try await database.saveGraph(state([movedA, movedB]))
        #expect(try await database.search(query: "old", includeArchived: true, limit: 10).isEmpty)
        #expect(try await database.search(query: "new", includeArchived: false, limit: 10).isEmpty)
        #expect(try await database.search(query: "new", includeArchived: true, limit: 10).first?.id == a.thread.id)
        #expect(try await database.search(query: "notifications", includeArchived: true, limit: 10).map(\.id) == [b.thread.id])
        try await database.saveGraph(state([]))
        #expect(try await database.search(query: "notifications", includeArchived: true, limit: 10).isEmpty)
    }

    @Test func provisionalResourcesDoNotEnterSearchAndResultsRespectLimits() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let work = detail(resources: [.file(FileIdentity(path: "/work/Provisional.swift"))], status: .provisional)
        try await database.saveGraph(state([work, detail(title: "Second")]))
        #expect(try await database.search(query: "provisional", includeArchived: false, limit: 10).isEmpty)
        #expect(try await database.search(query: "", includeArchived: false, limit: 1).count == 1)
        #expect(try await database.search(query: "", includeArchived: false, limit: 0).isEmpty)
    }

    @Test func migrationBackfillsExistingHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let connection = try DatabaseQueue(path: directory.appendingPathComponent("Thread.sqlite").path)
        try FoundationMigration.migrator().migrate(connection, upTo: "0003_activity_archive")
        let old = detail(title: "Existing history")
        try await connection.write { db in
            try db.execute(sql: "INSERT INTO threads(id,title,created_at,last_active_at,archived,payload) VALUES(?,?,?,?,?,?)",
                arguments: [old.thread.id.rawValue.uuidString, old.thread.title, epoch.timeIntervalSince1970,
                            epoch.timeIntervalSince1970, false, try GraphRecordCodec.encode(old.thread)])
        }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        #expect(try await database.search(query: "existing", includeArchived: false, limit: 10).first?.id == old.thread.id)
    }
}
