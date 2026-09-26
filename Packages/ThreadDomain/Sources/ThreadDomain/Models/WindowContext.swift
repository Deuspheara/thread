import Foundation

/// Identifies a window during an observation session, without exposing a platform window handle.
public struct WindowIdentity: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Describes a window in global screen coordinates, with an origin at the primary screen's top left.
public struct WindowFrame: Equatable, Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Carries the permitted metadata of a focused window.
public struct WindowContext: Equatable, Codable, Sendable {
    public let identity: WindowIdentity
    public let application: ApplicationContext
    public let title: String?
    public let frame: WindowFrame?
    public let document: FileIdentity?

    public init(identity: WindowIdentity, application: ApplicationContext, title: String?, frame: WindowFrame?, document: FileIdentity? = nil) {
        self.identity = identity
        self.application = application
        self.title = title
        self.frame = frame
        self.document = document
    }
}
