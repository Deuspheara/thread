import ThreadDomain

/// Saves changed checkpoints only after existing durable history was read successfully.
actor GraphHistory {
    private let repository: any ThreadRepository
    private var loaded = false
    private var lastSaved: ThreadGraphState?

    init(repository: any ThreadRepository) { self.repository = repository }

    func load() async throws -> ThreadGraphState {
        let state = try await repository.loadGraph()
        try ThreadGraphValidation.validate(state)
        loaded = true
        lastSaved = state
        return state
    }

    /// The owning engine serializes saves and its final shutdown flush.
    func save(_ state: ThreadGraphState) async throws {
        guard loaded else { throw HistoryLifecycleError.notLoaded }
        guard state != lastSaved else { return }
        try await repository.saveGraph(state)
        lastSaved = state
    }
}

public enum HistoryLifecycleError: Error, Sendable { case notLoaded, stopped, saveFailed }
