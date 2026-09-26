/// Defines durable graph storage without exposing a database implementation.
public protocol ThreadRepository: Sendable {
    func loadGraph() async throws -> ThreadGraphState
    func saveGraph(_ state: ThreadGraphState) async throws
}
