import Foundation
import ThreadAgentTransport

/// Applies acknowledgement backpressure and a deadline to each helper publication.
actor AgentPublicationChannel {
    private let peer: AgentPublicationPeer
    private var pending: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var deadlines: [UUID: Task<Void, Never>] = [:]

    init(peer: AgentPublicationPeer) { self.peer = peer }

    func send(_ publication: AgentPublication) async throws {
        guard pending.count < 2 else { throw AgentTransportError.busy }
        try Task.checkCancellation()
        let data = try AgentCommandCodec.encode(publication)
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                pending[id] = continuation
                deadlines[id] = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(4)) } catch { return }
                    await self?.finish(id, result: .failure(AgentTransportError.timeout))
                }
                let proxy = peer.connection.remoteObjectProxyWithErrorHandler { [weak self] _ in
                    Task { await self?.finish(id, result: .failure(AgentTransportError.unavailable)) }
                } as? any ThreadAgentPublications
                guard let proxy else { finish(id, result: .failure(AgentTransportError.unavailable)); return }
                proxy.publish(data) { [weak self] in Task { await self?.finish(id, result: .success(())) } }
            }
        } onCancel: {
            Task { await self.finish(id, result: .failure(CancellationError())) }
        }
    }

    private func finish(_ id: UUID, result: Result<Void, Error>) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        deadlines.removeValue(forKey: id)?.cancel()
        continuation.resume(with: result)
    }
}

/// NSXPCConnection supports concurrent proxy calls; configuration is finished before listener activation.
/// This immutable Foundation bridge is the only unchecked boundary; pending state stays actor-owned.
final class AgentPublicationPeer: @unchecked Sendable {
    let connection: NSXPCConnection
    init(connection: NSXPCConnection) { self.connection = connection }
}
