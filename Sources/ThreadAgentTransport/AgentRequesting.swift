import Foundation
import ThreadDomain

/// The local process boundary used by app intents; implementation owns connection lifecycle.
public protocol AgentRequesting: Sendable {
    func request(_ command: AgentCommand) async throws -> AgentReplyBody
    func contexts() -> AsyncStream<CurrentContext>
    func updates() -> AsyncStream<ThreadPresentation>
    func shutdownIfConnected() async throws
    func close() async
}
