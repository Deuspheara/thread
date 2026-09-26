import Foundation
import Testing
import ThreadDomain
import ThreadEngine
import ThreadDecisions
import ThreadPersistence

struct ObservationPrivacyPipelineTests {
    @Test func excludedActivityNeverReachesSavedEventsOrGraph() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record("Privacy fixture cleanup failed") }
        }
        let database = ThreadDatabase(directory: directory)
        try await database.prepare()
        let graph = ThreadGraphStore()
        let engine = ActivityEngine(graph: graph, decisions: HeuristicDecisionEngine(), repository: database, archive: database)
        try await engine.prepareHistory()
        let rules = try ObservationExclusions(applications: ["com.apple.terminal"], domains: ["secret.test"])
        let session = ObservationSession(exclusions: rules, onEvent: { await engine.ingest($0) })
        let terminal = TerminalContext(session: TerminalSessionIdentity(rawValue: UUID()), processIdentifier: 1,
                                       workingDirectory: "/private/project", terminalApplication: "com.apple.Terminal", sequence: 1)
        let tab = BrowserTabContext(identity: BrowserTabIdentity(connection: BrowserConnectionIdentity(rawValue: UUID()), tab: 1),
                                    browser: .chrome, window: 1, url: "https://secret.test/path", domain: "secret.test",
                                    title: "Sensitive", isActive: true)
        let kinds: [ActivityEventKind] = [.terminalDirectoryChanged(terminal),
            .repositoryChanged(RepositoryObservation(terminal: terminal.session, sequence: 1, resolution: .notRepository)),
            .browserTabActivated(tab)]
        let events = kinds.map {
            ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: Date(), source: ActivitySourceID(rawValue: "fixture"), kind: $0)
        }
        await session.run(sources: [PrivacyFixtureSource(values: events)])
        await engine.stop()
        #expect(await graph.details().isEmpty)
        #expect(try await database.loadGraph().threads.isEmpty)
        #expect(try await database.events(since: .distantPast, limit: 10).isEmpty)
        for await context in session.contexts() {
            #expect(context.terminal == nil)
            #expect(context.browserTab == nil)
        }
    }
}

private struct PrivacyFixtureSource: ActivitySource {
    let values: [ActivityEvent]
    func events() -> AsyncStream<ActivityEvent> {
        AsyncStream { continuation in
            values.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}
