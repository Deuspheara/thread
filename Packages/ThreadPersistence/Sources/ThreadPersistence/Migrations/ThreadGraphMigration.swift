import GRDB

/// Adds relational identity/indexes while preserving versioned typed metadata on each edge.
enum ThreadGraphMigration {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("0002_thread_graph") { database in
            try database.execute(sql: """
                CREATE TABLE threads (
                    id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL,
                    created_at REAL NOT NULL, last_active_at REAL NOT NULL,
                    archived INTEGER NOT NULL CHECK (archived IN (0, 1)), payload BLOB NOT NULL
                );
                CREATE INDEX threads_last_active_at ON threads(last_active_at);
                CREATE TABLE resources (
                    identity TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL,
                    last_seen REAL NOT NULL, payload BLOB NOT NULL
                );
                CREATE INDEX resources_kind ON resources(kind);
                CREATE TABLE thread_resources (
                    thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
                    resource_id TEXT NOT NULL REFERENCES resources(identity),
                    first_seen REAL NOT NULL, last_seen REAL NOT NULL,
                    confidence REAL NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
                    status TEXT NOT NULL CHECK (status IN ('provisional', 'confirmed')),
                    pinned INTEGER NOT NULL CHECK (pinned IN (0, 1)),
                    user_corrected INTEGER NOT NULL CHECK (user_corrected IN (0, 1)),
                    payload BLOB NOT NULL, PRIMARY KEY (thread_id, resource_id)
                );
                CREATE INDEX thread_resources_resource_id ON thread_resources(resource_id);
                CREATE TABLE user_corrections (
                    resource_id TEXT PRIMARY KEY NOT NULL REFERENCES resources(identity),
                    thread_id TEXT NOT NULL REFERENCES threads(id) ON DELETE CASCADE
                );
                UPDATE schema_metadata SET value = '2' WHERE key = 'schema_version';
                """)
        }
    }
}
