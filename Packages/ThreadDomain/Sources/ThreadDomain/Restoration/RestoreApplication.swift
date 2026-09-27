import Foundation

/// Records the intended document application on a Thread relationship, independently of file identity.
public struct RestoreApplication: Equatable, Codable, Sendable {
    public enum Origin: String, Codable, Sendable { case observed, explicit, fallback }
    public let identity: ApplicationIdentity
    public let name: String
    public let origin: Origin
    public init(identity: ApplicationIdentity, name: String, origin: Origin) {
        self.identity = identity; self.name = name; self.origin = origin
    }
    public var isValid: Bool {
        let bundle = identity.bundleIdentifier
        return !bundle.isEmpty && bundle.utf8.count <= 256 && !bundle.contains(where: { $0.isWhitespace || $0.isNewline })
            && !bundle.utf8.contains(0) && !name.isEmpty && name.count <= 160
    }
}

/// Carries one planned operation and its per-Thread document application preference.
public struct RestoreTarget: Equatable, Codable, Sendable {
    public let resource: Resource
    public let application: RestoreApplication?
    public let isProject: Bool
    public init(resource: Resource, application: RestoreApplication? = nil, isProject: Bool = false) {
        self.resource = resource; self.application = application; self.isProject = isProject
    }
}
