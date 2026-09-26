import Foundation

public struct AgentRequest: Codable, Sendable {
    public let version: Int
    public let id: UUID
    public let command: AgentCommand
    public init(id: UUID, command: AgentCommand) { version = 1; self.id = id; self.command = command }
}

public struct AgentReply: Codable, Sendable {
    public let version: Int
    public let id: UUID
    public let body: AgentReplyBody
    public init(id: UUID, body: AgentReplyBody) { version = 1; self.id = id; self.body = body }
}

public enum AgentTransportError: Error, Sendable { case invalidMessage, unavailable, busy, timeout }

/// Applies byte/version/correlation bounds to the concrete application request contract.
public enum AgentCommandCodec {
    public static let maximumBytes = 512 * 1024

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let data = try JSONEncoder().encode(value)
        guard data.count <= maximumBytes else { throw AgentTransportError.invalidMessage }
        return data
    }

    public static func request(_ data: Data) throws -> AgentRequest {
        let request = try decode(AgentRequest.self, data: data)
        guard request.version == 1 else { throw AgentTransportError.invalidMessage }
        return request
    }

    public static func reply(_ data: Data, id: UUID) throws -> AgentReplyBody {
        let reply = try decode(AgentReply.self, data: data)
        guard reply.version == 1, reply.id == id else { throw AgentTransportError.invalidMessage }
        return reply.body
    }

    public static func publication(_ data: Data) throws -> AgentPublication {
        try decode(AgentPublication.self, data: data)
    }

    private static func decode<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
        guard data.count <= maximumBytes else { throw AgentTransportError.invalidMessage }
        return try JSONDecoder().decode(type, from: data)
    }
}
