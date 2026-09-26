import Foundation
import Darwin
import ThreadAgentTransport

/// Bridges authenticated XPC callbacks to the helper-owned command session.
final class AgentProbeEndpoint: NSObject, ThreadAgentEndpoint {
    private let session: AgentCommandSession
    private let peer: AgentPeerLifetime
    private let publisher: AgentPublicationChannel
    init(session: AgentCommandSession, peer: AgentPeerLifetime, publisher: AgentPublicationChannel) {
        self.session = session; self.peer = peer; self.publisher = publisher; super.init()
    }

    func request(_ data: Data, reply: @escaping @Sendable (Data?) -> Void) {
        guard let request = try? AgentCommandCodec.request(data) else { reply(nil); return }
        Task { [session, peer, publisher] in await session.submit(request, peer: peer, publisher: publisher, reply: reply) }
    }

    func cancelRequest(_ data: Data) {
        guard let cancellation = try? AgentProbeCodec.request(data) else { return }
        Task { [session, peer] in await session.cancel(cancellation.nonce, peer: peer) }
    }

    func probe(_ data: Data, reply: @escaping @Sendable (Data?) -> Void) {
        do {
            let request = try AgentProbeCodec.request(data)
            reply(try AgentProbeCodec.encode(AgentProbeReply(nonce: request.nonce, processIdentifier: getpid())))
        } catch { reply(nil) }
    }
}

/// Restricts each connection to the invoking user and installed app signature before activation.
final class AgentListener: NSObject, NSXPCListenerDelegate {
    private let requirement: String
    private let session: AgentCommandSession

    init(requirement: String, session: AgentCommandSession) {
        self.requirement = requirement; self.session = session; super.init()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == getuid() else { return false }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: ThreadAgentEndpoint.self)
        let peer = AgentPeerLifetime()
        let publisher = AgentPublicationChannel(peer: AgentPublicationPeer(connection: connection))
        connection.remoteObjectInterface = NSXPCInterface(with: ThreadAgentPublications.self)
        connection.exportedObject = AgentProbeEndpoint(session: session, peer: peer, publisher: publisher)
        connection.invalidationHandler = { [session] in Task { await session.disconnected(peer) } }
        connection.interruptionHandler = { [session] in Task { await session.disconnected(peer) } }
        connection.activate()
        return true
    }
}
