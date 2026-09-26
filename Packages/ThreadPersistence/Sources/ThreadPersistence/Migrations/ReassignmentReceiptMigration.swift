import GRDB

/// Preserves exact prior membership receipts without coupling graph/evaluation retention.
enum ReassignmentReceiptMigration {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("0010_reassignment_receipts") { database in
            try database.execute(sql: """
                ALTER TABLE resource_reassignments ADD COLUMN decision_record_id TEXT
                    CHECK (origin != 'explicit' OR decision_record_id IS NULL);
                CREATE INDEX resource_reassignments_decision_record_id ON resource_reassignments(decision_record_id);
                UPDATE schema_metadata SET value = '10' WHERE key = 'schema_version';
                """)
        }
    }
}
