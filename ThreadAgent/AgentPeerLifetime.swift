/// Keeps retirement attached to its connection, so late callbacks cannot outlive a rejection cache.
@MainActor
final class AgentPeerLifetime {
    private(set) var isActive = true

    nonisolated init() {}

    func retire() { isActive = false }
}
