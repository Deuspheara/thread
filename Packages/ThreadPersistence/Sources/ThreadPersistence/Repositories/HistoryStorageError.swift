/// Reports graph failures without leaking SQL, payloads, or local paths.
public enum HistoryStorageError: Error, Sendable { case notPrepared, invalidState, readFailed, writeFailed }
