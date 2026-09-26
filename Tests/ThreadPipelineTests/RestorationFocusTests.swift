import Foundation
import Testing
import ThreadDomain
import ThreadEngine
import ThreadDecisions

struct RestorationFocusTests {
    @Test func restorationSelectsThreadAndSuppressesGeneratedInferenceUntilCompletion() async throws {
        let graph = ThreadGraphStore()
        let id = ThreadID(rawValue: UUID())
        let time = Date(timeIntervalSince1970: 100)
        try await graph.restore(ThreadGraphState(threads: [ThreadDetail(
            thread: ThreadDomain.Thread(id: id, title: "Chosen", createdAt: time, lastActiveAt: time), resources: [])], corrections: []))
        let runtime = ActivityRuntimeTests()
        let engine = ActivityEngine(graph: graph, decisions: HeuristicDecisionEngine(), policy: runtime.policy)
        let token = try await engine.beginRestoration(id)
        let selected = try await runtime.waitForOverview(engine.updates()) { $0.active == id }
        #expect(selected.threads.first?.thread.lastActiveAt ?? .distantPast > time)
        let terminal = TerminalSessionIdentity(rawValue: UUID())
        await runtime.sendProject("/restoration/generated", sequence: 1, session: terminal, to: engine)
        try await Task.sleep(for: .milliseconds(60))
        #expect(await graph.details().count == 1)
        // An unrelated token cannot release another restoration's suppression.
        try await engine.endRestoration(UUID())
        await runtime.sendProject("/restoration/still-generated", sequence: 2, session: terminal, to: engine)
        try await Task.sleep(for: .milliseconds(60))
        #expect(await graph.details().count == 1)
        try await engine.endRestoration(token)
        await runtime.sendProject("/actual/user-work", sequence: 3, session: terminal, to: engine)
        let resumed = try await runtime.waitForOverview(engine.updates()) { $0.threads.count == 2 }
        #expect(resumed.active == id)
        #expect(!resumed.threads.contains { $0.resources.contains { $0.resource.id == .workingDirectory("/restoration/generated") } })
        await engine.stop()
    }
}
