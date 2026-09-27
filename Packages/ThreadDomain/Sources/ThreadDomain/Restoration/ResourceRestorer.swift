import Foundation

public enum RestoreCapability: String, Codable, Sendable {
    case unavailable, activateOnly, resource, partial, full
}

public enum RestoreOutcome: String, Codable, Sendable {
    case restored, unavailable, failed, cancelled, unknown
}

public struct RestoreResult: Equatable, Codable, Sendable {
    public let resource: ResourceID
    public let capability: RestoreCapability
    public let outcome: RestoreOutcome
    public let application: RestoreApplication?
    public let explanation: String?
    public init(resource: ResourceID, capability: RestoreCapability, outcome: RestoreOutcome, application: RestoreApplication? = nil, explanation: String? = nil) {
        self.resource = resource; self.capability = capability; self.outcome = outcome
        self.application = application; self.explanation = explanation
    }
}

public protocol ResourceRestorer: Sendable {
    func capability(for resource: Resource) async -> RestoreCapability
    func restore(_ resource: Resource) async throws -> RestoreResult
    func capability(for target: RestoreTarget) async -> RestoreCapability
    func restore(_ target: RestoreTarget) async throws -> RestoreResult
}

public extension ResourceRestorer {
    func capability(for target: RestoreTarget) async -> RestoreCapability {
        guard target.application == nil else { return .unavailable }
        return await capability(for: target.resource)
    }
    func restore(_ target: RestoreTarget) async throws -> RestoreResult {
        guard target.application == nil else {
            return RestoreResult(resource: target.resource.id, capability: .unavailable, outcome: .unavailable)
        }
        return try await restore(target.resource)
    }
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
