import Foundation

/// The initial local readiness exchange; it carries no activity or credentials.
@objc public protocol ThreadAgentEndpoint {
    func probe(_ data: Data, reply: @escaping @Sendable (Data?) -> Void)
    func request(_ data: Data, reply: @escaping @Sendable (Data?) -> Void)
    func cancelRequest(_ data: Data)
}

@objc public protocol ThreadAgentPublications {
    func publish(_ data: Data, reply: @escaping @Sendable () -> Void)
}

public struct AgentProbeRequest: Codable, Sendable {
    public let version: Int
    public let nonce: UUID
    public init(nonce: UUID) { version = 1; self.nonce = nonce }
}

public struct AgentProbeReply: Codable, Sendable {
    public let version: Int
    public let nonce: UUID
    public let processIdentifier: Int32
    public init(nonce: UUID, processIdentifier: Int32) {
        version = 1; self.nonce = nonce; self.processIdentifier = processIdentifier
    }
}

public enum AgentProbeError: Error, Sendable { case signatureUnavailable, invalidMessage, unavailable, busy, timeout }

/// Encodes only the bounded version-one readiness contract.
public enum AgentProbeCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 1024 else { throw AgentProbeError.invalidMessage }
        return data
    }

    public static func request(_ data: Data) throws -> AgentProbeRequest {
        guard data.count <= 1024 else { throw AgentProbeError.invalidMessage }
        let request = try JSONDecoder().decode(AgentProbeRequest.self, from: data)
        guard request.version == 1 else { throw AgentProbeError.invalidMessage }
        return request
    }

    public static func reply(_ data: Data, nonce: UUID) throws -> AgentProbeReply {
        guard data.count <= 1024 else { throw AgentProbeError.invalidMessage }
        let reply = try JSONDecoder().decode(AgentProbeReply.self, from: data)
        guard reply.version == 1, reply.nonce == nonce, reply.processIdentifier > 0 else { throw AgentProbeError.invalidMessage }
        return reply
    }
}
