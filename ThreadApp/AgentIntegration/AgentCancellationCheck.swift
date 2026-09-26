#if DEBUG
import Foundation
import ThreadDomain
import ThreadAgentTransport

/// Exercises bounded caller cancellation against an already configured disposable helper connection.
enum AgentCancellationCheck {
    private enum Outcome: Sendable { case detail, cancelled, busy }

    @MainActor static func run(_ connection: AgentConnection, thread: ThreadID) async throws -> String {
        let edit = Task { try await connection.request(.edit(.rename(thread, title: "Cancelled edit"))) }
        edit.cancel()
        do {
            _ = try await edit.value
            throw AgentTransportError.invalidMessage
        } catch is CancellationError {
            // A pre-cancelled request must not submit a mutation.
        }
        var completed = 0
        var cancelled = 0
        var busy = 0
        for _ in 0..<4 {
            let reads = (0..<8).map { _ in Task.detached { try await read(connection, thread: thread) } }
            await Task.yield()
            for index in stride(from: 0, to: reads.count, by: 2) { reads[index].cancel() }
            for read in reads {
                switch try await read.value {
                case .detail: completed += 1
                case .cancelled: cancelled += 1
                case .busy: busy += 1
                }
            }
        }
        guard completed > 0,
              case let .detail(page) = try await connection.request(.detail(thread, after: nil, limit: 64)),
              page?.thread.title == "Recovered fixture", page?.thread.isArchived == true else {
            throw AgentTransportError.invalidMessage
        }
        return "reads=\(completed) cancelled=\(cancelled) busy=\(busy)"
    }

    private static func read(_ connection: AgentConnection, thread: ThreadID) async throws -> Outcome {
        do {
            switch try await connection.request(.detail(thread, after: nil, limit: 64)) {
            case let .detail(page):
                guard page?.thread.id == thread else { throw AgentTransportError.invalidMessage }
                return .detail
            case .failure(.cancelled): return .cancelled
            case .failure(.busy): return .busy
            default: throw AgentTransportError.invalidMessage
            }
        } catch is CancellationError {
            return .cancelled
        } catch AgentTransportError.busy {
            return .busy
        }
    }
}
#endif
