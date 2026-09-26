import Foundation
import Testing
import ThreadDomain
@testable import ThreadGit

struct GitActivityTests {
    @Test func shellEventsProduceRepositoryThenBranchChangeWithoutLosingSessionIdentity() async throws {
        let repo = try TemporaryRepository()
        defer { repo.remove() }
        try repo.commit()
        let channel = AsyncStream<ActivityEvent>.makeStream()
        let source = GitActivitySource(upstream: FixtureSource(stream: channel.stream))
        let running = Task { await source.run() }
        defer { channel.continuation.finish(); running.cancel() }
        let session = TerminalSessionIdentity(rawValue: UUID())
        channel.continuation.yield(event(session, sequence: 1, directory: repo.path))
        let first = try await nextRepository(from: source)
        guard case .repositoryChanged(let observation) = first else { Issue.record("Expected initial repository"); return }
        #expect(observation.terminal == session)
        #expect(observation.sequence == 1)
        try repo.git(["checkout", "-b", "next-branch"])
        channel.continuation.yield(event(session, sequence: 2, directory: repo.path))
        let changed = try await nextRepository(from: source)
        guard case .branchChanged(let update) = changed, case .available(let context) = update.resolution else {
            Issue.record("Expected branch change"); return
        }
        #expect(update.sequence == 2)
        #expect(context.branch == "next-branch")
    }

    private func nextRepository(from source: GitActivitySource) async throws -> ActivityEventKind {
        try await withThrowingTaskGroup(of: ActivityEventKind.self) { group in
            group.addTask {
                for await event in source.events() {
                    switch event.kind {
                    case .repositoryChanged, .branchChanged: return event.kind
                    default: break
                    }
                }
                throw GitReadError.unavailable
            }
            group.addTask { try await Task.sleep(for: .seconds(5)); throw GitReadError.timedOut }
            defer { group.cancelAll() }
            return try await #require(group.next())
        }
    }

    private func event(_ session: TerminalSessionIdentity, sequence: UInt64, directory: String) -> ActivityEvent {
        let context = TerminalContext(session: session, processIdentifier: 1, workingDirectory: directory, terminalApplication: nil, sequence: sequence)
        return ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: Date(), source: ActivitySourceID(rawValue: "test"),
                             kind: .terminalCommandCompleted(context, 0))
    }
}

private struct FixtureSource: ActivitySource {
    let stream: AsyncStream<ActivityEvent>
    func events() -> AsyncStream<ActivityEvent> { stream }
}
