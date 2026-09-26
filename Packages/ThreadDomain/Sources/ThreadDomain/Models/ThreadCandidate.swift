import Foundation

public struct ThreadID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// Carries only the local summary needed to consider an existing Thread.
public struct ThreadCandidate: Equatable, Codable, Sendable {
    public let id: ThreadID
    public let title: String
    public let lastActiveAt: Date
    public let resourceIDs: Set<ResourceID>
    public let projectDirectories: Set<String>

    public init(id: ThreadID, title: String, lastActiveAt: Date, resourceIDs: Set<ResourceID>, projectDirectories: Set<String> = []) {
        self.id = id
        self.title = title
        self.lastActiveAt = lastActiveAt
        self.resourceIDs = resourceIDs
        self.projectDirectories = projectDirectories
    }
}

public enum CandidateSignal: String, Codable, Sendable {
    case sameRepository, sameBranch, sameDirectory, sameFile, sameBrowserPage, sameTicket
    case sharedLiveResource, recentActivity, conflictingRepository, conflictingBranch
}

/// A deterministic relevance ranking, not an AI probability or authorization to mutate the graph.
public struct ScoredThreadCandidate: Equatable, Codable, Sendable {
    public let candidate: ThreadCandidate
    public let relevance: Double
    public let signals: [CandidateSignal]

    public init(candidate: ThreadCandidate, relevance: Double, signals: [CandidateSignal]) {
        self.candidate = candidate
        self.relevance = relevance
        self.signals = signals
    }
}
