import GRDB

/// Stores inferred focus policy outcomes separately from membership and activity payloads.
enum TransitionApplicationMigration {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("0007_transition_applications") { database in
            try database.execute(sql: """
                CREATE TABLE transition_applications (
                    id TEXT PRIMARY KEY NOT NULL, timestamp REAL NOT NULL,
                    phase TEXT NOT NULL CHECK (phase IN ('context', 'review')),
                    outcome TEXT NOT NULL CHECK (outcome IN ('activated', 'switched', 'deferred', 'alreadyActive', 'declined', 'confidenceRejected', 'staleTime', 'obsoleteContext')),
                    previous_thread_id TEXT, target_thread_id TEXT NOT NULL,
                    CHECK (outcome != 'activated' OR previous_thread_id IS NULL),
                    CHECK (outcome != 'switched' OR (previous_thread_id IS NOT NULL AND previous_thread_id != target_thread_id)),
                    CHECK (outcome != 'alreadyActive' OR (previous_thread_id IS NOT NULL AND previous_thread_id = target_thread_id))
                );
                CREATE INDEX transition_applications_timestamp ON transition_applications(timestamp);
                UPDATE schema_metadata SET value = '7' WHERE key = 'schema_version';
                """)
        }
    }
}
