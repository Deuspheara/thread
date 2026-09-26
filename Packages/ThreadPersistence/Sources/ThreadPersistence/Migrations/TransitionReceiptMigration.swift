import GRDB

/// Links initial and delayed focus policy evaluations to the selected local transition record.
enum TransitionReceiptMigration {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("0011_transition_receipts") { database in
            try database.execute(sql: """
                ALTER TABLE transition_applications ADD COLUMN decision_record_id TEXT;
                CREATE INDEX transition_applications_decision_record_id ON transition_applications(decision_record_id);
                UPDATE schema_metadata SET value = '11' WHERE key = 'schema_version';
                """)
        }
    }
}
