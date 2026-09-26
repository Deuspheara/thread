import Foundation

/// Validates Safari's request/reply native messages before forwarding local metadata.
public struct SafariRequestForwarder {
    public struct Reply: Codable, Sendable {
        public let sequence: UInt64
        public let forwarded: Bool
        public let instance: String?
    }

    private let endpoint: URL

    public init(endpoint: URL) { self.endpoint = endpoint }

    public func forwardRestoreReply(_ data: Data) throws -> BrowserRestoreReply {
        guard data.count <= 1024 else { throw BrowserTransportError.invalidFrame }
        let reply = try JSONDecoder().decode(BrowserRestoreReply.self, from: data)
        try reply.validate()
        let endpoint = self.endpoint.deletingLastPathComponent()
            .appendingPathComponent("r/\(reply.id)/s")
        try BrowserMessageSender().sendControl(JSONEncoder().encode(reply), to: endpoint)
        return reply
    }

    public func forward(_ data: Data) throws -> Reply {
        guard data.count <= 16_384 else { throw BrowserTransportError.invalidFrame }
        let message = try JSONDecoder().decode(BrowserMessage.self, from: data)
        guard message.browser == .safari else { throw BrowserTransportError.invalidOrigin }
        guard let safe = try message.sanitized() else {
            return Reply(sequence: message.sequence, forwarded: false, instance: nil)
        }
        let instance = try BrowserMessageSender().send(safe, to: endpoint)
        return Reply(sequence: safe.sequence, forwarded: instance != nil, instance: instance)
    }
}
