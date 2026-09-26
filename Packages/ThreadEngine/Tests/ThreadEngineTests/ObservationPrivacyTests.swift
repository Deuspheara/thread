import Foundation
import Testing
import ThreadDomain
@testable import ThreadEngine

struct ObservationPrivacyTests {
    @Test func domainBoundaryUsesURLHostAndRejectsInvalidRules() throws {
        let rules = try ObservationExclusions(applications: [], domains: ["EXAMPLE.COM"])
        #expect(rules.excludes(url: "https://docs.example.com/help"))
        #expect(rules.excludes(url: "https://example.com./help"))
        #expect(!rules.excludes(url: "https://notexample.com/help"))
        #expect(!rules.excludes(url: "https://example.com.evil.test/help"))
        #expect(throws: ExclusionError.self) {
            try ObservationExclusions(applications: [], domains: ["https://example.com"])
        }
        #expect(throws: ExclusionError.self) {
            try ObservationExclusions(applications: [], domains: Array(repeating: "example.com", count: 65))
        }
    }

    @Test func excludedTabsAndShellGitCarryNoSensitiveMetadata() throws {
        let rules = try ObservationExclusions(applications: ["com.apple.terminal"], domains: ["secret.test"])
        var filter = ObservationPrivacyFilter(exclusions: rules)
        let tab = BrowserTabContext(identity: BrowserTabIdentity(connection: BrowserConnectionIdentity(rawValue: UUID()), tab: 1),
                                    browser: .chrome, window: 1, url: "https://secret.test/path", domain: "forged.test",
                                    title: "Sensitive", isActive: true)
        #expect(filter.screen(event(.browserTabActivated(tab)))?.kind == .observationCleared)
        let session = TerminalSessionIdentity(rawValue: UUID())
        let terminal = TerminalContext(session: session, processIdentifier: 1, workingDirectory: "/private/project",
                                       terminalApplication: "com.apple.Terminal", sequence: 1)
        #expect(filter.screen(event(.terminalDirectoryChanged(terminal)))?.kind == .observationCleared)
        #expect(filter.screen(event(.repositoryChanged(RepositoryObservation(terminal: session, sequence: 1,
                                                                             resolution: .notRepository)))) == nil)
        var paused = ObservationPrivacyFilter(exclusions: nil)
        #expect(paused.screen(event(.browserTabActivated(tab))) == nil)
        #expect(paused.screen(event(.accessibilityPermissionChanged(.granted))) != nil)
    }

    @Test func privacyBoundaryDiscardsUnemittedEvidenceAndVisibleContext() {
        let application = ApplicationContext(identity: ApplicationIdentity(bundleIdentifier: "app.test"),
                                             name: "Sensitive", processIdentifier: 1)
        var aggregator = EventAggregator()
        let start = Date(timeIntervalSince1970: 10)
        #expect(aggregator.ingest(event(.applicationActivated(application), at: start), at: start).isEmpty)
        let boundary = start.addingTimeInterval(1)
        #expect(aggregator.ingest(event(.observationCleared, at: boundary), at: boundary).isEmpty)
        #expect(aggregator.nextDeadline == nil)
        #expect(aggregator.advance(to: start.addingTimeInterval(20)).isEmpty)
        var reducer = CurrentContextReducer()
        reducer.apply(event(.accessibilityPermissionChanged(.granted), at: start))
        reducer.apply(event(.applicationActivated(application), at: start))
        reducer.apply(event(.observationCleared, at: boundary))
        #expect(reducer.context.application == nil)
        #expect(reducer.context.permission == .granted)
    }

    @Test func browserVariantExclusionUsesNativeIdentityRatherThanCanonicalFamily() throws {
        var filter = ObservationPrivacyFilter(exclusions: try ObservationExclusions(
            applications: ["com.google.Chrome.canary"], domains: []))
        let identity = BrowserTabIdentity(connection: BrowserConnectionIdentity(rawValue: UUID()), tab: 1)
        func tab(_ identifier: String?) -> BrowserTabContext {
            BrowserTabContext(identity: identity, browser: .chrome, window: 1, url: "https://example.com/",
                domain: "example.com", title: "Example", isActive: true,
                application: identifier.map { ApplicationIdentity(bundleIdentifier: $0) })
        }
        #expect(filter.screen(event(.browserTabActivated(tab("com.google.Chrome.canary"))))?.kind == .observationCleared)
        #expect(filter.screen(event(.browserTabActivated(tab("com.google.Chrome"))))?.kind != .observationCleared)
        #expect(filter.screen(event(.browserTabActivated(tab(nil))))?.kind != .observationCleared)
    }

    private func event(_ kind: ActivityEventKind, at time: Date = Date(timeIntervalSince1970: 10)) -> ActivityEvent {
        ActivityEvent(id: ActivityEventID(rawValue: UUID()), timestamp: time,
                      source: ActivitySourceID(rawValue: "fixture"), kind: kind)
    }
}
