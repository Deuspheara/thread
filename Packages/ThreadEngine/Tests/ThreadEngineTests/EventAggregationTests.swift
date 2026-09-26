import Foundation
import Testing
import ThreadDomain
@testable import ThreadEngine

struct EventAggregationTests {
    let epoch = Date(timeIntervalSince1970: 1_000)
    let session = TerminalSessionIdentity(rawValue: UUID())

    func event(_ kind: ActivityEventKind, _ second: Double, source: String = "test") -> ActivityEvent {
        ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: epoch.addingTimeInterval(second),
                      source: ActivitySourceID(rawValue: source), kind: kind)
    }
    func terminal(_ path: String, sequence: UInt64) -> TerminalContext {
        TerminalContext(session: session, processIdentifier: 1, workingDirectory: path, terminalApplication: nil, sequence: sequence)
    }
    func repo(_ path: String, branch: String = "main", sequence: UInt64) -> ActivityEventKind {
        .repositoryChanged(RepositoryObservation(terminal: session, sequence: sequence, resolution: .available(
            RepositoryContext(identity: RepositoryIdentity(commonDirectory: path + "/.git"), rootPath: path,
                              gitDirectory: path + "/.git", branch: branch, head: nil,
                              dirty: RepositoryDirtySummary(changedTrackedFiles: 0, conflictedFiles: 0)))))
    }
    func tab(_ connection: UUID = UUID(), url: String = "https://example.com/docs") -> BrowserTabContext {
        BrowserTabContext(identity: BrowserTabIdentity(connection: BrowserConnectionIdentity(rawValue: connection), tab: 1),
                          browser: .safari, window: 1, url: url, domain: "example.com", title: "Docs", isActive: true)
    }

    @Test func focusedDocumentBecomesFileEvidence() throws {
        var aggregator = EventAggregator()
        let app = ApplicationContext(identity: ApplicationIdentity(bundleIdentifier: "com.microsoft.VSCode"), name: "Code", processIdentifier: 12)
        let document = FileIdentity(path: "/work/team.code-workspace")
        let window = WindowContext(identity: WindowIdentity(rawValue: UUID()), application: app, title: "Team", frame: nil, document: document)
        _ = aggregator.ingest(event(.accessibilityPermissionChanged(.granted), 0), at: epoch)
        _ = aggregator.ingest(event(.applicationActivated(app), 0), at: epoch)
        _ = aggregator.ingest(event(.windowFocused(window), 0.1), at: epoch.addingTimeInterval(0.1))
        let context = try #require(aggregator.advance(to: epoch.addingTimeInterval(3)).first)
        #expect(context.resources.contains { $0.resource == .file(document) })
        var evidence = ActivityEvidenceWindow()
        evidence.record([.window(window), .file(document)], source: ActivitySourceID(rawValue: "test"), at: epoch, limit: 10)
        evidence.invalidate(for: .accessibilityPermissionChanged(.notGranted))
        #expect(evidence.entries.isEmpty)
    }

    @Test func combinesSourcesAfterQuietPeriodAndDoesNotRepeatedlyEmitIdleContext() throws {
        var aggregator = EventAggregator()
        let shell = event(.terminalDirectoryChanged(terminal("/work/project", sequence: 1)), 0)
        #expect(aggregator.ingest(shell, at: epoch).isEmpty)
        #expect(aggregator.ingest(event(repo("/work/project", sequence: 1), 0.5), at: epoch.addingTimeInterval(0.5)).isEmpty)
        #expect(aggregator.ingest(event(.browserTabActivated(tab()), 1), at: epoch.addingTimeInterval(1)).isEmpty)
        #expect(aggregator.advance(to: epoch.addingTimeInterval(2.9)).isEmpty)
        let context = try #require(aggregator.advance(to: epoch.addingTimeInterval(3)).first)
        #expect(Set(context.resources.map { $0.resource.kind }) == [.terminal, .workingDirectory, .repository, .branch, .browserPage])
        #expect(context.endedAt == epoch.addingTimeInterval(3))
        #expect(aggregator.advance(to: epoch.addingTimeInterval(100)).isEmpty)
        #expect(aggregator.nextDeadline == nil)
    }

    @Test func repositorySwitchSeparatesOldResourcesAndRejectsDelayedGitResult() throws {
        var aggregator = EventAggregator()
        _ = aggregator.ingest(event(.terminalDirectoryChanged(terminal("/work/A", sequence: 1)), 0), at: epoch)
        _ = aggregator.ingest(event(repo("/work/A", sequence: 1), 0.2), at: epoch.addingTimeInterval(0.2))
        let previous = aggregator.ingest(event(.terminalDirectoryChanged(terminal("/work/B", sequence: 2)), 1), at: epoch.addingTimeInterval(1))
        #expect(previous.count == 1)
        _ = aggregator.ingest(event(repo("/work/A", sequence: 1), 1.1), at: epoch.addingTimeInterval(1.1))
        _ = aggregator.ingest(event(repo("/work/B", sequence: 2), 1.2), at: epoch.addingTimeInterval(1.2))
        let current = try #require(aggregator.advance(to: epoch.addingTimeInterval(4)).first)
        #expect(current.resources.contains { $0.resource.id == .workingDirectory("/work/B") })
        #expect(!current.resources.contains { $0.resource.id == .workingDirectory("/work/A") })
        #expect(!current.resources.contains { $0.resource.id == .repository(RepositoryIdentity(commonDirectory: "/work/A/.git")) })
    }

    @Test func privateFocusClearRemovesBrowserEvidenceAndBackgroundInventoryNeverEntersContext() throws {
        var aggregator = EventAggregator()
        let active = tab()
        _ = aggregator.ingest(event(.terminalDirectoryChanged(terminal("/work", sequence: 1)), 0), at: epoch)
        _ = aggregator.ingest(event(.browserTabActivated(active), 0.2), at: epoch.addingTimeInterval(0.2))
        _ = aggregator.ingest(event(.browserTabOpened(tab(url: "https://example.com/background")), 0.3), at: epoch.addingTimeInterval(0.3))
        _ = aggregator.ingest(event(.browserFocusCleared(active.identity.connection), 0.5), at: epoch.addingTimeInterval(0.5))
        let context = try #require(aggregator.advance(to: epoch.addingTimeInterval(3)).first)
        #expect(!context.resources.contains { $0.resource.kind == .browserPage })
    }

    @Test func boundsContinuousActivityAndExpiresOldEvidence() throws {
        var aggregator = EventAggregator(policy: AggregationPolicy(quietInterval: 2, maximumBatchInterval: 4,
                                                                   evidenceLifetime: 5, maximumResources: 3))
        var batches: [ActivityContext] = []
        for second in 0...6 {
            batches += aggregator.ingest(event(.browserTabActivated(tab(url: "https://example.com/\(second)")), Double(second)),
                                         at: epoch.addingTimeInterval(Double(second)))
        }
        #expect(batches.count == 1)
        #expect(batches[0].endedAt == epoch.addingTimeInterval(4))
        #expect(batches[0].resources.count == 3)
        _ = aggregator.advance(to: epoch.addingTimeInterval(20))
        _ = aggregator.ingest(event(.terminalDirectoryChanged(terminal("/new", sequence: 1)), 21), at: epoch.addingTimeInterval(21))
        let context = try #require(aggregator.advance(to: epoch.addingTimeInterval(23)).first)
        #expect(context.resources.allSatisfy { $0.resource.kind != .browserPage })
    }

    @Test func duplicateAndOutOfOrderInputsCannotExtendBatchDeadline() {
        var aggregator = EventAggregator()
        let original = event(.browserTabActivated(tab()), 2)
        _ = aggregator.ingest(original, at: epoch.addingTimeInterval(2))
        _ = aggregator.ingest(original, at: epoch.addingTimeInterval(3))
        _ = aggregator.ingest(event(.browserTabActivated(tab()), 1), at: epoch.addingTimeInterval(3))
        #expect(aggregator.nextDeadline == epoch.addingTimeInterval(4))
        #expect(aggregator.advance(to: epoch.addingTimeInterval(4)).count == 1)
    }

    @Test func branchChangePreservesCurrentTerminalButDropsPreviousResearch() throws {
        var aggregator = EventAggregator()
        _ = aggregator.ingest(event(.terminalDirectoryChanged(terminal("/work/A", sequence: 1)), 0), at: epoch)
        _ = aggregator.ingest(event(repo("/work/A", branch: "main", sequence: 1), 0.2), at: epoch.addingTimeInterval(0.2))
        _ = aggregator.ingest(event(.browserTabActivated(tab()), 0.3), at: epoch.addingTimeInterval(0.3))
        _ = aggregator.advance(to: epoch.addingTimeInterval(3))
        _ = aggregator.ingest(event(.terminalCommandCompleted(terminal("/work/A", sequence: 2), 0), 4), at: epoch.addingTimeInterval(4))
        _ = aggregator.ingest(event(repo("/work/A", branch: "fix", sequence: 2), 4.2), at: epoch.addingTimeInterval(4.2))
        let context = try #require(aggregator.advance(to: epoch.addingTimeInterval(7)).first)
        #expect(context.resources.contains { $0.resource.id == .terminal(session) })
        #expect(context.resources.contains { $0.resource.id == .branch(RepositoryIdentity(commonDirectory: "/work/A/.git"), "fix") })
        #expect(!context.resources.contains { $0.resource.kind == .browserPage })
    }

    @Test func durableIdentitiesSurviveConnectionChangesAndNormalizeLexicalPaths() {
        #expect(Resource.browserPage(tab()).id == Resource.browserPage(tab()).id)
        #expect(Resource.browserPage(tab(url: "https://EXAMPLE.com:443")).id == Resource.browserPage(tab(url: "https://example.com/")).id)
        #expect(Resource.workingDirectory("/work/a/../project/").id == Resource.workingDirectory("/work/project").id)
        let repository = RepositoryIdentity(commonDirectory: "/work/project/.git")
        #expect(Resource.branch(repository, "main").id != Resource.branch(repository, "fix").id)
        #expect(Resource.terminal(terminal("/one", sequence: 1)).id == Resource.terminal(terminal("/two", sequence: 2)).id)
    }
}
