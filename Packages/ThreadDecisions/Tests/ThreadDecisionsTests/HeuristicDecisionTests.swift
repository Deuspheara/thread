import Foundation
import Testing
import ThreadDomain
import ThreadDecisions

struct HeuristicDecisionTests {
    let now = Date(timeIntervalSince1970: 100)
    let engine = HeuristicDecisionEngine()
    func context(_ resource: Resource, duration: Double = 0) -> ActivityContext {
        ActivityContext(startedAt: now.addingTimeInterval(-duration), endedAt: now, resources: [
            ResourceEvidence(resource: resource, firstSeen: now.addingTimeInterval(-duration), lastSeen: now,
                             source: ActivitySourceID(rawValue: "test"))])
    }
    func candidate(_ resource: Resource, score: Double, signals: [CandidateSignal]) -> ScoredThreadCandidate {
        ScoredThreadCandidate(candidate: ThreadCandidate(id: ThreadID(rawValue: UUID()), title: "Work", lastActiveAt: now,
                                                        resourceIDs: [resource.id]), relevance: score, signals: signals)
    }

    @Test func clearMatchAndAmbiguousAlternativesHaveDifferentOutcomes() async throws {
        let resource = Resource.workingDirectory("/work/project")
        let first = candidate(resource, score: 0.96, signals: [.sameDirectory])
        let clear = try await engine.classifyMembership(context: context(resource), candidates: [first])
        #expect(clear.target == .existing(first.candidate.id))
        #expect(clear.confidence >= 0.96)
        let second = candidate(resource, score: 0.94, signals: [.sameDirectory])
        let ambiguous = try await engine.classifyMembership(context: context(resource), candidates: [second, first])
        #expect(ambiguous.target == .undetermined)
    }

    @Test func ticketOnlyMatchStaysProvisionalAndDuplicateTicketsRemainAmbiguous() async throws {
        let resource = Resource.branch(RepositoryIdentity(commonDirectory: "/work/.git"), "fix/HC-418")
        let first = candidate(resource, score: 0.76, signals: [.sameTicket])
        let decision = try await engine.classifyMembership(context: context(resource), candidates: [first])
        #expect(decision.target == .existing(first.candidate.id))
        #expect(decision.confidence >= 0.72 && decision.confidence < 0.92)
        let other = candidate(resource, score: 0.74, signals: [.sameTicket])
        #expect(try await engine.classifyMembership(context: context(resource), candidates: [first, other]).target == .undetermined)
    }

    @Test func repositoryCreatesThreadButIncidentalDirectoryWaitsForMoreEvidence() async throws {
        let resource = Resource.repository(RepositoryContext(identity: RepositoryIdentity(commonDirectory: "/work/.git"),
                                                             rootPath: "/work", gitDirectory: "/work/.git", branch: "fix", head: nil,
                                                             dirty: RepositoryDirtySummary(changedTrackedFiles: 0, conflictedFiles: 0)))
        #expect(try await engine.classifyMembership(context: context(resource), candidates: []).target == .newThread)
        let directory = Resource.workingDirectory("/work")
        #expect(try await engine.classifyMembership(context: context(directory), candidates: []).target == .undetermined)
        #expect(try await engine.classifyMembership(context: context(directory, duration: 21), candidates: []).target == .newThread)
    }

    @Test func restorableWindowMetadataIsDurableButUnidentifiableWindowsRemainSessionOnly() async throws {
        let application = ApplicationContext(identity: ApplicationIdentity(bundleIdentifier: "app.editor"),
            name: "Editor", processIdentifier: 1, launchDate: now)
        let window = Resource.window(WindowContext(identity: WindowIdentity(rawValue: UUID()),
            application: application, title: "Project.swift", frame: WindowFrame(x: 0, y: 0, width: 500, height: 300)))
        #expect(try await engine.classifyPersistence(resource: window, context: context(window)).disposition == .durable)
        let unknown = Resource.window(WindowContext(identity: WindowIdentity(rawValue: UUID()),
            application: application, title: nil, frame: nil))
        #expect(try await engine.classifyPersistence(resource: unknown, context: context(unknown)).disposition == .sessionOnly)
    }

    @Test func briefBrowserVisitCannotSwitchActiveThreadButSustainedResearchCan() async throws {
        let resource = Resource.browserPage(BrowserTabContext(identity: BrowserTabIdentity(connection: BrowserConnectionIdentity(rawValue: UUID()), tab: 1),
                                                            browser: .safari, window: 1, url: "https://example.com/", domain: "example.com", title: "Research", isActive: true))
        let known = candidate(resource, score: 0.76, signals: [.sameBrowserPage])
        let brief = try await engine.classifyMembership(context: context(resource), candidates: [known])
        #expect(brief.confidence < 0.92)
        let sustained = context(resource, duration: 21)
        let decision = try await engine.classifyMembership(context: sustained, candidates: [known])
        #expect(decision.confidence >= 0.96)
        #expect(try await engine.detectTransition(context: sustained, active: nil, membership: decision).shouldTransition)
    }
}
