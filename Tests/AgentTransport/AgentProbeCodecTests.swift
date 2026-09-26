import Foundation
import Testing
import ThreadAgentTransport

struct AgentProbeCodecTests {
    @Test func readinessRequiresTheRequestNonceAndAValidProcess() throws {
        let request = AgentProbeRequest(nonce: UUID())
        #expect(try AgentProbeCodec.request(AgentProbeCodec.encode(request)).nonce == request.nonce)
        let reply = try AgentProbeCodec.encode(AgentProbeReply(nonce: request.nonce, processIdentifier: 123))
        #expect(try AgentProbeCodec.reply(reply, nonce: request.nonce).processIdentifier == 123)
        #expect(throws: AgentProbeError.invalidMessage) { try AgentProbeCodec.reply(reply, nonce: UUID()) }
        let invalid = try AgentProbeCodec.encode(AgentProbeReply(nonce: request.nonce, processIdentifier: 0))
        #expect(throws: AgentProbeError.invalidMessage) { try AgentProbeCodec.reply(invalid, nonce: request.nonce) }
    }

    @Test func unsupportedOrOversizedRequestsFailBeforeUse() throws {
        let unsupported = Data("{\"version\":2,\"nonce\":\"\(UUID().uuidString)\"}".utf8)
        #expect(throws: AgentProbeError.invalidMessage) { try AgentProbeCodec.request(unsupported) }
        #expect(throws: AgentProbeError.invalidMessage) { try AgentProbeCodec.request(Data(repeating: 32, count: 1025)) }
        #expect(throws: (any Error).self) { try AgentProbeCodec.request(Data("invalid".utf8)) }
    }
}
