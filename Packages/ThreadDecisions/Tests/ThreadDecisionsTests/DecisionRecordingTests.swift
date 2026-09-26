import Foundation
import Testing
import ThreadDomain
import ThreadDecisions

struct DecisionRecordingTests {
    private let context = ActivityContext(startedAt: Date(timeIntervalSince1970: 10),
        endedAt: Date(timeIntervalSince1970: 20), resources: [])

    @Test func recordsSelectedOriginsWithoutRetainingActivityInputs() async throws {
        let capture = RecordCapture()
        let suppliedID = DecisionRecordID(rawValue: UUID())
        let local = FixedRecordedDecisions(membership: MembershipDecision(target: .newThread, confidence: 0.97, recordID: suppliedID))
        let ambiguous = FixedRecordedDecisions(membership: MembershipDecision(target: .undetermined, confidence: 0.5))
        let success = HybridDecisionEngine(local: local, remote: local, onDecision: { await capture.record($0) },
            uptime: { 10 }, onFallback: { _ in Issue.record("Unexpected fallback") })
        let localResult = try await success.classifyMembership(context: context, candidates: [])
        let remote = HybridDecisionEngine(local: ambiguous, remote: local, onDecision: { await capture.record($0) },
            uptime: { 10 }, onFallback: { _ in Issue.record("Unexpected fallback") })
        let remoteResult = try await remote.classifyMembership(context: context, candidates: [])
        let fallback = HybridDecisionEngine(local: ambiguous, remote: FixedRecordedDecisions(failure: .offline),
            onDecision: { await capture.record($0) }, uptime: { 10 }, onFallback: { _ in })
        let fallbackResult = try await fallback.classifyMembership(context: context, candidates: [])
        let records = await capture.records
        #expect(records.map(\.origin) == [.local, .remote, .localFallback])
        #expect(records.allSatisfy { $0.timestamp == context.endedAt && $0.elapsedMilliseconds == 0 && $0.isValid })
        #expect(records.map { $0.decision.kind } == [.membership, .membership, .membership])
        #expect([localResult, remoteResult, fallbackResult].map(\.recordID) == records.map { Optional($0.id) })
        #expect(!records.contains { $0.id == suppliedID })
        for record in records {
            if case .membership(let value) = record.decision { #expect(value.recordID == nil) }
        }
        let unrecorded = HybridDecisionEngine(local: local, onFallback: { _ in })
        #expect(try await unrecorded.classifyMembership(context: context, candidates: []).recordID == nil)
    }

    @Test func allOperationsRecordButCancelledInferenceDoesNot() async throws {
        let capture = RecordCapture()
        let local = FixedRecordedDecisions(membership: MembershipDecision(target: .newThread, confidence: 0.97))
        let hybrid = HybridDecisionEngine(local: local, onDecision: { await capture.record($0) }, onFallback: { _ in })
        _ = try await hybrid.detectTransition(context: context, active: nil,
            membership: MembershipDecision(target: .undetermined, confidence: 0))
        _ = try await hybrid.classifyPersistence(resource: .workingDirectory("/private/path"), context: context)
        let cancelled = HybridDecisionEngine(local: FixedRecordedDecisions(failure: .cancelled),
            onDecision: { await capture.record($0) }, onFallback: { _ in })
        await #expect(throws: CancellationError.self) { try await cancelled.classifyMembership(context: context, candidates: []) }
        #expect(await capture.records.map { $0.decision.kind } == [.transition, .persistence])
        let data = try JSONEncoder().encode(await capture.records)
        #expect(!String(decoding: data, as: UTF8.self).contains("/private/path"))
    }

    @Test func transitionReceiptsAreLocallyIssuedForLocalRemoteAndFallbackResults() async throws {
        let capture = RecordCapture(), suppliedID = DecisionRecordID(rawValue: UUID())
        let strong = FixedRecordedDecisions(transition: .init(shouldTransition: true, confidence: 0.99, recordID: suppliedID))
        let weak = FixedRecordedDecisions(transition: .init(shouldTransition: true, confidence: 0.5))
        let engines = [
            HybridDecisionEngine(local: strong, remote: strong, onDecision: { await capture.record($0) }, onFallback: { _ in }),
            HybridDecisionEngine(local: weak, remote: strong, onDecision: { await capture.record($0) }, onFallback: { _ in }),
            HybridDecisionEngine(local: weak, remote: FixedRecordedDecisions(failure: .offline),
                onDecision: { await capture.record($0) }, onFallback: { _ in })
        ]
        let membership = MembershipDecision(target: .existing(ThreadID(rawValue: UUID())), confidence: 0.99)
        var results: [TransitionDecision] = []
        for engine in engines { results.append(try await engine.detectTransition(context: context, active: nil, membership: membership)) }
        let records = await capture.records
        #expect(records.map(\.origin) == [.local, .remote, .localFallback])
        #expect(results.map(\.recordID) == records.map { Optional($0.id) })
        #expect(!records.contains { $0.id == suppliedID })
        for record in records {
            if case .transition(let value) = record.decision { #expect(value.recordID == nil) }
        }
        let unrecorded = HybridDecisionEngine(local: strong, onFallback: { _ in })
        #expect(try await unrecorded.detectTransition(context: context, active: nil, membership: membership).recordID == nil)
    }
}

private actor RecordCapture {
    var records: [DecisionRecord] = []
    func record(_ value: DecisionRecord) { records.append(value) }
}

private struct FixedRecordedDecisions: DecisionEngine {
    enum Failure: Error { case offline, cancelled }
    var membership = MembershipDecision(target: .undetermined, confidence: 0.5)
    var failure: Failure?
    var transition = TransitionDecision(shouldTransition: false, confidence: 1)
    func classifyMembership(context: ActivityContext, candidates: [ScoredThreadCandidate]) throws -> MembershipDecision {
        switch failure {
        case .offline: throw Failure.offline
        case .cancelled: throw CancellationError()
        case nil: return membership
        }
    }
    func detectTransition(context: ActivityContext, active: ThreadID?, membership: MembershipDecision) throws -> TransitionDecision {
        if let failure { throw failure }
        return transition
    }
    func classifyPersistence(resource: Resource, context: ActivityContext) -> PersistenceDecision {
        PersistenceDecision(disposition: .durable, confidence: 1)
    }
}
