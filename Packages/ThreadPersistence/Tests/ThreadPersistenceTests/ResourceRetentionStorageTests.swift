import Foundation
import Testing
import ThreadDomain
import ThreadPersistence

struct ResourceRetentionStorageTests {
    @Test func databaseRejectsSessionOnlyAndDiscardedGraphAndSnapshotResources() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record("Retention fixture cleanup failed") }
        }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let now = Date(timeIntervalSince1970: 100)
        let thread = ThreadDomain.Thread(id: ThreadID(rawValue: UUID()), title: "Work", createdAt: now, lastActiveAt: now)
        let baseline = ThreadGraphState(threads: [ThreadDetail(thread: thread, resources: [])], corrections: [])
        try await database.saveGraph(baseline)
        for disposition in [PersistenceDisposition.sessionOnly, .discard] {
            let edge = ThreadResource(resource: .workingDirectory("/work"), confidence: 1, firstSeen: now,
                lastSeen: now, source: ActivitySourceID(rawValue: "test"), status: .confirmed, persistence: disposition)
            let graph = ThreadGraphState(threads: [ThreadDetail(thread: thread, resources: [edge])], corrections: [])
            await #expect(throws: HistoryStorageError.invalidState) { try await database.saveGraph(graph) }
            #expect(try await database.loadGraph() == baseline)
            let snapshot = ThreadSnapshot(id: ThreadSnapshotID(rawValue: UUID()), thread: thread.id,
                capturedAt: now, title: "Work", resources: [edge])
            let event = ArchivedActivityEvent(event: ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: now,
                source: ActivitySourceID(rawValue: "test"), kind: .accessibilityPermissionChanged(.granted)))
            await #expect(throws: HistoryStorageError.invalidState) {
                try await database.append(events: [event], snapshots: [snapshot], at: now, retention: HistoryRetentionPolicy())
            }
            #expect(try await database.snapshots(for: thread.id, limit: 100).isEmpty)
            #expect(try await database.events(since: now, limit: 100).isEmpty)
        }
    }
}
