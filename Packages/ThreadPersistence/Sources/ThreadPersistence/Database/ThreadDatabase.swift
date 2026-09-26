import Foundation
import GRDB

/// Owns the SQLite connection and prepares durable storage before use.
public actor ThreadDatabase {
    private let directory: URL
    private var database: DatabaseQueue?

    public init(directory: URL) {
        self.directory = directory
    }

    func preparedConnection() throws -> DatabaseQueue {
        guard let database else { throw HistoryStorageError.notPrepared }
        return database
    }

    public func prepare() throws {
        guard database == nil else { return }
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw StorageError.directoryUnavailable
        }

        let connection: DatabaseQueue
        do {
            connection = try DatabaseQueue(path: directory.appendingPathComponent("Thread.sqlite").path)
        } catch {
            throw StorageError.databaseUnavailable
        }
        do {
            try FoundationMigration.migrator().migrate(connection)
        } catch {
            throw StorageError.migrationFailed
        }
        database = connection
    }
}
