import Foundation
import Testing
import ThreadDomain
@testable import ThreadEngine

struct ThreadGraphTests {
    let epoch = Date(timeIntervalSince1970: 100)
    func context(_ resources: [Resource], at offset: Double = 0) -> ActivityContext {
        let time = epoch.addingTimeInterval(offset)
        return ActivityContext(startedAt: time, endedAt: time, resources: resources.map {
            ResourceEvidence(resource: $0, firstSeen: time, lastSeen: time, source: ActivitySourceID(rawValue: "test"))
        })
    }

    @Test func sharedTerminalRetainsDifferentRestorationMetadataInEachThread() async throws {
        let graph = ThreadGraphStore()
        let session = TerminalSessionIdentity(rawValue: UUID())
        func terminal(_ cwd: String, _ sequence: UInt64) -> Resource {
            .terminal(TerminalContext(session: session, processIdentifier: 1, workingDirectory: cwd, terminalApplication: nil, sequence: sequence))
        }
        let a = try #require(await graph.apply(.automatic(.newThread), confidence: 0.97,
                                              context: context([.workingDirectory("/a"), terminal("/a", 1)])))
        let b = try #require(await graph.apply(.automatic(.newThread), confidence: 0.97,
                                              context: context([.workingDirectory("/b"), terminal("/b", 2)], at: 10)))
        let details = await graph.details()
        let previous = try #require(details.first { $0.thread.id == a })
        #expect(previous.resources.contains { $0.resource == terminal("/a", 1) })
        #expect(details.first?.thread.id == b)
    }

    @Test func provisionalEvidenceCannotConfirmItselfOrDowngradeExistingMembership() async throws {
        let graph = ThreadGraphStore()
        let a = try #require(await graph.apply(.automatic(.newThread), confidence: 0.97, context: context([.workingDirectory("/a")])))
        _ = try await graph.apply(.provisional(a), confidence: 0.75, context: context([.file(FileIdentity(path: "/a/draft")), .workingDirectory("/a")], at: 5))
        let candidates = await graph.candidates()
        #expect(candidates.first?.resourceIDs.contains(.file(FileIdentity(path: "/a/draft"))) == false)
        let detail = try #require(await graph.details().first)
        #expect(detail.thread.lastActiveAt == epoch)
        #expect(detail.resources.first { $0.resource.id == .workingDirectory("/a") }?.confidence == 0.97)
        _ = try await graph.apply(.automatic(.existing(a)), confidence: 0.95, context: context([.file(FileIdentity(path: "/a/draft"))], at: 6))
        #expect(await graph.candidates().first?.resourceIDs.contains(.file(FileIdentity(path: "/a/draft"))) == true)
    }

    @Test func rejectedUpdatesCannotReportAnAppliedAttachment() async throws {
        let graph = ThreadGraphStore()
        let resource = Resource.workingDirectory("/a")
        let receipt = DecisionRecordID(rawValue: UUID()), rejectedReceipt = DecisionRecordID(rawValue: UUID())
        let id = try #require(await graph.apply(.automatic(.newThread), confidence: 0.97,
            context: context([resource]), membershipRecordID: receipt))
        let before = await graph.checkpoint()
        let stale = try await graph.apply(.automatic(.existing(id)), confidence: 0.99,
            context: context([resource], at: -1), membershipRecordID: rejectedReceipt)
        #expect(stale == nil)
        #expect(await graph.checkpoint() == before)
        let weak = try await graph.apply(.provisional(id), confidence: 0.8,
            context: context([resource], at: 5), membershipRecordID: rejectedReceipt)
        #expect(weak == nil)
        #expect(await graph.checkpoint() == before)
        #expect(await graph.detail(id)?.resources.first?.membershipRecordID == receipt)
        _ = try await graph.apply(.automatic(.existing(id)), confidence: 0.99, context: context([resource], at: 6))
        #expect(await graph.detail(id)?.resources.first?.membershipRecordID == nil)
    }

    @Test func mixedEvidenceReportsOnlyWhenAtLeastOneAttachmentIsAccepted() async throws {
        let graph = ThreadGraphStore()
        let directory = Resource.workingDirectory("/a")
        let id = try #require(await graph.apply(.automatic(.newThread), confidence: 0.97, context: context([directory])))
        let file = Resource.file(FileIdentity(path: "/a/draft"))
        let target = try await graph.apply(.provisional(id), confidence: 0.8, context: context([directory, file], at: 5))
        #expect(target == id)
        let detail = try #require(await graph.detail(id))
        #expect(detail.resources.first { $0.resource.id == directory.id }?.confidence == 0.97)
        #expect(detail.resources.first { $0.resource.id == file.id }?.status == .provisional)
        #expect(detail.thread.lastActiveAt == epoch)
    }

    @Test func userReassignmentBlocksReattachmentAndEmptyThreadCreation() async throws {
        let graph = ThreadGraphStore()
        let a = try #require(await graph.apply(.automatic(.newThread), confidence: 0.97, context: context([.workingDirectory("/a")])))
        let b = try #require(await graph.apply(.automatic(.newThread), confidence: 0.97, context: context([.workingDirectory("/b")], at: 1)))
        let resource = Resource.file(FileIdentity(path: "/shared/design"))
        let observation = context([resource], at: 2)
        let receipt = DecisionRecordID(rawValue: UUID())
        _ = try await graph.apply(.automatic(.existing(a)), confidence: 0.99, context: observation, membershipRecordID: receipt)
        try await graph.reassign(observation.resources[0], to: b)
        let rejected = try await graph.apply(.automatic(.existing(a)), confidence: 1, context: context([resource], at: 3))
        #expect(rejected == nil)
        let empty = try await graph.apply(.automatic(.newThread), confidence: 1, context: context([resource], at: 4))
        #expect(empty == nil)
        let details = await graph.details()
        #expect(details.count == 2)
        #expect(details.first { $0.thread.id == a }?.resources.contains { $0.resource.id == resource.id } == false)
        #expect(details.first { $0.thread.id == b }?.resources.first { $0.resource.id == resource.id }?.userCorrected == true)
        _ = try await graph.apply(.automatic(.existing(b)), confidence: 1, context: context([resource], at: 5), membershipRecordID: receipt)
        #expect(await graph.detail(b)?.resources.first { $0.resource.id == resource.id }?.membershipRecordID == nil)
    }

    @Test func checkpointHydrationPreservesCorrectionsAndRefusesToReplaceLiveGraph() async throws {
        let graph = ThreadGraphStore()
        let resource = Resource.workingDirectory("/a")
        let observation = context([resource])
        let id = try #require(await graph.apply(.automatic(.newThread), confidence: 0.97, context: observation))
        try await graph.reassign(observation.resources[0], to: id)
        let checkpoint = await graph.checkpoint()
        let restored = ThreadGraphStore()
        try await restored.restore(checkpoint)
        #expect(await restored.checkpoint() == checkpoint)
        let rejected = try await restored.apply(.automatic(.newThread), confidence: 1, context: observation)
        #expect(rejected == nil)
        await #expect(throws: ThreadGraphError.graphNotEmpty) { try await restored.restore(checkpoint) }
    }

    @Test func archivedThreadsAreExcludedAndRenamesSurviveInference() async throws {
        let graph = ThreadGraphStore()
        let observation = context([.workingDirectory("/a")])
        let id = try #require(await graph.apply(.automatic(.newThread), confidence: 0.97, context: observation))
        try await graph.rename(id, title: "My work")
        _ = try await graph.apply(.automatic(.existing(id)), confidence: 0.96, context: context([.workingDirectory("/a")], at: 1))
        #expect(await graph.details().first?.thread.title == "My work")
        try await graph.archive(id, archived: true)
        #expect(await graph.candidates().isEmpty)
        await #expect(throws: ThreadGraphError.self) {
            try await graph.apply(.automatic(.existing(id)), confidence: 1, context: observation)
        }
    }

    @Test func mergeAndSplitDoNotInventInferenceForUserChangedOwnership() async throws {
        let graph = ThreadGraphStore()
        let shared = Resource.file(FileIdentity(path: "/shared")), unique = Resource.file(FileIdentity(path: "/b/unique"))
        let aReceipt = DecisionRecordID(rawValue: UUID()), bReceipt = DecisionRecordID(rawValue: UUID())
        let a = try #require(await graph.apply(.automatic(.newThread), confidence: 0.99,
            context: context([.workingDirectory("/a"), shared]), membershipRecordID: aReceipt))
        let b = try #require(await graph.apply(.automatic(.newThread), confidence: 0.99,
            context: context([.workingDirectory("/b"), shared, unique], at: 1), membershipRecordID: bReceipt))
        try await graph.merge(a, into: b)
        let combined = try #require(await graph.detail(b))
        #expect(combined.resources.first { $0.resource.id == .workingDirectory("/a") }?.membershipRecordID == nil)
        #expect(combined.resources.first { $0.resource.id == shared.id }?.membershipRecordID == nil)
        #expect(combined.resources.first { $0.resource.id == unique.id }?.membershipRecordID == bReceipt)
        let c = ThreadID(rawValue: UUID())
        try await graph.split(b, into: c, title: "Split", resources: [unique.id], at: epoch.addingTimeInterval(2))
        let selected = try #require(await graph.detail(c)?.resources.first)
        #expect(selected.userCorrected && selected.membershipRecordID == nil)
        let hydrated = ThreadGraphStore()
        try await hydrated.restore(graph.checkpoint())
        #expect(await hydrated.checkpoint() == graph.checkpoint())
    }
}
