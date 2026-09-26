import GRDB

/// Correlates local inference/application archives without requiring both records to survive retention.
enum MembershipReceiptMigration {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("0009_membership_receipts") { database in
            try database.execute(sql: """
                ALTER TABLE membership_applications ADD COLUMN decision_record_id TEXT;
                CREATE INDEX membership_applications_decision_record_id ON membership_applications(decision_record_id);
                UPDATE schema_metadata SET value = '9' WHERE key = 'schema_version';
                """)
        }
    }
}
