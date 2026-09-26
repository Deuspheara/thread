import Foundation

public enum BrowserKind: String, Codable, Sendable { case chromium, chrome, brave, edge, safari }

/// Scopes numeric tab identities to one native connection, avoiding cross-profile collisions.
public struct BrowserConnectionIdentity: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct BrowserTabIdentity: Hashable, Codable, Sendable {
    public let connection: BrowserConnectionIdentity
    public let tab: Int64
    public init(connection: BrowserConnectionIdentity, tab: Int64) { self.connection = connection; self.tab = tab }
}

/// Contains only sanitized tab metadata; URL queries/fragments/credentials never enter this value.
public struct BrowserTabContext: Equatable, Codable, Sendable {
    public let identity: BrowserTabIdentity
    public let browser: BrowserKind
    public let application: ApplicationIdentity?
    public let window: Int64
    public let url: String
    public let domain: String
    public let title: String
    public let isActive: Bool
    public init(identity: BrowserTabIdentity, browser: BrowserKind, window: Int64, url: String,
                domain: String, title: String, isActive: Bool, application: ApplicationIdentity? = nil) {
        self.identity = identity
        self.browser = browser
        self.application = application
        self.window = window
        self.url = url
        self.domain = domain
        self.title = title
        self.isActive = isActive
    }
}
