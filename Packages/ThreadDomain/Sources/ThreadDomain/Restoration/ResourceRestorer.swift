import Foundation

public enum RestoreCapability: String, Codable, Sendable {
    case unavailable, activateOnly, resource, partial, full
}

public enum RestoreOutcome: String, Codable, Sendable {
    case restored, unavailable, failed, cancelled
}

public struct RestoreResult: Equatable, Codable, Sendable {
    public let resource: ResourceID
    public let capability: RestoreCapability
    public let outcome: RestoreOutcome
    public init(resource: ResourceID, capability: RestoreCapability, outcome: RestoreOutcome) {
        self.resource = resource; self.capability = capability; self.outcome = outcome
    }
}

public protocol ResourceRestorer: Sendable {
    func capability(for resource: Resource) async -> RestoreCapability
    func restore(_ resource: Resource) async throws -> RestoreResult
}

public struct ThreadRestoreReport: Codable, Sendable {
    public let thread: ThreadID
    public let results: [RestoreResult]
    public init(thread: ThreadID, results: [RestoreResult]) { self.thread = thread; self.results = results }
}

public enum ThreadRestoreError: Error, Codable, Sendable { case busy, unknownThread }

public protocol ThreadRestoring: Sendable {
    func restore(_ thread: ThreadID) async throws -> ThreadRestoreReport
}
