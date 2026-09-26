import GRDB

/// Adds bounded inference metadata storage without linking to mutable graph identities.
enum DecisionArchiveMigration {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("0005_decision_archive") { database in
            try database.execute(sql: """
                CREATE TABLE decision_records (
                    id TEXT PRIMARY KEY NOT NULL, timestamp REAL NOT NULL,
                    origin TEXT NOT NULL CHECK (origin IN ('local', 'remote', 'localFallback')),
                    kind TEXT NOT NULL CHECK (kind IN ('membership', 'transition', 'persistence')),
                    confidence REAL NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
                    elapsed_milliseconds REAL NOT NULL CHECK (elapsed_milliseconds >= 0), payload BLOB NOT NULL
                );
                CREATE INDEX decision_records_timestamp ON decision_records(timestamp);
                CREATE INDEX decision_records_origin_kind ON decision_records(origin, kind);
                UPDATE schema_metadata SET value = '5' WHERE key = 'schema_version';
                """)
        }
    }
}
