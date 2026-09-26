import Foundation
import ThreadDomain

/// Serializes independent event sources and publishes coalescible foreground snapshots in order.
public actor ObservationSession {
    private nonisolated let updates: AsyncStream<CurrentContext>
    private let continuation: AsyncStream<CurrentContext>.Continuation
    private var reducer = CurrentContextReducer()
    private var privacy: ObservationPrivacyFilter
    private var running = false
    private let onEvent: @Sendable (ActivityEvent) async -> Void

    public init(exclusions: ObservationExclusions? = ObservationExclusions(), onEvent: @escaping @Sendable (ActivityEvent) async -> Void = { _ in }) {
        self.onEvent = onEvent
        privacy = ObservationPrivacyFilter(exclusions: exclusions)
        let channel = AsyncStream<CurrentContext>.makeStream(bufferingPolicy: .bufferingNewest(1))
        updates = channel.stream
        continuation = channel.continuation
    }

    /// One presentation consumer receives snapshots; intermediate snapshots may be coalesced.
    public nonisolated func contexts() -> AsyncStream<CurrentContext> { updates }

    public func run(sources: [any ActivitySource]) async {
        guard !running else { return }
        running = true
        defer {
            running = false
            continuation.finish()
        }
        await withTaskGroup(of: Void.self) { group in
            for source in sources {
                group.addTask {
                    for await event in source.events() {
                        guard !Task.isCancelled else { return }
                        await self.receive(event)
                    }
                }
            }
        }
    }

    public func setExclusions(_ exclusions: ObservationExclusions, at time: Date) async {
        privacy.exclusions = exclusions
        await forward(ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: time,
                                    source: ActivitySourceID(rawValue: "privacy"), kind: .observationCleared))
    }

    private func receive(_ event: ActivityEvent) async {
        guard let accepted = privacy.screen(event) else { return }
        await forward(accepted)
    }

    private func forward(_ event: ActivityEvent) async {
        let previous = reducer.context
        reducer.apply(event)
        if previous != reducer.context { continuation.yield(reducer.context) }
        await onEvent(event)
    }
}
