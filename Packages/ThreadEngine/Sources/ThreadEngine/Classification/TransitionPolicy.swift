import Foundation
import ThreadDomain

/// Requires sustained stronger evidence and a cooldown before changing the active Thread.
public struct TransitionPolicy: Sendable {
    public private(set) var active: ThreadID?
    private let threshold: Double
    private let dwell: TimeInterval
    private let cooldown: TimeInterval
    private var switchedAt = Date.distantPast
    private var latestTime = Date.distantPast
    private var pending: (id: ThreadID, since: Date, last: Date)?

    /// The runtime can perform one delayed review while the same evidence remains current.
    public var nextReviewAt: Date? {
        guard let pending else { return nil }
        return max(pending.since.addingTimeInterval(dwell), switchedAt.addingTimeInterval(cooldown))
    }

    public init(threshold: Double = 0.96, dwell: TimeInterval = 3, cooldown: TimeInterval = 8) {
        precondition(threshold.isFinite && (0.92...1).contains(threshold))
        precondition(dwell.isFinite && dwell > 0 && cooldown.isFinite && cooldown >= dwell)
        self.threshold = threshold
        self.dwell = dwell
        self.cooldown = cooldown
    }

    @discardableResult
    public mutating func consider(_ target: ThreadID, decision: TransitionDecision, at time: Date) -> TransitionApplicationOutcome {
        guard time.timeIntervalSinceReferenceDate.isFinite, time >= latestTime else { return .staleTime }
        latestTime = time
        guard decision.shouldTransition else { pending = nil; return .declined }
        guard decision.confidence.isFinite,
              (threshold...1).contains(decision.confidence) else { pending = nil; return .confidenceRejected }
        if target == active { pending = nil; return .alreadyActive }
        if active == nil { select(target, at: time); return .activated }
        guard let evidence = pending, evidence.id == target,
              time.timeIntervalSince(evidence.last) <= 30 else {
            pending = (target, time, time)
            return .deferred
        }
        pending = (target, evidence.since, time)
        guard time.timeIntervalSince(evidence.since) >= dwell,
              time.timeIntervalSince(switchedAt) >= cooldown else { return .deferred }
        select(target, at: time)
        return .switched
    }

    public mutating func remove(_ target: ThreadID) {
        if active == target { active = nil }
        if pending?.id == target { pending = nil }
    }

    public mutating func cancelPending() { pending = nil }

    /// Explicit user selection bypasses inference while starting a fresh cooldown.
    public mutating func select(_ target: ThreadID, at time: Date) {
        guard time.timeIntervalSinceReferenceDate.isFinite, time >= latestTime else { return }
        active = target
        latestTime = time
        switchedAt = time
        pending = nil
    }
}
