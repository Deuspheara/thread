import Foundation
import Testing
import ThreadDomain
import ThreadEngine

/// Replays pure stages with explicit deadlines; it does not replace ActivityEngine scheduler tests.
struct FixtureReplay {
    private var aggregator = EventAggregator()
    private var transitions = TransitionPolicy()
    private var review: (ThreadID, TransitionDecision)?
    private var checkpointRemoteCalls = 0
    private var identities: [ReplayFixture.Anchor: ThreadID] = [:]
    private let remoteUnavailable: Bool
    private let graph = ThreadGraphStore()
    private let decisions: ReplayDecisions
    private let inference: ActivityInference

    init(remoteUnavailable: Bool) {
        self.remoteUnavailable = remoteUnavailable
        let decisions = ReplayDecisions(remoteUnavailable: remoteUnavailable)
        self.decisions = decisions
        inference = ActivityInference(graph: graph, decisions: decisions)
    }

    mutating func run(_ fixture: ReplayFixture) async throws {
        for step in fixture.steps {
            let time = Date(timeIntervalSince1970: fixture.epoch).addingTimeInterval(step.at)
            try await advance(to: time)
            if let event = step.event {
                for context in aggregator.ingest(event, at: time) {
                    try await process(context, at: time, activeEvidence: false)
                }
                // Emissions preceding a newly arrived event cannot select active focus.
                transitions.cancelPending()
                review = nil
            }
            if let expected = step.expect { try await verify(expected) }
        }
        if !remoteUnavailable { #expect(await decisions.remoteCalls() == 0) }
    }

    private mutating func advance(to time: Date) async throws {
        while let deadline = nextDeadline, deadline <= time {
            for context in aggregator.advance(to: deadline) {
                try await process(context, at: deadline, activeEvidence: true)
            }
            if let evidence = review, let date = transitions.nextReviewAt, date <= deadline {
                transitions.consider(evidence.0, decision: evidence.1, at: deadline)
                review = nil
            }
        }
        for context in aggregator.advance(to: time) {
            try await process(context, at: time, activeEvidence: true)
        }
    }

    private var nextDeadline: Date? {
        [aggregator.nextDeadline, review == nil ? nil : transitions.nextReviewAt].compactMap { $0 }.min()
    }

    private mutating func process(_ context: ActivityContext, at time: Date, activeEvidence: Bool) async throws {
        let result = try await inference.process(context, active: transitions.active)
        guard activeEvidence else { return }
        if let id = result.thread {
            transitions.consider(id, decision: result.transition, at: time)
            review = transitions.nextReviewAt == nil ? nil : (id, result.transition)
        } else { transitions.cancelPending(); review = nil }
    }

    private mutating func verify(_ expected: ReplayFixture.Expectation) async throws {
        let details = await graph.details()
        #expect(details.count == expected.threads)
        if let anchor = expected.active {
            let active = try #require(transitions.active)
            let detail = try #require(details.first { $0.thread.id == active })
            #expect(anchor.matches(detail))
            if let original = identities[anchor] { #expect(active == original) }
            else { identities[anchor] = active }
        } else { #expect(transitions.active == nil) }
        let calls = await decisions.remoteCalls()
        if remoteUnavailable, expected.membership == .undetermined { #expect(calls > checkpointRemoteCalls) }
        checkpointRemoteCalls = calls
        if let membership = expected.membership {
            let result = try #require(await decisions.membership)
            switch membership {
            case .new: #expect(result.target == .newThread)
            case .existing: if case .existing = result.target {} else { Issue.record("Expected existing membership") }
            case .undetermined: #expect(result.target == .undetermined)
            }
        }
    }
}
