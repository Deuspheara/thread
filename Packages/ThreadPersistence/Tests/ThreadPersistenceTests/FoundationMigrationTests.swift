import Foundation
import GRDB
import Testing
import ThreadPersistence

struct FoundationMigrationTests {
    @Test func migrationSurvivesReopenWithoutDuplicatingMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        try await database.prepare()
        try await ThreadDatabase(directory: directory).prepare()

        let connection = try DatabaseQueue(path: directory.appendingPathComponent("Thread.sqlite").path)
        let (version, count, migrations) = try await connection.read { database in
            (
                try String.fetchOne(database, sql: "SELECT value FROM schema_metadata WHERE key = 'schema_version'"),
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM schema_metadata"),
                try String.fetchAll(database, sql: "SELECT identifier FROM grdb_migrations")
            )
        }
        #expect(version == "11")
        #expect(count == 1)
        #expect(migrations == ["0001_foundation", "0002_thread_graph", "0003_activity_archive", "0004_thread_search", "0005_decision_archive", "0006_membership_applications", "0007_transition_applications", "0008_resource_reassignments", "0009_membership_receipts", "0010_reassignment_receipts", "0011_transition_receipts"])
    }

    @Test func existingFoundationDatabaseUpgradesWithoutErasingMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let connection = try DatabaseQueue(path: directory.appendingPathComponent("Thread.sqlite").path)
        try await connection.write { database in
            try database.execute(sql: """
                CREATE TABLE schema_metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
                INSERT INTO schema_metadata VALUES ('schema_version', '1'), ('preserved', 'yes');
                CREATE TABLE grdb_migrations(identifier TEXT NOT NULL PRIMARY KEY);
                INSERT INTO grdb_migrations VALUES ('0001_foundation');
                """)
        }
        try await ThreadDatabase(directory: directory).prepare()
        let value = try await connection.read { try String.fetchOne($0, sql: "SELECT value FROM schema_metadata WHERE key = 'preserved'") }
        #expect(value == "yes")
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        #expect(try await database.loadGraph().threads.isEmpty)
    }

    @Test func unavailableDirectoryReportsTypedFailure() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data().write(to: file)
        let database = ThreadDatabase(directory: file.appendingPathComponent("storage"))
        await #expect(throws: StorageError.directoryUnavailable) {
            try await database.prepare()
        }
    }

    @Test func membershipReceiptUpgradePreservesUnlinkedExistingRows() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let connection = try DatabaseQueue(path: directory.appendingPathComponent("Thread.sqlite").path)
        let id = UUID()
        try await connection.write { database in
            // Recreate the previous schema on a real graph database, leaving all earlier migrations intact.
            try database.execute(sql: """
                DROP INDEX membership_applications_decision_record_id;
                ALTER TABLE membership_applications DROP COLUMN decision_record_id;
                DROP INDEX resource_reassignments_decision_record_id;
                ALTER TABLE resource_reassignments DROP COLUMN decision_record_id;
                DROP INDEX transition_applications_decision_record_id;
                ALTER TABLE transition_applications DROP COLUMN decision_record_id;
                DELETE FROM grdb_migrations WHERE identifier IN ('0009_membership_receipts', '0010_reassignment_receipts', '0011_transition_receipts');
                UPDATE schema_metadata SET value = '8' WHERE key = 'schema_version';
                """)
            try database.execute(sql: "INSERT INTO membership_applications(id, timestamp, outcome) VALUES (?, 100, 'waiting')",
                arguments: [id.uuidString])
            try database.execute(sql: "INSERT INTO transition_applications(id, timestamp, phase, outcome, target_thread_id) VALUES (?, 100, 'context', 'activated', ?)",
                arguments: [id.uuidString, UUID().uuidString])
        }
        let reopened = ThreadDatabase(directory: directory)
        try await reopened.prepare()
        let records = try await reopened.membershipApplications(since: .distantPast, limit: 10)
        #expect(records.count == 1 && records.first?.id.rawValue == id)
        #expect(records.first?.decisionRecordID == nil)
        #expect(try await reopened.transitionApplications(since: .distantPast, limit: 10).first?.decisionRecordID == nil)
    }
}
