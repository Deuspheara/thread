/// Describes startup failures without exposing database implementation or private paths.
public enum StorageError: Error, Sendable {
    case directoryUnavailable
    case databaseUnavailable
    case migrationFailed
}
