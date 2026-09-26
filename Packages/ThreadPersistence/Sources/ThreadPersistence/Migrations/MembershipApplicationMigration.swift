import GRDB

/// Adds narrow live-graph membership outcomes independently of inference and graph payloads.
enum MembershipApplicationMigration {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("0006_membership_applications") { database in
            try database.execute(sql: """
                CREATE TABLE membership_applications (
                    id TEXT PRIMARY KEY NOT NULL, timestamp REAL NOT NULL,
                    outcome TEXT NOT NULL CHECK (outcome IN ('waiting', 'confirmedAttachment', 'provisionalAttachment', 'noAttachment')),
                    thread_id TEXT,
                    CHECK ((outcome IN ('waiting', 'noAttachment') AND thread_id IS NULL)
                        OR (outcome IN ('confirmedAttachment', 'provisionalAttachment') AND thread_id IS NOT NULL))
                );
                CREATE INDEX membership_applications_timestamp ON membership_applications(timestamp);
                UPDATE schema_metadata SET value = '6' WHERE key = 'schema_version';
                """)
        }
    }
}
