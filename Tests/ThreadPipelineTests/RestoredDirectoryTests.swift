import Foundation
import Testing
import ThreadDomain
import ThreadEngine
import ThreadDecisions

struct RestoredDirectoryTests {
    @Test func delayedTerminalDocumentReusesRepositoryThread() async throws {
        let graph = ThreadGraphStore()
        let inference = ActivityInference(graph: graph, decisions: HeuristicDecisionEngine())
        let time = Date(timeIntervalSince1970: 100)
        let repository = RepositoryContext(identity: RepositoryIdentity(commonDirectory: "/tmp/fixture/project/.git"),
            rootPath: "/tmp/fixture/project", gitDirectory: "/tmp/fixture/project/.git", branch: "fix",
            head: nil, dirty: RepositoryDirtySummary(changedTrackedFiles: 0, conflictedFiles: 0, isApproximate: false))
        func context(_ resources: [Resource], at date: Date) -> ActivityContext {
            ActivityContext(startedAt: date, endedAt: date, resources: resources.map {
                ResourceEvidence(resource: $0, firstSeen: date, lastSeen: date, source: ActivitySourceID(rawValue: "fixture"))
            })
        }
        let initial = try await inference.process(context([.repository(repository), .branch(repository.identity, "fix"),
            .workingDirectory("/private/tmp/fixture/project")], at: time), active: nil)
        let original = try #require(initial.thread)
        let delayed = try await inference.process(context([.file(FileIdentity(path: "/tmp/fixture/project"))],
            at: time.addingTimeInterval(5)), active: original)
        #expect(delayed.thread == original)
        #expect(await graph.details().count == 1)
        #expect(await graph.detail(original)?.resources.contains { $0.resource.id == .file(FileIdentity(path: "/tmp/fixture/project")) } == true)
        let unrelated = try await inference.process(context([.file(FileIdentity(path: "/tmp/fixture/project-other"))],
            at: time.addingTimeInterval(10)), active: original)
        #expect(unrelated.thread != original)
        #expect(await graph.details().count == 2)
    }
}
