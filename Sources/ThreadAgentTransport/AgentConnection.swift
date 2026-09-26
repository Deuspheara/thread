import Foundation
import OSLog
import ThreadDomain

/// Owns a signed XPC connection with bounded requests, deadlines and coalesced UI publications.
public actor AgentConnection: AgentRequesting {
    private let app: URL
    private var connection: NSXPCConnection?
    private var generation: UInt64 = 0
    private var pending: [UUID: CheckedContinuation<Data, Error>] = [:]
    private var deadlines: [UUID: Task<Void, Never>] = [:]
    private let contextChannel = AsyncStream<CurrentContext>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private let threadChannel = AsyncStream<ThreadPresentation>.makeStream(bufferingPolicy: .bufferingNewest(1))

    public init(app: URL) { self.app = app }
    public nonisolated func contexts() -> AsyncStream<CurrentContext> { contextChannel.stream }
    public nonisolated func updates() -> AsyncStream<ThreadPresentation> { threadChannel.stream }
    public var revision: UInt64 { generation }

    public func request(_ command: AgentCommand) async throws -> AgentReplyBody {
        try await perform(command, reconnect: true)
    }

    public func shutdownIfConnected() async throws {
        guard connection != nil else { return }
        guard case .done = try await perform(.shutdown, reconnect: false) else { throw AgentTransportError.unavailable }
    }

    private func perform(_ command: AgentCommand, reconnect: Bool) async throws -> AgentReplyBody {
        let id = UUID()
        let data = try AgentCommandCodec.encode(AgentRequest(id: id, command: command))
        let duration: Duration = if case .restore = command { .seconds(30) } else { .seconds(8) }
        let reply = try await exchange(id: id, data: data, probe: false, duration: duration, reconnect: reconnect)
        return try AgentCommandCodec.reply(reply, id: id)
    }

    public func probe() async throws -> AgentProbeReply {
        let id = UUID()
        let data = try AgentProbeCodec.encode(AgentProbeRequest(nonce: id))
        return try AgentProbeCodec.reply(try await exchange(id: id, data: data, probe: true, duration: .seconds(4)), nonce: id)
    }

    #if DEBUG
    public func probeRejectingPeer() async throws -> AgentProbeReply {
        guard pending.isEmpty else { throw AgentProbeError.busy }
        close()
        try connect(rejectPeer: true)
        return try await probe()
    }
    #endif

    public func close() {
        generation &+= 1
        connection?.invalidate()
        connection = nil
        for id in Array(pending.keys) { finish(id, result: .failure(AgentTransportError.unavailable)) }
    }

    private func exchange(id: UUID, data: Data, probe: Bool, duration: Duration, reconnect: Bool = true) async throws -> Data {
        guard pending.count < 8 else { throw AgentTransportError.busy }
        try Task.checkCancellation()
        if connection == nil {
            guard reconnect else { throw AgentTransportError.unavailable }
            try connect(rejectPeer: false)
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                pending[id] = continuation
                deadlines[id] = Task { [weak self] in
                    do { try await Task.sleep(for: duration) } catch { return }
                    await self?.cancel(id, error: AgentTransportError.timeout)
                }
                let proxy = connection?.remoteObjectProxyWithErrorHandler { [weak self] _ in
                    Task { await self?.finish(id, result: .failure(AgentTransportError.unavailable)) }
                } as? any ThreadAgentEndpoint
                guard let proxy else { finish(id, result: .failure(AgentTransportError.unavailable)); return }
                let reply: @Sendable (Data?) -> Void = { [weak self] value in
                    let result: Result<Data, Error> = value.map { .success($0) } ?? .failure(AgentTransportError.invalidMessage)
                    Task { await self?.finish(id, result: result) }
                }
                if probe { proxy.probe(data, reply: reply) } else { proxy.request(data, reply: reply) }
            }
        } onCancel: {
            Task { await self.cancel(id, error: CancellationError()) }
        }
    }

    private func connect(rejectPeer: Bool) throws {
        var requirement = try AgentSigningRequirement.string(for: app.appendingPathComponent("Contents/XPCServices/ThreadAgent.xpc"))
        if rejectPeer { requirement = "(\(requirement)) and identifier \"app.thread.desktop.rejected-peer\"" }
        let connection = NSXPCConnection(serviceName: "app.thread.desktop.agent")
        connection.setCodeSigningRequirement(requirement)
        connection.remoteObjectInterface = NSXPCInterface(with: ThreadAgentEndpoint.self)
        connection.exportedInterface = NSXPCInterface(with: ThreadAgentPublications.self)
        generation &+= 1
        let token = generation
        connection.exportedObject = AgentPublicationReceiver { [weak self] data in
            await self?.receive(data, generation: token)
        }
        connection.interruptionHandler = { [weak self] in Task { await self?.disconnected(token) } }
        connection.invalidationHandler = { [weak self] in Task { await self?.disconnected(token) } }
        self.connection = connection
        connection.activate()
    }

    private func receive(_ data: Data, generation token: UInt64) {
        guard generation == token else { return }
        do {
            switch try AgentCommandCodec.publication(data) {
            case let .context(value): contextChannel.continuation.yield(value)
            case let .threads(value):
                guard value.threads.count <= 20, value.threads.allSatisfy({ $0.applications.count <= 3 }) else {
                    throw AgentTransportError.invalidMessage
                }
                threadChannel.continuation.yield(value)
            case .disconnected: disconnected(token)
            }
        } catch {
            Logger(subsystem: "app.thread.desktop", category: "agent").error("Agent publication rejected")
            disconnected(token)
        }
    }

    private func cancel(_ id: UUID, error: Error) {
        guard pending[id] != nil else { return }
        if let data = try? AgentProbeCodec.encode(AgentProbeRequest(nonce: id)),
           let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in }) as? any ThreadAgentEndpoint {
            proxy.cancelRequest(data)
        }
        finish(id, result: .failure(error))
    }

    private func finish(_ id: UUID, result: Result<Data, Error>) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        deadlines.removeValue(forKey: id)?.cancel()
        continuation.resume(with: result)
    }

    private func disconnected(_ token: UInt64) {
        guard token == generation else { return }
        close()
        contextChannel.continuation.yield(CurrentContext(windowAvailability: .temporarilyUnavailable))
        threadChannel.continuation.yield(ThreadPresentation(threads: [], active: nil, history: .unavailable))
    }
}

/// A stateless Objective-C callback bridge; all decoding and state belongs to AgentConnection.
private final class AgentPublicationReceiver: NSObject, ThreadAgentPublications {
    private let receive: @Sendable (Data) async -> Void
    init(receive: @escaping @Sendable (Data) async -> Void) { self.receive = receive; super.init() }
    func publish(_ data: Data, reply: @escaping @Sendable () -> Void) {
        Task { [receive] in await receive(data); reply() }
    }
}
