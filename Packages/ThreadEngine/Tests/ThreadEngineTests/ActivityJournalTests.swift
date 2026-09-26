import Foundation
import Testing
import ThreadDomain
@testable import ThreadEngine

struct ActivityJournalTests {
    let epoch = Date(timeIntervalSince1970: 100)
    func event(_ index: Int) -> ActivityEvent {
        ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: epoch.addingTimeInterval(Double(index)),
            source: ActivitySourceID(rawValue: "test"), kind: .terminalDirectoryChanged(TerminalContext(
                session: TerminalSessionIdentity(rawValue: UUID()), processIdentifier: 1, workingDirectory: "/work", terminalApplication: nil, sequence: UInt64(index + 1))))
    }

    @Test func boundedJournalFiltersNoisyEventsAndReportsDiscardedEvidence() {
        var journal = ActivityJournal()
        let ignored = ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: epoch,
            source: ActivitySourceID(rawValue: "test"), kind: .accessibilityPermissionChanged(.granted))
        _ = journal.record(ignored, at: epoch)
        #expect(journal.deadline == nil)
        var overflow = false
        for index in 0..<513 { overflow = journal.record(event(index), at: epoch) || overflow }
        let batch = journal.batch()
        #expect(overflow)
        #expect(batch.events.count == 512)
        #expect(batch.events.first?.event.timestamp == epoch.addingTimeInterval(1))
        #expect(batch.events.allSatisfy { $0.thread == nil })
    }

    @Test func retryRetainsIDsAndAcknowledgmentPreservesNewArrivals() {
        var journal = ActivityJournal()
        let first = event(0), second = event(1)
        _ = journal.record(first, at: epoch)
        let duplicate = ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: epoch.addingTimeInterval(0.1),
                                      source: first.source, kind: first.kind)
        _ = journal.record(duplicate, at: epoch.addingTimeInterval(0.1))
        let failedBatch = journal.batch()
        #expect(failedBatch.events.count == 1)
        #expect(journal.deadline == nil)
        let retry = journal.batch()
        #expect(retry.events == failedBatch.events)
        _ = journal.record(second, at: epoch.addingTimeInterval(1))
        journal.acknowledge(retry, at: epoch.addingTimeInterval(2))
        #expect(journal.deadline == epoch.addingTimeInterval(4))
        let remaining = journal.batch()
        #expect(remaining.events.map { $0.event.id } == [second.id])
        journal.acknowledge(remaining, at: epoch.addingTimeInterval(4))
        #expect(journal.deadline == nil)
    }

    @Test func snapshotsAreThrottledPerThreadAndSurviveRetry() {
        var journal = ActivityJournal()
        let id = ThreadID(rawValue: UUID())
        let detail = ThreadDetail(thread: ThreadDomain.Thread(id: id, title: "Work", createdAt: epoch, lastActiveAt: epoch), resources: [
            ThreadResource(resource: .workingDirectory("/work"), confidence: 0.97, firstSeen: epoch, lastSeen: epoch,
                           source: ActivitySourceID(rawValue: "test"), status: .confirmed)])
        _ = journal.capture(detail, at: epoch)
        _ = journal.capture(detail, at: epoch.addingTimeInterval(10))
        let first = journal.batch()
        #expect(first.snapshots.count == 1)
        _ = journal.capture(detail, at: epoch.addingTimeInterval(60))
        let later = journal.batch()
        #expect(later.snapshots.count == 2)
        journal.acknowledge(first, at: epoch.addingTimeInterval(61))
        #expect(journal.batch().snapshots.map(\.id) == [later.snapshots[1].id])
    }
}
