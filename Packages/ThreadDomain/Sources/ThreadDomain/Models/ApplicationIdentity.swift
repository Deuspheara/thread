import Foundation

/// Identifies an installed application independently of its running process.
public struct ApplicationIdentity: Hashable, Codable, Sendable {
    public let bundleIdentifier: String

    public init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }
}

/// Captures an application's running instance without retaining platform objects.
public struct ApplicationContext: Equatable, Codable, Sendable {
    public let identity: ApplicationIdentity
    public let name: String
    public let processIdentifier: Int32
    public let launchDate: Date?

    public init(identity: ApplicationIdentity, name: String, processIdentifier: Int32, launchDate: Date? = nil) {
        self.identity = identity
        self.name = name
        self.processIdentifier = processIdentifier
        self.launchDate = launchDate
    }

    public func isSameInstance(as other: ApplicationContext) -> Bool {
        identity == other.identity && processIdentifier == other.processIdentifier && launchDate == other.launchDate
    }
}
