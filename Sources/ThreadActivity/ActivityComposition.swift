import Foundation
import ThreadDomain
import ThreadEngine
import ThreadRestore
import ThreadDecisions
import ThreadMacOS
import ThreadPersistence
import ThreadShell
import ThreadGit
import ThreadBrowser
import OSLog

/// Constructs the app's dependency graph without exposing a global dependency container.
@MainActor
public enum ActivityComposition {
    public static func make(directory: URL, appBundle: Bundle) -> ActivitySession {
        let remoteSetup = RemoteInferenceSetup(directory: directory)
        let database = ThreadDatabase(directory: directory)
        let workspace = WorkspaceActivitySource(excluding: "app.thread.desktop")
        let accessibility = AccessibilityActivitySource(excluding: "app.thread.desktop")
        let shell = ShellActivitySource(url: directory.appendingPathComponent("Shell/activity.sock"))
        let git = GitActivitySource(upstream: shell)
        let safari = safariSource(bundle: appBundle)
        let graph = ThreadGraphStore()
        let decisionRecords = DecisionRecordBuffer(archive: database, onFailure: { failure in
            let logger = Logger(subsystem: "app.thread.desktop", category: "classification")
            switch failure {
            case .invalidRecord: logger.error("Invalid decision record rejected")
            case .backlogOverflow: logger.error("Decision recording backlog limit reached")
            case .writeUnavailable: logger.error("Decision recording unavailable; pending records retained")
            }
        })
        let applications = MembershipApplicationJournal(archive: database, onFailure: { failure in
            let logger = Logger(subsystem: "app.thread.desktop", category: "classification")
            switch failure {
            case .invalidRecord: logger.error("Invalid membership application record rejected")
            case .backlogOverflow: logger.error("Membership application recording backlog limit reached")
            case .writeUnavailable: logger.error("Membership application recording unavailable; records retained")
            }
        })
        let transitions = TransitionApplicationJournal(archive: database, onFailure: { failure in
            let logger = Logger(subsystem: "app.thread.desktop", category: "classification")
            switch failure {
            case .invalidRecord: logger.error("Invalid transition application record rejected")
            case .backlogOverflow: logger.error("Transition application recording backlog limit reached")
            case .writeUnavailable: logger.error("Transition application recording unavailable; records retained")
            }
        })
        let reassignments = ResourceReassignmentJournal(archive: database, onFailure: { failure in
            let logger = Logger(subsystem: "app.thread.desktop", category: "classification")
            switch failure {
            case .invalidRecord: logger.error("Invalid resource reassignment record rejected")
            case .backlogOverflow: logger.error("Resource reassignment recording backlog limit reached")
            case .writeUnavailable: logger.error("Resource reassignment recording unavailable; records retained")
            }
        })
        let decisions = HybridDecisionEngine(remoteProvider: { await remoteSetup.connection.availableEngine() },
            onDecision: { await decisionRecords.record($0) }, onFallback: { reason in
            let logger = Logger(subsystem: "app.thread.desktop", category: "classification")
            switch reason {
            case .remoteUnavailable: logger.notice("Remote inference unavailable; using local decision")
            case .invalidResponse: logger.error("Remote inference response rejected; using local decision")
            }
        })
        let preferences = ObservationPreferencesFile(directory: directory)
        let initialExclusions: ObservationExclusions?
        do { initialExclusions = try preferences.load() }
        catch {
            initialExclusions = nil
            Logger(subsystem: "app.thread.desktop", category: "permissions").error("Privacy rules unavailable; observation paused")
        }
        let engine = ActivityEngine(graph: graph, decisions: decisions, repository: database, archive: database,
            onMembershipApplication: { await applications.record($0) },
            onTransitionApplication: { await transitions.record($0) },
            onResourceReassignment: { await reassignments.record($0) })
        let session = ObservationSession(exclusions: initialExclusions, onEvent: { await engine.ingest($0) })
        var restorers: [any ResourceRestorer] = [ApplicationRestorer(), VSCodeRestorer(), FileRestorer(),
            BrowserTabRestorer(directory: directory.appendingPathComponent("Browser")), BrowserRestorer(),
            TerminalRestorer(), WindowRestorer()]
        if let safari, let group = appBundle.object(forInfoDictionaryKey: "ThreadAppGroupIdentifier") as? String,
           let endpoint = try? BrowserSocketLocation.safariURL(groupIdentifier: group) {
            restorers.insert(SafariTabRestorer(directory: endpoint.deletingLastPathComponent(),
                extensionIdentifier: "app.thread.desktop.safari", connected: { safari.isConnected($0) }), at: 3)
        }
        let directoryIdentity = DirectoryRestoreIdentity()
        let restoration = ThreadRestoration(graph: graph, restorers: restorers, focus: engine,
            directoryIdentity: { directoryIdentity.canonicalPath($0) })
        let sources = ObservationSources(workspace: workspace, accessibility: accessibility, shell: shell, git: git,
            browser: BrowserActivitySource(url: directory.appendingPathComponent("Browser/activity.sock")), safari: safari)
        let activity = ActivityRuntime(sources: sources, session: session, engine: engine, reading: graph,
            prepareStorage: {
                do {
                    try await prepare(database)
                    await remoteSetup.prepare()
                    await decisionRecords.prepare()
                    await applications.prepare()
                    await transitions.prepare()
                    await reassignments.prepare()
                    try Task.checkCancellation()
                    try await engine.prepareHistory()
                }
                catch {
                    await engine.historyPreparationFailed()
                    Logger(subsystem: "app.thread.desktop", category: "persistence").error("History initialization unavailable")
                    throw error
                }
            }, flushRecords: {
                await decisionRecords.flush()
                await applications.flush()
                await transitions.flush()
                await reassignments.flush()
            })
        return ActivitySession(runtime: activity, search: database, restoration: restoration, remote: remoteSetup,
            loadExclusions: { try preferences.load() }, saveExclusions: { value in
                try preferences.save(value)
                await session.setExclusions(value, at: Date())
            }, refresh: { workspace.refresh(); accessibility.refresh() },
            requestPermission: { accessibility.requestPermission() })
    }

    private static func safariSource(bundle: Bundle) -> BrowserActivitySource? {
        guard let group = bundle.object(forInfoDictionaryKey: "ThreadAppGroupIdentifier") as? String,
              !group.isEmpty else { return nil }
        do { return BrowserActivitySource(url: try BrowserSocketLocation.safariURL(groupIdentifier: group)) }
        catch {
            Logger(subsystem: "app.thread.desktop", category: "browser").error("Safari App Group unavailable")
            return nil
        }
    }

    private static func prepare(_ database: ThreadDatabase) async throws {
        let logger = Logger(subsystem: "app.thread.desktop", category: "persistence")
        do {
            try await database.prepare()
            logger.info("Local storage prepared")
        } catch {
            switch error as? StorageError {
            case .directoryUnavailable: logger.error("Storage directory unavailable")
            case .databaseUnavailable: logger.error("Database unavailable")
            case .migrationFailed: logger.error("Database migration failed")
            case nil: logger.error("Unexpected storage initialization failure")
            }
            throw error
        }
    }
}
