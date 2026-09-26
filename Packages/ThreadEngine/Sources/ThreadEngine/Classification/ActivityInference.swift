import ThreadDomain
import Foundation

/// Reports applied membership and transition evidence without selecting the active Thread itself.
public struct InferenceOutcome: Sendable {
    public let thread: ThreadID?
    public let authorization: MembershipAuthorization
    public let transition: TransitionDecision
}

/// Runs one context through candidate selection, inference, authorization, and atomic graph mutation.
public struct ActivityInference: Sendable {
    private let graph: ThreadGraphStore
    private let decisions: any DecisionEngine
    private let selector: ThreadCandidateSelector
    private let policy: DecisionPolicy
    private let onApplication: (@Sendable (MembershipApplicationRecord) async -> Void)?

    public init(graph: ThreadGraphStore, decisions: any DecisionEngine,
                selector: ThreadCandidateSelector = ThreadCandidateSelector(), policy: DecisionPolicy = DecisionPolicy(),
                onApplication: (@Sendable (MembershipApplicationRecord) async -> Void)? = nil) {
        self.graph = graph
        self.decisions = decisions
        self.selector = selector
        self.policy = policy
        self.onApplication = onApplication
    }

    /// The runtime serializes contexts; this operation does not start unstructured tasks.
    public func process(_ context: ActivityContext, active: ThreadID?) async throws -> InferenceOutcome {
        let candidates = selector.select(context: context, from: await graph.candidates())
        let membership = try await decisions.classifyMembership(context: context, candidates: candidates)
        try Task.checkCancellation()
        let authorization = policy.authorize(membership, candidates: Set(candidates.map { $0.candidate.id }))
        guard authorization != .wait else {
            await record(.waiting, thread: nil, decision: membership.recordID, at: context.endedAt)
            return InferenceOutcome(thread: nil, authorization: .wait,
                                    transition: TransitionDecision(shouldTransition: false, confidence: 0))
        }
        let classified = try await ResourcePersistenceClassifier().classify(context, decisions: decisions)
        let thread = try await graph.apply(authorization, confidence: membership.confidence,
            context: classified.context, persistence: classified.persistence, membershipRecordID: membership.recordID)
        let outcome: MembershipApplicationOutcome
        if thread == nil { outcome = .noAttachment }
        else if case .provisional = authorization { outcome = .provisionalAttachment }
        else { outcome = .confirmedAttachment }
        await record(outcome, thread: thread, decision: membership.recordID, at: context.endedAt)
        guard let thread, case .automatic = authorization else {
            return InferenceOutcome(thread: thread, authorization: authorization,
                                    transition: TransitionDecision(shouldTransition: false, confidence: 0))
        }
        try Task.checkCancellation()
        let resolved = MembershipDecision(target: .existing(thread), confidence: membership.confidence)
        let transition = try await decisions.detectTransition(context: context, active: active, membership: resolved)
        return InferenceOutcome(thread: thread, authorization: authorization, transition: transition)
    }

    private func record(_ outcome: MembershipApplicationOutcome, thread: ThreadID?, decision: DecisionRecordID?, at time: Date) async {
        guard let onApplication else { return }
        await onApplication(MembershipApplicationRecord(id: MembershipApplicationID(rawValue: UUID()),
            timestamp: time, outcome: outcome, thread: thread, decisionRecordID: decision))
    }
}
