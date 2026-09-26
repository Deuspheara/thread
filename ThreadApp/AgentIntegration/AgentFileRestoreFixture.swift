#if DEBUG
import Foundation
import Darwin
import OSLog
import ThreadDomain
import ThreadPersistence
import ThreadAgentTransport

/// Verifies a saved file-only Thread through the actual app client and helper in private disposable storage.
enum AgentFileRestoreFixture {
    @MainActor static func runIfRequested() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard environment["THREAD_AGENT_FILE_RESTORE_CHECK"] == "1" else { return false }
        guard let path = environment["THREAD_DATA_DIRECTORY"], let directory = ownedDirectory(path) else { exit(78) }
        Task {
            let client = AgentClient(app: Bundle.main.bundleURL, debugDirectory: directory.path)
            var passed = false
            do {
                let thread = try await seed(directory)
                let availability = try await client.start()
                guard availability.processIdentifier > 0, availability.processIdentifier != getpid() else {
                    throw AgentTransportError.invalidMessage
                }
                try await client.prepare()
                guard let page = try await client.detailPage(thread, after: nil, limit: 64),
                      page.resources.count == 1 else { throw AgentTransportError.invalidMessage }
                let report = try await client.restore(thread)
                guard report.thread == thread, report.results.count == 1,
                      report.results[0].resource == page.resources[0].resource.id,
                      report.results[0].capability == .resource, report.results[0].outcome == .restored else {
                    throw AgentTransportError.invalidMessage
                }
                passed = true
            } catch {
                Logger(subsystem: "app.thread.desktop", category: "restore").error("Owned file restore fixture failed")
            }
            await client.shutdown()
            do {
                let result = directory.appendingPathComponent("AgentFileRestoreResult")
                try Data((passed ? "passed" : "failed").utf8).write(to: result, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: result.path)
            } catch { exit(74) }
            exit(passed ? 0 : 1)
        }
        return true
    }

    private static func seed(_ directory: URL) async throws -> ThreadID {
        let file = directory.appendingPathComponent("SavedThreadRestore.txt")
        try Data("Thread saved file restoration check.\nDisposable test document.\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let now = Date()
        let id = ThreadID(rawValue: UUID())
        let thread = ThreadDomain.Thread(id: id, title: "Saved file fixture", createdAt: now, lastActiveAt: now)
        let edge = ThreadResource(resource: .file(FileIdentity(path: file.path)), confidence: 1,
            firstSeen: now, lastSeen: now, source: ActivitySourceID(rawValue: "fixture"), status: .confirmed)
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        try await database.saveGraph(ThreadGraphState(threads: [ThreadDetail(thread: thread, resources: [edge])], corrections: []))
        return id
    }

    private static func ownedDirectory(_ path: String) -> URL? {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let parent = url.deletingLastPathComponent()
        guard url.lastPathComponent == "data", parent.lastPathComponent.hasPrefix("th-agent-file-restore-"),
              ["/private/tmp", "/tmp"].contains(parent.deletingLastPathComponent().path),
              !FileManager.default.fileExists(atPath: url.appendingPathComponent("Thread.sqlite").path) else { return nil }
        for directory in [parent, url] {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path),
                  attributes[.type] as? FileAttributeType == .typeDirectory,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else { return nil }
        }
        return url
    }
}
#endif
