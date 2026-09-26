import Foundation

/// Retains bounded temporal evidence for one resource without retaining raw event payloads.
public struct ResourceEvidence: Equatable, Codable, Sendable {
    public let resource: Resource
    public let firstSeen: Date
    public let lastSeen: Date
    public let source: ActivitySourceID

    public init(resource: Resource, firstSeen: Date, lastSeen: Date, source: ActivitySourceID) {
        self.resource = resource
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.source = source
    }
}

/// Supplies recently observed resources to local candidate selection and inference.
public struct ActivityContext: Equatable, Codable, Sendable {
    public let startedAt: Date
    public let endedAt: Date
    public let resources: [ResourceEvidence]

    public init(startedAt: Date, endedAt: Date, resources: [ResourceEvidence]) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.resources = resources
    }
}
