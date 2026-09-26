import Foundation
import ThreadAgentTransport

/// Bounds in-flight command work and remembers cancellation arriving before request registration.
@MainActor
final class AgentRequestQueue {
    private var requests: [UUID: Task<Void, Never>] = [:]
    private var cancelled: Set<UUID> = []
    private var cancellationOrder: [UUID] = []

    func submit(_ id: UUID, operation: @escaping @MainActor @Sendable () async -> AgentReplyBody,
                reply: @escaping @Sendable (Data?) -> Void) {
        if cancelled.remove(id) != nil {
            cancellationOrder.removeAll { $0 == id }
            respond(.failure(.cancelled), id: id, reply: reply)
            return
        }
        guard requests.count < 8, requests[id] == nil else {
            respond(.failure(.busy), id: id, reply: reply)
            return
        }
        requests[id] = Task { [weak self] in
            guard let self else { reply(nil); return }
            let body = Task.isCancelled ? .failure(AgentFailure.cancelled) : await operation()
            requests.removeValue(forKey: id)
            respond(body, id: id, reply: reply)
        }
    }

    func cancel(_ id: UUID) {
        if let request = requests[id] { request.cancel(); return }
        guard cancelled.insert(id).inserted else { return }
        cancellationOrder.append(id)
        if cancellationOrder.count > 64 { cancelled.remove(cancellationOrder.removeFirst()) }
    }

    func cancelAll(except id: UUID? = nil) {
        for (requestID, task) in requests where requestID != id { task.cancel() }
    }

    func clearCancellationHistory() { cancelled.removeAll(); cancellationOrder.removeAll() }

    private func respond(_ body: AgentReplyBody, id: UUID, reply: @Sendable (Data?) -> Void) {
        reply(try? AgentCommandCodec.encode(AgentReply(id: id, body: body)))
    }
}
