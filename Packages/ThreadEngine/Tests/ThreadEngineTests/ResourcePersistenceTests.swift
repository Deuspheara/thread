import Foundation
import Testing
import ThreadDomain
@testable import ThreadEngine

struct ResourcePersistenceTests {
    private let now = Date(timeIntervalSince1970: 100)
    private func context(_ resources: [Resource]) -> ActivityContext {
        ActivityContext(startedAt: now, endedAt: now, resources: resources.map {
            ResourceEvidence(resource: $0, firstSeen: now, lastSeen: now, source: ActivitySourceID(rawValue: "test"))
        })
    }

    @Test func confidencePolicyRejectsUncertainAndInvalidDurability() {
        let policy = ResourcePersistencePolicy()
        for value in [0.919, -0.1, 1.1, Double.nan, .infinity] {
            #expect(policy.authorize(PersistenceDecision(disposition: .durable, confidence: value)) == .sessionOnly)
            #expect(policy.authorize(PersistenceDecision(disposition: .discard, confidence: value)) == .sessionOnly)
        }
        for disposition in [PersistenceDisposition.durable, .sessionOnly, .discard] {
            #expect(policy.authorize(PersistenceDecision(disposition: disposition, confidence: 0.92)) == disposition)
        }
    }

    @Test func liveInferenceHonorsRetentionInCheckpointsSnapshotsAndHydration() async throws {
        let graph = ThreadGraphStore()
        let directory = Resource.workingDirectory("/work")
        let session = Resource.file(FileIdentity(path: "/work/session.swift"))
        let discarded = Resource.file(FileIdentity(path: "/work/discard.swift"))
        let decisions = RetentionDecisions(dispositions: [session.id: .sessionOnly, discarded.id: .discard])
        let outcome = try await ActivityInference(graph: graph, decisions: decisions)
            .process(context([directory, session, discarded]), active: nil)
        let id = try #require(outcome.thread)
        let live = try #require(await graph.detail(id))
        #expect(Set(live.resources.map { $0.resource.id }) == [directory.id, session.id])
        #expect(await decisions.calls == 3)
        let checkpoint = await graph.checkpoint()
        #expect(checkpoint.threads.first?.resources.map { $0.resource.id } == [directory.id])
        let snapshot = try #require(SnapshotBuilder().build(live, at: now))
        #expect(snapshot.resources.map { $0.resource.id } == [directory.id])
        let hydrated = ThreadGraphStore()
        try await hydrated.restore(checkpoint)
        #expect(await hydrated.detail(id)?.resources.map { $0.resource.id } == [directory.id])
    }

    @Test func discardedAnchorCannotCreateAnEmptyThreadAndFailureCannotPartiallyMutate() async throws {
        let resource = Resource.workingDirectory("/work")
        let graph = ThreadGraphStore()
        let inference = ActivityInference(graph: graph, decisions: RetentionDecisions(dispositions: [resource.id: .discard]))
        #expect(try await inference.process(context([resource]), active: nil).thread == nil)
        #expect(await graph.details().isEmpty)
        let cancelled = ActivityInference(graph: graph, decisions: RetentionDecisions(cancelAfter: 1))
        await #expect(throws: CancellationError.self) {
            try await cancelled.process(context([resource, .file(FileIdentity(path: "/work/file"))]), active: nil)
        }
        #expect(await graph.details().isEmpty)
    }

    @Test func explicitCorrectionMakesSessionResourceDurableAndOverridesLaterDiscard() async throws {
        let graph = ThreadGraphStore()
        let resource = Resource.workingDirectory("/work")
        let observation = context([resource])
        let id = try #require(await graph.apply(.automatic(.newThread), confidence: 1,
            context: observation, persistence: [resource.id: .sessionOnly]))
        #expect(await graph.checkpoint().threads.first?.resources.isEmpty == true)
        try await graph.reassign(observation.resources[0], to: id)
        _ = try await graph.apply(.automatic(.existing(id)), confidence: 1,
            context: observation, persistence: [resource.id: .discard])
        let saved = await graph.checkpoint()
        #expect(saved.threads.first?.resources.first?.persistence == .durable)
        #expect(saved.threads.first?.resources.first?.userCorrected == true)
        try ThreadGraphValidation.validate(saved)
    }

    @Test func confirmedDiscardRemovesAnInferredEdgeButProvisionalDiscardCannot() async throws {
        let graph = ThreadGraphStore()
        let directory = Resource.workingDirectory("/work")
        let resource = Resource.file(FileIdentity(path: "/work/temporary.swift"))
        let observation = context([directory, resource])
        let id = try #require(await graph.apply(.automatic(.newThread), confidence: 1, context: observation))
        _ = try await graph.apply(.provisional(id), confidence: 0.75, context: observation, persistence: [resource.id: .discard])
        #expect(await graph.detail(id)?.resources.contains { $0.resource.id == resource.id } == true)
        _ = try await graph.apply(.automatic(.existing(id)), confidence: 1, context: observation, persistence: [resource.id: .discard])
        #expect(await graph.detail(id)?.resources.contains { $0.resource.id == resource.id } == false)
        #expect(await graph.checkpoint().threads.first?.resources.map { $0.resource.id } == [directory.id])
    }

    @Test func uncertainRetentionCanBecomeDurableAndProvisionalEvidenceCannotDowngradeIt() async throws {
        let graph = ThreadGraphStore()
        let resource = Resource.workingDirectory("/work")
        let observation = context([resource])
        let id = try #require(await graph.apply(.automatic(.newThread), confidence: 1,
            context: observation, persistence: [resource.id: .sessionOnly]))
        _ = try await graph.apply(.automatic(.existing(id)), confidence: 1, context: observation, persistence: [resource.id: .durable])
        _ = try await graph.apply(.provisional(id), confidence: 0.75, context: observation, persistence: [resource.id: .sessionOnly])
        #expect(await graph.checkpoint().threads.first?.resources.first?.persistence == .durable)
    }

    @Test func pinsAndStaleEvidenceCannotLoseDurableRetention() async throws {
        let resource = Resource.workingDirectory("/work")
        let thread = ThreadDomain.Thread(id: ThreadID(rawValue: UUID()), title: "Work", createdAt: now, lastActiveAt: now)
        var edge = ThreadResource(resource: resource, confidence: 1, firstSeen: now, lastSeen: now,
            source: ActivitySourceID(rawValue: "test"), status: .confirmed, pinned: true)
        let pinned = ThreadGraphStore()
        try await pinned.restore(ThreadGraphState(threads: [ThreadDetail(thread: thread, resources: [edge])], corrections: []))
        for disposition in [PersistenceDisposition.discard, .sessionOnly] {
            _ = try await pinned.apply(.automatic(.existing(thread.id)), confidence: 1,
                context: context([resource]), persistence: [resource.id: disposition])
        }
        #expect(await pinned.checkpoint().threads.first?.resources.first?.persistence == .durable)
        edge.pinned = false
        let stale = ThreadGraphStore()
        try await stale.restore(ThreadGraphState(threads: [ThreadDetail(thread: thread, resources: [edge])], corrections: []))
        let earlier = now.addingTimeInterval(-1)
        let observation = ActivityContext(startedAt: earlier, endedAt: earlier, resources: [
            ResourceEvidence(resource: resource, firstSeen: earlier, lastSeen: earlier, source: edge.source)])
        _ = try await stale.apply(.automatic(.existing(thread.id)), confidence: 1,
            context: observation, persistence: [resource.id: .discard])
        #expect(await stale.checkpoint().threads.first?.resources.first?.persistence == .durable)
    }

    @Test func classifierBoundsAndDeduplicatesBeforeInference() async throws {
        let resources = (0..<200).map { Resource.file(FileIdentity(path: "/work/File\($0).swift")) }
        let decisions = RetentionDecisions()
        let classified = try await ResourcePersistenceClassifier().classify(context(resources + resources), decisions: decisions)
        #expect(classified.context.resources.count == 128)
        #expect(classified.persistence.count == 128)
        #expect(await decisions.calls == 128)
    }

    @Test func legacyRelationshipPayloadRemainsReadableAndNonDurableCheckpointsAreRejected() throws {
        let observation = context([.workingDirectory("/work")]).resources[0]
        let edge = ThreadResource(resource: observation.resource, confidence: 1, firstSeen: now, lastSeen: now,
            source: observation.source, status: .confirmed)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = String(decoding: try encoder.encode(edge), as: UTF8.self)
        #expect(encoded.contains("\"persistence\":\"durable\","))
        let legacy = encoded.replacingOccurrences(of: "\"persistence\":\"durable\",", with: "")
        #expect(try JSONDecoder().decode(ThreadResource.self, from: Data(legacy.utf8)).persistence == .durable)
        var session = edge
        session.persistence = .sessionOnly
        let thread = ThreadDomain.Thread(id: ThreadID(rawValue: UUID()), title: "Work", createdAt: now, lastActiveAt: now)
        #expect(throws: ThreadGraphValidationError.self) {
            try ThreadGraphValidation.validate(ThreadGraphState(threads: [ThreadDetail(thread: thread, resources: [session])], corrections: []))
        }
    }
}

private actor RetentionDecisions: DecisionEngine {
    var calls = 0
    private let dispositions: [ResourceID: PersistenceDisposition]
    private let cancelAfter: Int?
    init(dispositions: [ResourceID: PersistenceDisposition] = [:], cancelAfter: Int? = nil) {
        self.dispositions = dispositions
        self.cancelAfter = cancelAfter
    }
    func classifyMembership(context: ActivityContext, candidates: [ScoredThreadCandidate]) -> MembershipDecision {
        MembershipDecision(target: .newThread, confidence: 1)
    }
    func detectTransition(context: ActivityContext, active: ThreadID?, membership: MembershipDecision) -> TransitionDecision {
        TransitionDecision(shouldTransition: false, confidence: 1)
    }
    func classifyPersistence(resource: Resource, context: ActivityContext) throws -> PersistenceDecision {
        if calls == cancelAfter { throw CancellationError() }
        calls += 1
        return PersistenceDecision(disposition: dispositions[resource.id] ?? .durable, confidence: 1)
    }
}
