import Foundation
import ThreadDomain

/// Implements bounded event/snapshot history without exposing database records to callers.
extension ThreadDatabase: ActivityArchive {
    public func append(events: [ArchivedActivityEvent], snapshots: [ThreadSnapshot], at time: Date, retention: HistoryRetentionPolicy) throws {
        try ActivityArchiveWriter.validate(events: events, snapshots: snapshots, time: time)
        let connection = try preparedConnection()
        do {
            try connection.write { try ActivityArchiveWriter.append(events: events, snapshots: snapshots, at: time, retention: retention, in: $0) }
        } catch { throw HistoryStorageError.writeFailed }
    }

    public func snapshots(for thread: ThreadID, limit: Int) throws -> [ThreadSnapshot] {
        let connection = try preparedConnection()
        do { return try connection.read { try ActivityArchiveReader.snapshots(thread: thread, limit: limit, in: $0) } }
        catch { throw HistoryStorageError.readFailed }
    }

    public func events(since time: Date, limit: Int) throws -> [ArchivedActivityEvent] {
        let connection = try preparedConnection()
        do { return try connection.read { try ActivityArchiveReader.events(since: time, limit: limit, in: $0) } }
        catch { throw HistoryStorageError.readFailed }
    }
}
