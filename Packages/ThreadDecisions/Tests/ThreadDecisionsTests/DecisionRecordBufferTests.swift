import Foundation
import Testing
import ThreadDomain
import ThreadDecisions

struct DecisionRecordBufferTests {
    private let now = Date(timeIntervalSince1970: 100)
    private func record(_ index: Int = 0) -> DecisionRecord {
        DecisionRecord(id: DecisionRecordID(rawValue: UUID()), timestamp: now.addingTimeInterval(Double(index)),
            origin: .local, elapsedMilliseconds: 1, decision: .membership(MembershipDecision(target: .newThread, confidence: 1)))
    }

    @Test func failedWritesRetainOriginalIDsAndRecoveryDoesNotDuplicateRecords() async {
        let archive = RecordArchiveProbe(failing: true)
        let (failures, notification) = AsyncStream<DecisionRecordingFailure>.makeStream()
        let buffer = DecisionRecordBuffer(archive: archive, now: { Date(timeIntervalSince1970: 100) },
            onFailure: { notification.yield($0) })
        let first = record(), second = record(1)
        await buffer.record(first)
        await buffer.flush()
        await buffer.flush()
        await buffer.record(second)
        await archive.allowWrites()
        await buffer.flush()
        await buffer.flush()
        #expect(Set(await archive.saved.map(\.id)) == [first.id, second.id])
        #expect(await archive.attempts == 3)
        notification.finish()
        var notices: [DecisionRecordingFailure] = []
        for await value in failures { notices.append(value) }
        #expect(notices == [.writeUnavailable])
    }

    @Test func startupCleanupBacklogBoundsAndInvalidRecordRejectionAreExplicit() async {
        let archive = RecordArchiveProbe()
        let (failures, notification) = AsyncStream<DecisionRecordingFailure>.makeStream()
        let buffer = DecisionRecordBuffer(archive: archive, onFailure: { notification.yield($0) })
        await buffer.prepare()
        #expect(await archive.attempts == 1)
        let records = (0..<300).map { record($0) }
        for value in records { await buffer.record(value) }
        await buffer.record(DecisionRecord(id: DecisionRecordID(rawValue: UUID()), timestamp: now, origin: .local,
            elapsedMilliseconds: -1, decision: .membership(MembershipDecision(target: .newThread, confidence: 1))))
        await buffer.flush()
        #expect(Set(await archive.saved.map(\.id)) == Set(records.suffix(256).map(\.id)))
        notification.finish()
        var notices: [DecisionRecordingFailure] = []
        for await value in failures { notices.append(value) }
        #expect(notices == [.backlogOverflow, .invalidRecord])
    }

    @Test func arrivalsDuringFlushAreDrainedAndConcurrentCallersAwaitCompletion() async {
        let (started, notify) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let archive = SuspendedRecordArchive(started: notify)
        let buffer = DecisionRecordBuffer(archive: archive, onFailure: { _ in Issue.record("Unexpected write failure") })
        let first = record(), second = record(1)
        await buffer.record(first)
        let flush = Task { await buffer.flush() }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        await buffer.record(second)
        let concurrent = Task { await buffer.flush() }
        await archive.release()
        await flush.value
        await concurrent.value
        #expect(Set(await archive.saved.map(\.id)) == [first.id, second.id])
        #expect(await archive.attempts == 2)
        notify.finish()
    }
}

private actor RecordArchiveProbe: DecisionArchive {
    enum Failure: Error { case unavailable }
    var saved: [DecisionRecord] = []
    var attempts = 0
    private var failing: Bool
    init(failing: Bool = false) { self.failing = failing }
    func allowWrites() { failing = false }
    func append(decisions: [DecisionRecord], at time: Date, retention: DecisionRetentionPolicy) throws {
        attempts += 1
        if failing { throw Failure.unavailable }
        for record in decisions where !saved.contains(where: { $0.id == record.id }) { saved.append(record) }
    }
    func decisions(since time: Date, limit: Int) -> [DecisionRecord] { Array(saved.prefix(limit)) }
}

private actor SuspendedRecordArchive: DecisionArchive {
    var saved: [DecisionRecord] = []
    var attempts = 0
    private let started: AsyncStream<Void>.Continuation
    private var gate: CheckedContinuation<Void, Never>?
    init(started: AsyncStream<Void>.Continuation) { self.started = started }
    func release() { gate?.resume(); gate = nil }
    func append(decisions: [DecisionRecord], at time: Date, retention: DecisionRetentionPolicy) async {
        attempts += 1
        if attempts == 1 {
            await withCheckedContinuation { gate = $0; started.yield(()) }
        }
        saved.append(contentsOf: decisions)
    }
    func decisions(since time: Date, limit: Int) -> [DecisionRecord] { Array(saved.prefix(limit)) }
}
