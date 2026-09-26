import Foundation
import Testing
import ThreadDomain
import ThreadAgentTransport

struct AgentCommandCodecTests {
    @Test func shutdownNeverConnectsToAnUnusedHelper() async throws {
        let connection = AgentConnection(app: URL(fileURLWithPath: "/nonexistent-fixture.app"))
        // A connect would fail signature validation; a fresh shutdown has no peer to contact.
        try await connection.shutdownIfConnected()
        await connection.close()
    }

    @Test func responsesCannotBeUsedForAnotherRequestOrVersion() throws {
        let id = UUID()
        let reply = try AgentCommandCodec.encode(AgentReply(id: id, body: .done))
        #expect(throws: AgentTransportError.invalidMessage) { try AgentCommandCodec.reply(reply, id: UUID()) }
        var object = try #require(JSONSerialization.jsonObject(with: reply) as? [String: Any])
        object["version"] = 2
        let unsupported = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: AgentTransportError.invalidMessage) { try AgentCommandCodec.reply(unsupported, id: id) }
    }

    @Test func byteLimitsApplyBeforeDecodingPublicationsAndCommands() throws {
        let oversized = Data(repeating: 32, count: AgentCommandCodec.maximumBytes + 1)
        #expect(throws: AgentTransportError.invalidMessage) { try AgentCommandCodec.request(oversized) }
        #expect(throws: AgentTransportError.invalidMessage) { try AgentCommandCodec.publication(oversized) }
        let request = try AgentCommandCodec.encode(AgentRequest(id: UUID(), command: .detail(ThreadID(rawValue: UUID()), after: nil, limit: 64)))
        if case .detail(_, _, 64) = try AgentCommandCodec.request(request).command {} else {
            Issue.record("Typed detail request lost its bounded page intent")
        }
    }
}
