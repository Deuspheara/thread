import Foundation
import Testing
import ThreadAgentTransport
@testable import ThreadAgent

@MainActor
struct AgentRequestQueueTests {
    @Test func cancellationBeforeRegistrationPreventsTheOperation() async throws {
        let queue = AgentRequestQueue()
        let id = UUID()
        let counter = OperationCounter()
        let channel = AsyncStream<AgentReplyBody>.makeStream(bufferingPolicy: .bufferingNewest(1))
        queue.cancel(id)
        queue.submit(id, operation: { counter.count += 1; return .done }, reply: reply(id, channel.continuation))
        for await result in channel.stream {
            guard case .failure(.cancelled) = result else { Issue.record("Early cancellation was not acknowledged"); return }
            break
        }
        #expect(counter.count == 0)
    }

    @Test func ninthRequestIsRejectedWhileEightOperationsArePending() async throws {
        let queue = AgentRequestQueue()
        let gate = OperationGate()
        for _ in 0..<8 {
            queue.submit(UUID(), operation: { await gate.wait(); return .done }, reply: { _ in })
        }
        let id = UUID()
        let channel = AsyncStream<AgentReplyBody>.makeStream(bufferingPolicy: .bufferingNewest(1))
        queue.submit(id, operation: { Issue.record("Overflow request executed"); return .done }, reply: reply(id, channel.continuation))
        for await result in channel.stream {
            guard case .failure(.busy) = result else { Issue.record("Request admission was not bounded"); return }
            break
        }
        queue.cancelAll()
        gate.release()
    }

    @Test func disconnectedPeerCannotSubmitLateWork() async {
        let session = AgentCommandSession(appBundle: Bundle.main)
        let peer = AgentPeerLifetime()
        await session.disconnected(peer)
        // More than the old rejection-cache capacity must not revive this connection.
        for _ in 0..<128 { await session.disconnected(AgentPeerLifetime()) }
        let unused = NSXPCConnection(serviceName: "fixture.not-activated")
        let publisher = AgentPublicationChannel(peer: AgentPublicationPeer(connection: unused))
        let request = AgentRequest(id: UUID(), command: .recent(limit: 1))
        let channel = AsyncStream<AgentReplyBody>.makeStream(bufferingPolicy: .bufferingNewest(1))
        session.submit(request, peer: peer, publisher: publisher, reply: reply(request.id, channel.continuation))
        for await result in channel.stream {
            guard case .failure(.cancelled) = result else { Issue.record("Disconnected peer was admitted"); return }
            break
        }
    }

    private func reply(_ id: UUID, _ continuation: AsyncStream<AgentReplyBody>.Continuation) -> @Sendable (Data?) -> Void {
        { data in
            guard let data, let value = try? AgentCommandCodec.reply(data, id: id) else {
                Issue.record("Invalid queue reply"); continuation.finish(); return
            }
            continuation.yield(value)
        }
    }
}

@MainActor private final class OperationCounter { var count = 0 }

@MainActor private final class OperationGate {
    private var released = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if released { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func release() {
        released = true
        for continuation in waiting { continuation.resume() }
        waiting.removeAll()
    }
}
