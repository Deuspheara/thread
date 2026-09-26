import Foundation
import Testing
import ThreadDomain
import ThreadEngine

struct ObservationSessionTests {
    @Test func finiteSourcePublishesLatestSnapshotAndCompletes() async {
        let session = ObservationSession()
        let application = ApplicationContext(identity: ApplicationIdentity(bundleIdentifier: "app.test"), name: "Test", processIdentifier: 1)
        let event = ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: Date(timeIntervalSince1970: 1), source: ActivitySourceID(rawValue: "test"), kind: .applicationActivated(application))
        let source = FiniteSource(values: [event])
        await session.run(sources: [source])
        var snapshots: [CurrentContext] = []
        for await context in session.contexts() { snapshots.append(context) }
        #expect(snapshots.last?.application == application)
    }

    @Test func cancellationFinishesOpenSourcesAndPresentation() async {
        let session = ObservationSession()
        let channel = AsyncStream<ActivityEvent>.makeStream()
        let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let source = OpenSource(stream: channel.stream, started: started.continuation)
        let task = Task { await session.run(sources: [source]) }
        for await _ in started.stream { break }
        task.cancel()
        await task.value
        var count = 0
        for await _ in session.contexts() { count += 1 }
        #expect(count == 0)
    }
}

private struct FiniteSource: ActivitySource {
    let values: [ActivityEvent]
    func events() -> AsyncStream<ActivityEvent> {
        AsyncStream { continuation in
            for value in values { continuation.yield(value) }
            continuation.finish()
        }
    }
}

private struct OpenSource: ActivitySource {
    let stream: AsyncStream<ActivityEvent>
    let started: AsyncStream<Void>.Continuation
    func events() -> AsyncStream<ActivityEvent> {
        started.yield(())
        started.finish()
        return stream
    }
}
