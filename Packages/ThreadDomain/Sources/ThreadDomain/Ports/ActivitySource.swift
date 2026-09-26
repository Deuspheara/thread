/// Supplies a single-consumer stream of normalized observations; cancellation ends the subscription.
public protocol ActivitySource: Sendable {
    func events() -> AsyncStream<ActivityEvent>
}
