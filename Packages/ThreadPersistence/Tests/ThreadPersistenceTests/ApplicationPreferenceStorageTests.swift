import Foundation
import Testing
import ThreadDomain
import ThreadPersistence

struct ApplicationPreferenceStorageTests {
    @Test func sharedFileApplicationPreferencesSurviveDatabaseReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("thread-app-preference-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let time = Date(timeIntervalSince1970: 100)
        let details = ["dev.zed.Zed", "com.microsoft.VSCode"].map { bundle in
            let thread = ThreadDomain.Thread(id: ThreadID(rawValue: UUID()), title: bundle, createdAt: time, lastActiveAt: time)
            let app = RestoreApplication(identity: ApplicationIdentity(bundleIdentifier: bundle), name: bundle, origin: .explicit)
            let edge = ThreadResource(resource: .file(FileIdentity(path: "/fixture/shared.swift")), confidence: 1,
                firstSeen: time, lastSeen: time, source: ActivitySourceID(rawValue: "fixture"), status: .confirmed, restoreApplication: app)
            return ThreadDetail(thread: thread, resources: [edge])
        }
        let state = ThreadGraphState(threads: details, corrections: [])
        try await database.saveGraph(state)
        let reopened = ThreadDatabase(directory: directory)
        try await reopened.prepare()
        let loaded = try await reopened.loadGraph()
        for detail in details { #expect(loaded.threads.first { $0.thread.id == detail.thread.id } == detail) }
    }
}
