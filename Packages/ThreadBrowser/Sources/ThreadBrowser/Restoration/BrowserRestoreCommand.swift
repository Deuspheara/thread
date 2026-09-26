import Foundation

/// Defines a narrow connection-scoped tab restore request for native messaging.
public struct BrowserRestoreCommand: Codable, Sendable {
    public let version: Int
    public let kind: String
    public let id: String
    public let connection: String
    public let url: String
    public let tabID: Int64?
    public let expiresAt: Double

    public init(id: UUID = UUID(), connection: UUID, url: String, tabID: Int64?) {
        version = 1; kind = "restoreTab"
        self.id = id.uuidString.lowercased(); self.connection = connection.uuidString.lowercased()
        self.url = url; self.tabID = tabID
        expiresAt = Date().addingTimeInterval(3.5).timeIntervalSince1970 * 1000
    }

    public func validate() throws {
        guard expiresAt.isFinite, expiresAt > Date().timeIntervalSince1970 * 1000,
              expiresAt <= Date().addingTimeInterval(10).timeIntervalSince1970 * 1000,
              version == 1, kind == "restoreTab", UUID(uuidString: id) != nil, UUID(uuidString: connection) != nil,
              tabID.map({ $0 >= 0 && $0 < 9_007_199_254_740_992 }) ?? true,
              let parts = URLComponents(string: url), parts.query == nil, parts.fragment == nil,
              BrowserURLPolicy().sanitize(url) != nil else { throw BrowserTransportError.invalidMessage }
    }
}

public struct BrowserRestoreReply: Codable, Sendable {
    public enum Outcome: String, Codable, Sendable { case focused, reopened, refused, busy, failed }
    public let version: Int
    public let kind: String
    public let id: String
    public let connection: String
    public let outcome: Outcome

    public init(id: String, connection: String, outcome: Outcome) {
        version = 1; kind = "restoreResult"; self.id = id; self.connection = connection; self.outcome = outcome
    }
    public func validate() throws {
        guard version == 1, kind == "restoreResult", UUID(uuidString: id) != nil,
              UUID(uuidString: connection) != nil else { throw BrowserTransportError.invalidMessage }
    }
}

struct BrowserRestoreEndpoint {
    let root: URL
    func host(_ connection: String) -> URL { root.appendingPathComponent("c/\(connection)/s") }
    func reply(_ id: String) -> URL { root.appendingPathComponent("r/\(id)/s") }
}
