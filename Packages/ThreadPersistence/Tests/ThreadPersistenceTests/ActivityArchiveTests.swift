import Foundation
import Testing
import ThreadDomain
import ThreadPersistence

struct ActivityArchiveTests {
    let epoch = Date(timeIntervalSince1970: 100)
    func event(_ offset: Double, thread: ThreadID? = nil) -> ArchivedActivityEvent {
        ArchivedActivityEvent(event: ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: epoch.addingTimeInterval(offset),
            source: ActivitySourceID(rawValue: "test"), kind: .accessibilityPermissionChanged(.granted)), thread: thread)
    }
    func snapshot(_ thread: ThreadID, _ offset: Double) -> ThreadSnapshot {
        let time = epoch.addingTimeInterval(offset)
        let resource = ThreadResource(resource: .workingDirectory("/work/project"), confidence: 0.97, firstSeen: epoch,
            lastSeen: time, source: ActivitySourceID(rawValue: "test"), status: .confirmed)
        return ThreadSnapshot(id: ThreadSnapshotID(rawValue: UUID()), thread: thread, capturedAt: time, title: "Work", resources: [resource])
    }
    func graph(_ ids: [ThreadID]) -> ThreadGraphState {
        ThreadGraphState(threads: ids.map {
            ThreadDetail(thread: ThreadDomain.Thread(id: $0, title: "Work", createdAt: epoch, lastActiveAt: epoch), resources: [])
        }, corrections: [])
    }

    @Test func ageCountAndPerThreadSnapshotRetentionAreAppliedOnEveryBatch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let a = ThreadID(rawValue: UUID()), b = ThreadID(rawValue: UUID())
        try await database.saveGraph(graph([a, b]))
        let retention = HistoryRetentionPolicy(eventLifetime: 10, maximumEvents: 2, snapshotsPerThread: 2)
        try await database.append(events: [event(0), event(10), event(11), event(15)],
            snapshots: [snapshot(a, 1), snapshot(a, 2), snapshot(a, 3), snapshot(b, 1)], at: epoch.addingTimeInterval(20), retention: retention)
        let events = try await database.events(since: epoch, limit: 100)
        #expect(events.map { $0.event.timestamp } == [epoch.addingTimeInterval(15), epoch.addingTimeInterval(11)])
        #expect(try await database.snapshots(for: a, limit: 100).map(\.capturedAt) == [epoch.addingTimeInterval(3), epoch.addingTimeInterval(2)])
        #expect(try await database.snapshots(for: b, limit: 100).count == 1)
        try await database.append(events: [], snapshots: [], at: epoch.addingTimeInterval(100), retention: retention)
        #expect(try await database.events(since: epoch, limit: 100).isEmpty)
        #expect(try await database.loadGraph().threads.count == 2)
    }

    @Test func retriedIDsDoNotDuplicateAndDeletingThreadClearsAttribution() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let id = ThreadID(rawValue: UUID())
        try await database.saveGraph(graph([id]))
        let events = [event(1, thread: id)]
        let snapshots = [snapshot(id, 1)]
        for _ in 0..<2 {
            try await database.append(events: events, snapshots: snapshots, at: epoch.addingTimeInterval(2), retention: HistoryRetentionPolicy())
        }
        #expect(try await database.events(since: epoch, limit: 100) == events)
        #expect(try await database.snapshots(for: id, limit: 100) == snapshots)
        try await database.saveGraph(graph([]))
        #expect(try await database.snapshots(for: id, limit: 100).isEmpty)
        let retained = try await database.events(since: epoch, limit: 100)
        #expect(retained.count == 1)
        #expect(retained.first?.thread == nil)
    }

    @Test func invalidSnapshotRollsBackEventsInTheSameBatch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let unknown = ThreadID(rawValue: UUID())
        await #expect(throws: HistoryStorageError.writeFailed) {
            try await database.append(events: [event(1)], snapshots: [snapshot(unknown, 1)],
                                      at: epoch.addingTimeInterval(2), retention: HistoryRetentionPolicy())
        }
        #expect(try await database.events(since: epoch, limit: 100).isEmpty)
    }
}
