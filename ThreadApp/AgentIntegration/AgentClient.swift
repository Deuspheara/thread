import Foundation
import ThreadDomain
import ThreadAgentTransport

/// Presents helper commands as domain ports and never replays an interrupted mutation.
actor AgentClient: ThreadReading, ThreadEditing, ThreadSearch, ThreadRestoring {
    private let connection: any AgentRequesting
    private let debugDirectory: String?
    private var observationRequested = false
    private var shutdownTask: Task<Void, Never>?

    init(app: URL, debugDirectory: String?) {
        connection = AgentConnection(app: app)
        self.debugDirectory = debugDirectory
    }

    init(connection: any AgentRequesting, debugDirectory: String?) {
        self.connection = connection
        self.debugDirectory = debugDirectory
    }

    nonisolated func contexts() -> AsyncStream<CurrentContext> { connection.contexts() }
    nonisolated func updates() -> AsyncStream<ThreadPresentation> { connection.updates() }

    func start() async throws -> AgentAvailability {
        observationRequested = true
        guard case let .availability(value) = try await call(.start) else { throw AgentTransportError.invalidMessage }
        return value
    }

    func prepare() async throws { try await done(.prepare) }
    func refresh() async throws { try await done(.refreshObservation) }
    func requestPermission() async throws { try await done(.requestPermission) }
    func shutdown() async {
        if let shutdownTask { await shutdownTask.value; return }
        observationRequested = false
        let connection = connection
        let task = Task {
            do { try await connection.shutdownIfConnected() }
            catch { LogCategory.activity.logger.error("Background shutdown unavailable") }
            await connection.close()
        }
        shutdownTask = task
        await task.value
    }

    func recentSummaries(limit: Int) async throws -> [ThreadSummary] {
        guard case let .summaries(value) = try await call(.recent(limit: limit)) else { throw ThreadReadError.unavailable }
        return value
    }

    func detailPage(_ thread: ThreadID, after resource: ResourceID?, limit: Int) async throws -> ThreadDetailPage? {
        guard case let .detail(value) = try await call(.detail(thread, after: resource, limit: limit)) else { throw ThreadReadError.unavailable }
        return value
    }

    func destinations(query: String, excluding thread: ThreadID, limit: Int) async throws -> [ThreadDomain.Thread] {
        guard case let .destinations(value) = try await call(.destinations(query: query, excluding: thread, limit: limit)) else {
            throw ThreadReadError.unavailable
        }
        return value
    }

    func search(query: String, includeArchived: Bool, limit: Int) async throws -> [ThreadSearchResult] {
        guard case let .search(value) = try await call(.search(query: query, includeArchived: includeArchived, limit: limit)) else {
            throw ThreadReadError.unavailable
        }
        return value
    }

    func edit(_ edit: ThreadEdit) async throws -> HistoryStatus {
        guard case let .history(value) = try await call(.edit(edit)) else { throw ThreadReadError.unavailable }
        return value
    }

    func restore(_ thread: ThreadID) async throws -> ThreadRestoreReport {
        guard case let .restore(value) = try await call(.restore(thread)) else { throw ThreadReadError.unavailable }
        return value
    }

    func exclusions() async throws -> ObservationExclusions {
        guard case let .exclusions(value) = try await call(.exclusions) else { throw ThreadReadError.unavailable }
        return value
    }
    func saveExclusions(_ value: ObservationExclusions) async throws { try await done(.saveExclusions(value)) }

    func remoteState() async throws -> RemoteInferenceState {
        guard case let .remote(value) = try await call(.remoteState) else { throw ThreadReadError.unavailable }
        return value
    }
    func remoteApply(_ value: RemoteInferencePreferences, token: String?) async throws { try await done(.remoteApply(value, token: token)) }
    func remoteDisable() async throws { try await done(.remoteDisable) }
    func remoteForget() async throws { try await done(.remoteForget) }

    private func done(_ command: AgentCommand) async throws {
        guard case .done = try await call(command) else { throw AgentTransportError.invalidMessage }
    }

    private func call(_ command: AgentCommand) async throws -> AgentReplyBody {
        try requireRunning()
        // Configure is idempotent. A dropped mutation is returned to the caller, never retried.
        try validate(try await connection.request(.configure(debugDirectory: debugDirectory)))
        try requireRunning()
        if observationRequested {
            switch command {
            case .start, .shutdown: break
            default:
                try validate(try await connection.request(.start))
                try requireRunning()
                try validate(try await connection.request(.prepare))
            }
        }
        try requireRunning()
        let reply: AgentReplyBody
        do { reply = try await connection.request(command) }
        catch AgentTransportError.busy { throw AgentTransportError.busy }
        catch {
            if command.requiresCompletionAcknowledgement { throw IntentCompletionError.unknown }
            throw error
        }
        try validate(reply)
        return reply
    }

    private func requireRunning() throws {
        try Task.checkCancellation()
        guard shutdownTask == nil else { throw CancellationError() }
    }

    private func validate(_ reply: AgentReplyBody) throws {
        guard case let .failure(failure) = reply else { return }
        switch failure {
        case let .edit(error): throw error
        case let .read(error): throw error
        case let .restore(error): throw error
        case let .remote(error): throw error
        case .cancelled: throw CancellationError()
        case .completionUnknown: throw IntentCompletionError.unknown
        case .busy: throw AgentTransportError.busy
        case .invalidRequest: throw AgentTransportError.invalidMessage
        case .unavailable: throw AgentTransportError.unavailable
        }
    }
}
