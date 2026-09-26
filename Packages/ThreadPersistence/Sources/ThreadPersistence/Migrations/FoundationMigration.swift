import GRDB

/// Registers the initial metadata schema; product tables arrive with their owning features.
enum FoundationMigration {
    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("0001_foundation") { database in
            try database.create(table: "schema_metadata") { table in
                table.column("key", .text).primaryKey()
                table.column("value", .text).notNull()
            }
            try database.execute(
                sql: "INSERT INTO schema_metadata (key, value) VALUES (?, ?)",
                arguments: ["schema_version", "1"]
            )
        }
        ThreadGraphMigration.register(in: &migrator)
        ActivityArchiveMigration.register(in: &migrator)
        ThreadSearchMigration.register(in: &migrator)
        DecisionArchiveMigration.register(in: &migrator)
        MembershipApplicationMigration.register(in: &migrator)
        TransitionApplicationMigration.register(in: &migrator)
        ResourceReassignmentMigration.register(in: &migrator)
        MembershipReceiptMigration.register(in: &migrator)
        ReassignmentReceiptMigration.register(in: &migrator)
        TransitionReceiptMigration.register(in: &migrator)
        return migrator
    }
}
