import Foundation
import ThreadDomain

struct ActivityJournalBatch: Sendable {
    let events: [ArchivedActivityEvent]
    let snapshots: [ThreadSnapshot]
}

/// Buffers selected metadata and throttled snapshots; acknowledgment removes only committed IDs.
struct ActivityJournal: Sendable {
    private var events: [ArchivedActivityEvent] = []
    private var snapshots: [ThreadSnapshot] = []
    private var lastRecorded: [ActivitySourceID: (kind: ActivityEventKind, time: Date)] = [:]
    private var lastCapture: [ThreadID: Date] = [:]
    private(set) var deadline: Date?

    /// Returns true if the bounded backlog discarded older, unsaved evidence.
    mutating func record(_ event: ActivityEvent, at time: Date) -> Bool {
        switch event.kind {
        case .applicationActivated, .windowFocused, .browserTabActivated, .terminalDirectoryChanged: break
        case .repositoryChanged(let observation), .branchChanged(let observation):
            guard case .available = observation.resolution else { return false }
        default: return false
        }
        guard !events.contains(where: { $0.event.id == event.id }) else { return false }
        if let previous = lastRecorded[event.source], previous.kind == event.kind,
           (0..<2).contains(time.timeIntervalSince(previous.time)) { return false }
        if lastRecorded[event.source] == nil, lastRecorded.count >= 64,
           let oldest = lastRecorded.min(by: { ($0.value.time, $0.key.rawValue) < ($1.value.time, $1.key.rawValue) })?.key {
            lastRecorded.removeValue(forKey: oldest)
        }
        lastRecorded[event.source] = (event.kind, time)
        // Classification attribution is unknown at ingress; do not label it with stale active work.
        events.append(ArchivedActivityEvent(event: event))
        if deadline == nil { deadline = time.addingTimeInterval(2) }
        if events.count > 512 { events.removeFirst(events.count - 512); return true }
        return false
    }

    mutating func capture(_ detail: ThreadDetail, at time: Date) -> Bool {
        if let last = lastCapture[detail.thread.id], time.timeIntervalSince(last) < 60 { return false }
        guard let snapshot = SnapshotBuilder().build(detail, at: time) else { return false }
        snapshots.append(snapshot)
        lastCapture[detail.thread.id] = time
        if deadline == nil { deadline = time.addingTimeInterval(2) }
        if snapshots.count > 64 { snapshots.removeFirst(snapshots.count - 64); return true }
        return false
    }

    mutating func pauseDeadline() { deadline = nil }
    mutating func batch() -> ActivityJournalBatch {
        deadline = nil
        return ActivityJournalBatch(events: events, snapshots: snapshots)
    }
    mutating func acknowledge(_ batch: ActivityJournalBatch, at time: Date) {
        let eventIDs = Set(batch.events.map { $0.event.id })
        let snapshotIDs = Set(batch.snapshots.map(\.id))
        events.removeAll { eventIDs.contains($0.event.id) }
        snapshots.removeAll { snapshotIDs.contains($0.id) }
        deadline = events.isEmpty && snapshots.isEmpty ? nil : time.addingTimeInterval(2)
    }
}
