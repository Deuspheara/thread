#if DEBUG
import Foundation
import Darwin
import OSLog
import ThreadDomain
import ThreadAgentTransport

/// Exercises actual helper commands and crash recovery using an explicitly owned debug data directory.
enum AgentRuntimeFixture {
    @MainActor static func runIfRequested() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard environment["THREAD_AGENT_RUNTIME_CHECK"] == "1" else { return false }
        guard let path = environment["THREAD_DATA_DIRECTORY"], let directory = fixtureDirectory(path) else { exit(78) }
        Task {
            let connection = AgentConnection(app: Bundle.main.bundleURL)
            do {
                try await exercise(connection, directory: directory)
                try write("passed", name: "AgentRuntimeResult", directory: directory)
            } catch {
                Logger(subsystem: "app.thread.desktop", category: "agent").error("Owned runtime fixture failed")
                try? write("failed", name: "AgentRuntimeResult", directory: directory)
            }
            await connection.close()
            exit(0)
        }
        return true
    }

    private static func exercise(_ connection: AgentConnection, directory: URL) async throws {
        try await done(connection, .configure(debugDirectory: directory.path))
        let first = try await start(connection)
        try await done(connection, .prepare)
        try write(String(first), name: "AgentRuntimeReady", directory: directory)
        var publications = connection.updates().makeAsyncIterator()
        let thread = try await observedThread(&publications)
        try await saved(connection, .rename(thread, title: "Recovered fixture"))
        try await saved(connection, .pin(thread, pinned: true))
        try await saved(connection, .archive(thread, archived: true))
        let exclusions = try ObservationExclusions(applications: ["org.example.fixture"], domains: ["ignored.example"])
        try await done(connection, .saveExclusions(exclusions))
        try await verifyArchived(connection, thread: thread, exclusions: exclusions)
        try await verifyValidation(connection)
        let cancellation = try await AgentCancellationCheck.run(connection, thread: thread)
        try write(cancellation, name: "AgentCancellationResult", directory: directory)
        try write(String(first), name: "AgentRuntimeKillReady", directory: directory)
        // The script kills only the PID returned by this private, signed fixture connection.
        while let update = await publications.next() {
            if update.history == .unavailable { break }
        }
        try await done(connection, .configure(debugDirectory: directory.path))
        let second = try await start(connection)
        guard second > 0, second != first else { throw AgentTransportError.invalidMessage }
        try await done(connection, .prepare)
        try await verifyArchived(connection, thread: thread, exclusions: exclusions)
        try await saved(connection, .archive(thread, archived: false))
        guard case let .summaries(recent) = try await connection.request(.recent(limit: 20)),
              recent.contains(where: { $0.thread.id == thread && $0.thread.isPinned }) else {
            throw AgentTransportError.invalidMessage
        }
        try write(String(second), name: "AgentRuntimeRecovered", directory: directory)
        try await done(connection, .shutdown)
        guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent("Shell/activity.sock").path),
              !FileManager.default.fileExists(atPath: directory.appendingPathComponent("Browser/activity.sock").path) else {
            throw AgentTransportError.invalidMessage
        }
    }

    private static func observedThread(_ publications: inout AsyncStream<ThreadPresentation>.Iterator) async throws -> ThreadID {
        while let update = await publications.next() {
            if let thread = update.threads.first { return thread.thread.id }
        }
        throw AgentTransportError.unavailable
    }

    private static func verifyArchived(_ connection: AgentConnection, thread: ThreadID, exclusions: ObservationExclusions) async throws {
        guard case let .search(results) = try await connection.request(.search(query: "Recovered", includeArchived: true, limit: 20)),
              results.contains(where: { $0.id == thread && $0.isArchived }),
              case let .detail(page) = try await connection.request(.detail(thread, after: nil, limit: 64)),
              let page, page.thread.title == "Recovered fixture", page.thread.isPinned, page.thread.isArchived,
              !page.resources.isEmpty,
              case let .exclusions(rules) = try await connection.request(.exclusions), rules == exclusions else {
            throw AgentTransportError.invalidMessage
        }
    }

    private static func verifyValidation(_ connection: AgentConnection) async throws {
        guard case .failure(.invalidRequest) = try await connection.request(.recent(limit: 21)),
              case .failure(.restore(.unknownThread)) = try await connection.request(.restore(ThreadID(rawValue: UUID()))),
              case let .remote(state) = try await connection.request(.remoteState),
              !state.preferences.enabled, state.preferences.endpoint == nil else { throw AgentTransportError.invalidMessage }
        let invalidRules = try JSONDecoder().decode(ObservationExclusions.self,
            from: Data("{\"applications\":[],\"domains\":[\"https://example.com\"]}".utf8))
        let invalidRemote = try JSONDecoder().decode(RemoteInferencePreferences.self,
            from: Data("{\"enabled\":true,\"endpoint\":\"http://example.com/decisions\"}".utf8))
        guard case .failure(.invalidRequest) = try await connection.request(.saveExclusions(invalidRules)),
              case .failure(.invalidRequest) = try await connection.request(.remoteApply(invalidRemote, token: nil)) else {
            throw AgentTransportError.invalidMessage
        }
        // Remote disabled/no endpoint: this read does not access any user Keychain entry or provider.
    }

    private static func start(_ connection: AgentConnection) async throws -> Int32 {
        guard case let .availability(value) = try await connection.request(.start), value.shell,
              value.processIdentifier != getpid() else { throw AgentTransportError.invalidMessage }
        return value.processIdentifier
    }

    private static func saved(_ connection: AgentConnection, _ edit: ThreadEdit) async throws {
        guard case .history(.saved) = try await connection.request(.edit(edit)) else { throw AgentTransportError.invalidMessage }
    }

    private static func done(_ connection: AgentConnection, _ command: AgentCommand) async throws {
        guard case .done = try await connection.request(command) else { throw AgentTransportError.invalidMessage }
    }

    private static func write(_ value: String, name: String, directory: URL) throws {
        let file = directory.appendingPathComponent(name)
        try Data(value.utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private static func fixtureDirectory(_ path: String) -> URL? {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let parent = url.deletingLastPathComponent()
        guard url.lastPathComponent == "data", parent.lastPathComponent.hasPrefix("th-agent-runtime-"),
              ["/private/tmp", "/tmp"].contains(parent.deletingLastPathComponent().path) else { return nil }
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
