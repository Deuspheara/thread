import Foundation
import ThreadDomain

/// Defines the bounded extension/host wire schema without any page contents.
public struct BrowserMessage: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case connected, opened, activated, updated, closed, focusCleared, disconnected }
    public let version: Int
    public let kind: Kind
    public let browser: BrowserKind
    public let application: ApplicationIdentity?
    public let connection: UUID
    public let sequence: UInt64
    public let isPrivate: Bool
    public let tabID: Int64?
    public let windowID: Int64?
    public let url: String?
    public let title: String?
    public let active: Bool?

    public init(kind: Kind, browser: BrowserKind, connection: UUID, sequence: UInt64, tabID: Int64? = nil,
                windowID: Int64? = nil, url: String? = nil, title: String? = nil, active: Bool? = nil, application: ApplicationIdentity? = nil) {
        version = 1
        self.kind = kind
        self.browser = browser
        self.application = application
        self.connection = connection
        self.sequence = sequence
        isPrivate = false
        self.tabID = tabID
        self.windowID = windowID
        self.url = url
        self.title = title
        self.active = active
    }

    public func sanitized() throws -> BrowserMessage? {
        guard !isPrivate else { return nil }
        guard version == 1, sequence > 0, sequence < 9_007_199_254_740_992 else { throw BrowserTransportError.invalidMessage }
        if let identifier = application?.bundleIdentifier {
            guard identifier.utf8.count <= 253, !identifier.isEmpty,
                  identifier.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 })
            else { throw BrowserTransportError.invalidMessage }
        }
        switch kind {
        case .connected, .disconnected, .focusCleared:
            return BrowserMessage(kind: kind, browser: browser, connection: connection, sequence: sequence)
        case .closed:
            guard let tabID, validID(tabID) else { throw BrowserTransportError.invalidMessage }
            return BrowserMessage(kind: kind, browser: browser, connection: connection, sequence: sequence, tabID: tabID)
        case .opened, .activated, .updated:
            guard let tabID, let windowID, validID(tabID), validID(windowID), let url,
                  let safe = BrowserURLPolicy().sanitize(url), let active, kind != .activated || active else { throw BrowserTransportError.invalidMessage }
            return BrowserMessage(kind: kind, browser: browser, connection: connection, sequence: sequence,
                                  tabID: tabID, windowID: windowID, url: safe.absoluteString,
                                  title: String((title ?? "").prefix(512)), active: active, application: application)
        }
    }

    /// Replaces extension-supplied identity with the native host's independently resolved identity.
    public func identified(by application: ApplicationIdentity?) -> BrowserMessage {
        BrowserMessage(kind: kind, browser: browser, connection: connection, sequence: sequence,
            tabID: tabID, windowID: windowID, url: url, title: title, active: active, application: application)
    }

    private func validID(_ value: Int64) -> Bool { value >= 0 && value < 9_007_199_254_740_992 }
}

public enum BrowserTransportError: Error, Sendable {
    case invalidMessage, unsafeDirectory, invalidPath, alreadyListening, unavailable, sendFailed, invalidFrame, invalidOrigin
}
