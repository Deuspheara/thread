import GRDB

/// Creates a metadata-only FTS5 index and backfills existing graph history atomically.
enum ThreadSearchMigration {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("0004_thread_search") { database in
            try database.execute(sql: """
                CREATE TABLE thread_search_documents (
                    thread_id TEXT UNIQUE NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
                    title TEXT NOT NULL, resources TEXT NOT NULL
                );
                CREATE VIRTUAL TABLE thread_search_fts USING fts5(
                    title, resources, content='thread_search_documents', content_rowid='rowid',
                    tokenize='unicode61 remove_diacritics 2'
                );
                CREATE TRIGGER thread_search_insert AFTER INSERT ON thread_search_documents BEGIN
                    INSERT INTO thread_search_fts(rowid, title, resources) VALUES (new.rowid, new.title, new.resources);
                END;
                CREATE TRIGGER thread_search_delete AFTER DELETE ON thread_search_documents BEGIN
                    INSERT INTO thread_search_fts(thread_search_fts, rowid, title, resources)
                    VALUES ('delete', old.rowid, old.title, old.resources);
                END;
                CREATE TRIGGER thread_search_update AFTER UPDATE ON thread_search_documents BEGIN
                    INSERT INTO thread_search_fts(thread_search_fts, rowid, title, resources)
                    VALUES ('delete', old.rowid, old.title, old.resources);
                    INSERT INTO thread_search_fts(rowid, title, resources) VALUES (new.rowid, new.title, new.resources);
                END;
                UPDATE schema_metadata SET value = '4' WHERE key = 'schema_version';
                """)
            try ThreadSearchIndex.update(ThreadGraphReader.load(from: database), in: database)
        }
    }
}
