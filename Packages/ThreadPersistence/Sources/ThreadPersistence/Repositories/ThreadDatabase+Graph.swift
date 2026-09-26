import ThreadDomain

/// Implements the graph-storage port with one SQLite transaction per checkpoint.
extension ThreadDatabase: ThreadRepository {
    public func loadGraph() throws -> ThreadGraphState {
        let connection = try preparedConnection()
        do { return try connection.read { try ThreadGraphReader.load(from: $0) } }
        catch { throw HistoryStorageError.readFailed }
    }

    public func saveGraph(_ state: ThreadGraphState) throws {
        try GraphRecordCodec.validate(state)
        let connection = try preparedConnection()
        do { try connection.write { try ThreadGraphWriter.save(state, in: $0) } }
        catch { throw HistoryStorageError.writeFailed }
    }
}
