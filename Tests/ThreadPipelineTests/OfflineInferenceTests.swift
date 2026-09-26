import Foundation
import Testing
import ThreadDomain
import ThreadEngine
import ThreadDecisions

struct OfflineInferenceTests {
    @Test func shellAndGitEventsProduceThreadsAndReturnToKnownWorkWithoutNetwork() async throws {
        let graph = ThreadGraphStore()
        let inference = ActivityInference(graph: graph, decisions: HeuristicDecisionEngine())
        var aggregator = EventAggregator()
        var transitions = TransitionPolicy()
        let epoch = Date(timeIntervalSince1970: 100)
        let session = TerminalSessionIdentity(rawValue: UUID())
        var assigned: [ThreadID] = []
        for (index, path) in ["/work/A", "/work/B", "/work/A"].enumerated() {
            let time = epoch.addingTimeInterval(Double(index * 20))
            let sequence = UInt64(index + 1)
            let terminal = TerminalContext(session: session, processIdentifier: 1, workingDirectory: path,
                                           terminalApplication: nil, sequence: sequence)
            let repository = RepositoryContext(identity: RepositoryIdentity(commonDirectory: path + "/.git"), rootPath: path,
                gitDirectory: path + "/.git", branch: "fix", head: nil, dirty: RepositoryDirtySummary(changedTrackedFiles: 0, conflictedFiles: 0))
            let kinds: [ActivityEventKind] = [.terminalDirectoryChanged(terminal), .repositoryChanged(
                RepositoryObservation(terminal: session, sequence: sequence, resolution: .available(repository)))]
            for kind in kinds {
                let event = ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: time,
                                          source: ActivitySourceID(rawValue: "replay"), kind: kind)
                for context in aggregator.ingest(event, at: time) { _ = try await inference.process(context, active: transitions.active) }
            }
            let context = try #require(aggregator.advance(to: time.addingTimeInterval(2)).first)
            let outcome = try await inference.process(context, active: transitions.active)
            let id = try #require(outcome.thread)
            assigned.append(id)
            transitions.consider(id, decision: outcome.transition, at: context.endedAt)
            if let review = transitions.nextReviewAt { transitions.consider(id, decision: outcome.transition, at: review) }
            #expect(transitions.active == id)
        }
        #expect(assigned[0] != assigned[1])
        #expect(assigned[0] == assigned[2])
        let details = await graph.details()
        #expect(details.count == 2)
        #expect(Set(details.map { $0.thread.title }) == ["A · fix", "B · fix"])
        #expect(details.allSatisfy { $0.resources.count == 4 })
    }
}
