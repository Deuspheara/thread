import GRDB

/// Adds indexed normalized events and per-Thread immutable restoration snapshots.
enum ActivityArchiveMigration {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("0003_activity_archive") { database in
            try database.execute(sql: """
                CREATE TABLE events (
                    id TEXT PRIMARY KEY NOT NULL, timestamp REAL NOT NULL,
                    thread_id TEXT REFERENCES threads(id) ON DELETE SET NULL, payload BLOB NOT NULL
                );
                CREATE INDEX events_timestamp ON events(timestamp);
                CREATE INDEX events_thread_id ON events(thread_id);
                CREATE TABLE snapshots (
                    id TEXT PRIMARY KEY NOT NULL, thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
                    captured_at REAL NOT NULL, payload BLOB NOT NULL
                );
                CREATE INDEX snapshots_thread_time ON snapshots(thread_id, captured_at DESC);
                UPDATE schema_metadata SET value = '3' WHERE key = 'schema_version';
                """)
        }
    }
}
