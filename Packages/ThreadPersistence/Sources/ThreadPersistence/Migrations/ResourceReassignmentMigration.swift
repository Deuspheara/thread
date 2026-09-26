import GRDB

/// Archives narrow source-edge attribution for explicit resource reassignment.
enum ResourceReassignmentMigration {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("0008_resource_reassignments") { database in
            try database.execute(sql: """
                CREATE TABLE resource_reassignments (
                    id TEXT PRIMARY KEY NOT NULL, timestamp REAL NOT NULL,
                    resource_kind TEXT NOT NULL CHECK (resource_kind IN ('application', 'window', 'browserPage', 'terminal', 'workingDirectory', 'repository', 'branch', 'file')),
                    origin TEXT NOT NULL CHECK (origin IN ('inferred', 'explicit')),
                    status TEXT NOT NULL CHECK (status IN ('confirmed', 'provisional')),
                    outcome TEXT NOT NULL CHECK (outcome IN ('moved', 'confirmed')),
                    source_thread_id TEXT NOT NULL, target_thread_id TEXT NOT NULL,
                    CHECK ((outcome = 'confirmed' AND source_thread_id = target_thread_id)
                        OR (outcome = 'moved' AND source_thread_id != target_thread_id))
                );
                CREATE INDEX resource_reassignments_timestamp ON resource_reassignments(timestamp);
                UPDATE schema_metadata SET value = '8' WHERE key = 'schema_version';
                """)
        }
    }
}
