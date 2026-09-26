import Foundation
import Testing
import ThreadDomain
@testable import ThreadEngine

struct DecisionPolicyTests {
    @Test func thresholdsRejectInvalidAndUnselectedTargets() {
        let id = ThreadID(rawValue: UUID())
        let policy = DecisionPolicy()
        let allowed: Set<ThreadID> = [id]
        #expect(policy.authorize(MembershipDecision(target: .existing(id), confidence: 0.92), candidates: allowed) == .automatic(.existing(id)))
        #expect(policy.authorize(MembershipDecision(target: .existing(id), confidence: 0.72), candidates: allowed) == .provisional(id))
        #expect(policy.authorize(MembershipDecision(target: .newThread, confidence: 0.91), candidates: []) == .wait)
        #expect(policy.authorize(MembershipDecision(target: .existing(id), confidence: 1), candidates: []) == .wait)
        for confidence in [Double.nan, Double.infinity, -0.1, 1.01, 0.719] {
            #expect(policy.authorize(MembershipDecision(target: .existing(id), confidence: confidence), candidates: allowed) == .wait)
        }
    }

    @Test func transitionNeedsSustainedEvidenceAndCooldownAndResistsRapidAlternation() {
        let a = ThreadID(rawValue: UUID()), b = ThreadID(rawValue: UUID())
        let epoch = Date(timeIntervalSince1970: 100)
        let certain = TransitionDecision(shouldTransition: true, confidence: 0.98)
        var policy = TransitionPolicy()
        let outcome1 = policy.consider(a, decision: certain, at: epoch)
        #expect(outcome1 == .activated)
        let outcome2 = policy.consider(b, decision: certain, at: epoch.addingTimeInterval(1))
        #expect(outcome2 == .deferred)
        let outcome3 = policy.consider(b, decision: certain, at: epoch.addingTimeInterval(4))
        #expect(outcome3 == .deferred)
        let outcome4 = policy.consider(a, decision: certain, at: epoch.addingTimeInterval(5))
        #expect(outcome4 == .alreadyActive)
        let outcome5 = policy.consider(b, decision: certain, at: epoch.addingTimeInterval(8))
        #expect(outcome5 == .deferred)
        let outcome6 = policy.consider(b, decision: certain, at: epoch.addingTimeInterval(11))
        #expect(outcome6 == .switched)
        #expect(policy.active == b)
        let outcome7 = policy.consider(a, decision: certain, at: epoch.addingTimeInterval(10))
        #expect(outcome7 == .staleTime)
        #expect(policy.active == b)
    }

    @Test func weakAndStaleEvidenceCannotAccumulateIntoTransition() {
        let a = ThreadID(rawValue: UUID()), b = ThreadID(rawValue: UUID())
        let epoch = Date(timeIntervalSince1970: 100)
        let certain = TransitionDecision(shouldTransition: true, confidence: 1)
        var policy = TransitionPolicy()
        policy.select(a, at: epoch)
        let outcome8 = policy.consider(b, decision: certain, at: epoch.addingTimeInterval(10))
        #expect(outcome8 == .deferred)
        let outcome9 = policy.consider(b, decision: TransitionDecision(shouldTransition: true, confidence: 0.95), at: epoch.addingTimeInterval(12))
        #expect(outcome9 == .confidenceRejected)
        let outcome10 = policy.consider(b, decision: certain, at: epoch.addingTimeInterval(14))
        #expect(outcome10 == .deferred)
        let outcome11 = policy.consider(b, decision: certain, at: epoch.addingTimeInterval(50))
        #expect(outcome11 == .deferred)
        #expect(policy.active == a)
    }
}
