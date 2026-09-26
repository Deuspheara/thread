import Foundation
import ThreadDomain

/// Resolves clear local matches and abstains when evidence is ambiguous or too generic.
public struct HeuristicDecisionEngine: DecisionEngine {
    public init() {}

    public func classifyMembership(context: ActivityContext, candidates: [ScoredThreadCandidate]) async throws -> MembershipDecision {
        let ranked = candidates.sorted { $0.relevance > $1.relevance }
        if let best = ranked.first, best.relevance >= 0.72 {
            let confidence = matchConfidence(best, context: context)
            if let runnerUp = ranked.dropFirst().first, best.relevance - runnerUp.relevance < 0.08 {
                return MembershipDecision(target: .undetermined, confidence: 0.5)
            }
            return MembershipDecision(target: .existing(best.candidate.id), confidence: confidence)
        }
        return newMembership(context)
    }

    public func detectTransition(context: ActivityContext, active: ThreadID?, membership: MembershipDecision) async throws -> TransitionDecision {
        guard case .existing(let target) = membership.target else {
            return TransitionDecision(shouldTransition: false, confidence: 0)
        }
        let strongAnchor = context.resources.contains {
            switch $0.resource {
            case .branch, .repository, .workingDirectory, .file: true
            case .browserPage: $0.lastSeen.timeIntervalSince($0.firstSeen) >= 20
            default: false
            }
        }
        return TransitionDecision(shouldTransition: target != active && strongAnchor, confidence: membership.confidence)
    }

    public func classifyPersistence(resource: Resource, context: ActivityContext) async throws -> PersistenceDecision {
        switch resource {
        case .terminal: return PersistenceDecision(disposition: .sessionOnly, confidence: 1)
        case .window(let window):
            let restorable = window.title?.isEmpty == false && window.application.launchDate != nil
            return PersistenceDecision(disposition: restorable ? .durable : .sessionOnly, confidence: 0.98)
        default: return PersistenceDecision(disposition: .durable, confidence: 0.98)
        }
    }

    private func matchConfidence(_ candidate: ScoredThreadCandidate, context: ActivityContext) -> Double {
        let signals = candidate.signals
        guard !signals.contains(.conflictingRepository), !signals.contains(.conflictingBranch) else { return 0.4 }
        if signals.contains(.sameBranch) { return 0.98 }
        if signals.contains(.sameDirectory) { return 0.96 }
        if signals.contains(.sameFile) { return 0.97 }
        if signals.contains(.sameRepository) { return 0.84 }
        if signals.contains(.sameBrowserPage) {
            let sustained = context.resources.contains {
                $0.resource.kind == .browserPage && candidate.candidate.resourceIDs.contains($0.resource.id)
                    && $0.lastSeen.timeIntervalSince($0.firstSeen) >= 20
            }
            return sustained ? 0.97 : 0.76
        }
        if signals.contains(.sameTicket) { return 0.76 }
        return 0.5
    }

    private func newMembership(_ context: ActivityContext) -> MembershipDecision {
        if context.resources.contains(where: { if case .repository = $0.resource { return true }; return false }) {
            return MembershipDecision(target: .newThread, confidence: 0.97)
        }
        let durableEvidence = context.resources.contains { evidence in
            switch evidence.resource {
            case .file: return true
            case .browserPage, .workingDirectory: return evidence.lastSeen.timeIntervalSince(evidence.firstSeen) >= 20
            default: return false
            }
        }
        return MembershipDecision(target: durableEvidence ? .newThread : .undetermined, confidence: durableEvidence ? 0.97 : 0)
    }
}
