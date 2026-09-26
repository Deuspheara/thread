import Foundation
import ThreadDomain

/// Ranks bounded local candidates without letting shared apps or recency outweigh project conflicts.
public struct ThreadCandidateSelector: Sendable {
    public let limit: Int
    public init(limit: Int = 8) {
        precondition((1...8).contains(limit))
        self.limit = limit
    }

    /// NEW_THREAD remains an independent decision alternative, never an invented historical candidate.
    public func select(context: ActivityContext, from candidates: [ThreadCandidate]) -> [ScoredThreadCandidate] {
        let identities = Set(context.resources.map { $0.resource.id })
        return candidates.map { score($0, identities: identities, at: context.endedAt) }
            .filter { $0.relevance >= 0.15 }
            .sorted {
                if $0.relevance != $1.relevance { return $0.relevance > $1.relevance }
                if $0.candidate.lastActiveAt != $1.candidate.lastActiveAt { return $0.candidate.lastActiveAt > $1.candidate.lastActiveAt }
                return $0.candidate.id.rawValue.uuidString < $1.candidate.id.rawValue.uuidString
            }
            .prefix(limit).map { $0 }
    }

    private func score(_ candidate: ThreadCandidate, identities: Set<ResourceID>, at time: Date) -> ScoredThreadCandidate {
        let common = identities.intersection(candidate.resourceIDs)
        var signals: [CandidateSignal] = []
        var relevance = 0.0
        for (signal, weight) in matchedSignals(common) {
            signals.append(signal)
            relevance = max(relevance, weight)
        }
        if ProjectDirectoryMatch().matches(identities, candidate: candidate) {
            if !signals.contains(.sameDirectory) { signals.append(.sameDirectory) }
            relevance = max(relevance, 0.93)
        }
        if TicketIdentifierMatch().matches(identities, known: candidate.resourceIDs) {
            signals.append(.sameTicket)
            relevance = max(relevance, 0.74)
        }
        let currentRepositories = repositories(in: identities)
        let knownRepositories = repositories(in: candidate.resourceIDs)
        if !currentRepositories.isEmpty, !knownRepositories.isEmpty, currentRepositories.isDisjoint(with: knownRepositories) {
            signals.append(.conflictingRepository)
            relevance = min(relevance, 0.20)
        }
        if conflictsWithBranch(identities, known: candidate.resourceIDs) {
            signals.append(.conflictingBranch)
            relevance = min(relevance, 0.40)
        }
        let age = time.timeIntervalSince(candidate.lastActiveAt)
        if relevance > 0, age >= 0, age <= 300 {
            signals.append(.recentActivity)
            relevance = min(1, relevance + 0.02)
        }
        return ScoredThreadCandidate(candidate: candidate, relevance: relevance, signals: signals)
    }

    private func matchedSignals(_ common: Set<ResourceID>) -> [(CandidateSignal, Double)] {
        var matches: [CandidateSignal: Double] = [:]
        for identity in common {
            switch identity {
            case .branch: matches[.sameBranch] = 0.96
            case .repository: matches[.sameRepository] = 0.84
            case .workingDirectory: matches[.sameDirectory] = 0.93
            case .file: matches[.sameFile] = 0.90
            case .browserPage: matches[.sameBrowserPage] = 0.74
            case .window, .terminal: matches[.sharedLiveResource] = 0.30
            case .application: break // The same editor/browser is not evidence of the same work.
            }
        }
        return matches.sorted { $0.key.rawValue < $1.key.rawValue }.map { ($0.key, $0.value) }
    }

    private func repositories(in identities: Set<ResourceID>) -> Set<RepositoryIdentity> {
        Set(identities.compactMap {
            switch $0 {
            case .repository(let repository), .branch(let repository, _): repository
            default: nil
            }
        })
    }

    private func conflictsWithBranch(_ current: Set<ResourceID>, known: Set<ResourceID>) -> Bool {
        for identity in current {
            guard case .branch(let repository, _) = identity, !known.contains(identity) else { continue }
            if known.contains(where: {
                if case .branch(let other, _) = $0 { return other == repository }
                return false
            }) { return true }
        }
        return false
    }
}
