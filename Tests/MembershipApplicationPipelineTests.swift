import Foundation
import Testing
import ThreadDomain
import ThreadEngine
import ThreadPersistence

struct MembershipApplicationPipelineTests {
    private let now = Date(timeIntervalSince1970: 100)

    @Test func outcomesReflectPolicyAndAcceptedAttachmentsEvenWhenLaterTransitionFails() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let clock = now
        let journal = MembershipApplicationJournal(archive: database, now: { clock }, onFailure: { _ in Issue.record("Unexpected recording failure") })
        await journal.prepare()
        let graph = ThreadGraphStore()
        let resource = Resource.workingDirectory("/fixture")
        var receipts: [DecisionRecordID] = []
        func process(_ membership: MembershipDecision, _ offset: Double, resources: [Resource], failsTransition: Bool = false) async throws -> InferenceOutcome {
            let time = now.addingTimeInterval(offset)
            let context = ActivityContext(startedAt: time, endedAt: time, resources: resources.map {
                ResourceEvidence(resource: $0, firstSeen: time, lastSeen: time, source: ActivitySourceID(rawValue: "fixture"))
            })
            let receipt = DecisionRecordID(rawValue: UUID())
            receipts.append(receipt)
            let recorded = MembershipDecision(target: membership.target, confidence: membership.confidence, recordID: receipt)
            return try await ActivityInference(graph: graph, decisions: ApplicationFixtureDecisions(membership: recorded,
                failsTransition: failsTransition), onApplication: { await journal.record($0) }).process(context, active: nil)
        }
        _ = try await process(.init(target: .undetermined, confidence: 0.5), 0, resources: [resource])
        let created = try await process(.init(target: .newThread, confidence: 0.99), 1, resources: [resource])
        let id = try #require(created.thread)
        let weak = try await process(.init(target: .existing(id), confidence: 0.8), 2, resources: [resource])
        #expect(weak.thread == nil)
        _ = try await process(.init(target: .existing(id), confidence: 0.8), 3,
            resources: [resource, .file(FileIdentity(path: "/fixture/draft"))])
        await #expect(throws: ApplicationFixtureError.unavailable) {
            try await process(.init(target: .existing(id), confidence: 0.99), 4, resources: [resource], failsTransition: true)
        }
        await journal.flush()
        let reopened = ThreadDatabase(directory: directory)
        try await reopened.prepare()
        let records = try await reopened.membershipApplications(since: .distantPast, limit: 100)
        #expect(records.map(\.outcome) == [.confirmedAttachment, .provisionalAttachment, .noAttachment, .confirmedAttachment, .waiting])
        #expect(records.filter { $0.thread != nil }.allSatisfy { $0.thread == id })
        #expect(Set(records.map(\.id)).count == 5)
        #expect(records.map(\.decisionRecordID) == receipts.reversed().map(Optional.init))
    }

    @Test func applicationArchiveRejectsInvalidBatchesAndRetainsBoundedIdempotentRecords() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let records = [-20.0, -2, -1, 0].map { offset in
            MembershipApplicationRecord(id: MembershipApplicationID(rawValue: UUID()), timestamp: now.addingTimeInterval(offset), outcome: .waiting, thread: nil)
        }
        let invalid = MembershipApplicationRecord(id: MembershipApplicationID(rawValue: UUID()), timestamp: now, outcome: .confirmedAttachment, thread: nil)
        await #expect(throws: HistoryStorageError.invalidState) {
            try await database.append(applications: [records[0], invalid], at: now, retention: DecisionRetentionPolicy())
        }
        #expect(try await database.membershipApplications(since: .distantPast, limit: 100).isEmpty)
        let retention = DecisionRetentionPolicy(lifetime: 10, maximumRecords: 2)
        for _ in 0..<2 { try await database.append(applications: records, at: now, retention: retention) }
        #expect(try await database.membershipApplications(since: .distantPast, limit: 100) == Array(records.suffix(2).reversed()))
        try await database.append(applications: [], at: now.addingTimeInterval(20), retention: retention)
        #expect(try await database.membershipApplications(since: .distantPast, limit: 100).isEmpty)
    }

    @Test func boundedJournalRetainsTheSameIdsAcrossFailedWrites() async throws {
        let archive = ApplicationArchiveProbe()
        let (stream, continuation) = AsyncStream<MembershipRecordingFailure>.makeStream(bufferingPolicy: .bufferingNewest(8))
        let clock = now
        let journal = MembershipApplicationJournal(archive: archive, now: { clock }, onFailure: { continuation.yield($0) })
        let records = (0..<257).map { _ in MembershipApplicationRecord(id: MembershipApplicationID(rawValue: UUID()),
            timestamp: now, outcome: .waiting, thread: nil) }
        for record in records { await journal.record(record) }
        await journal.flush()
        await journal.flush()
        await archive.enableWrites()
        await journal.flush()
        continuation.finish()
        var failures: [MembershipRecordingFailure] = []
        for await failure in stream { failures.append(failure) }
        #expect(failures == [.backlogOverflow, .writeUnavailable])
        #expect(await archive.ids == Set(records.suffix(256).map(\.id)))
    }
}

private enum ApplicationFixtureError: Error { case unavailable }
private struct ApplicationFixtureDecisions: DecisionEngine {
    let membership: MembershipDecision
    let failsTransition: Bool
    func classifyMembership(context: ActivityContext, candidates: [ScoredThreadCandidate]) -> MembershipDecision { membership }
    func detectTransition(context: ActivityContext, active: ThreadID?, membership: MembershipDecision) throws -> TransitionDecision {
        if failsTransition { throw ApplicationFixtureError.unavailable }
        return TransitionDecision(shouldTransition: false, confidence: 1)
    }
    func classifyPersistence(resource: Resource, context: ActivityContext) -> PersistenceDecision {
        PersistenceDecision(disposition: .durable, confidence: 1)
    }
}

private actor ApplicationArchiveProbe: MembershipApplicationArchive {
    private var writable = false
    private(set) var ids: Set<MembershipApplicationID> = []
    func enableWrites() { writable = true }
    func append(applications: [MembershipApplicationRecord], at time: Date, retention: DecisionRetentionPolicy) throws {
        if !writable { throw ApplicationFixtureError.unavailable }
        ids.formUnion(applications.map(\.id))
    }
    func membershipApplications(since time: Date, limit: Int) -> [MembershipApplicationRecord] { [] }
}
